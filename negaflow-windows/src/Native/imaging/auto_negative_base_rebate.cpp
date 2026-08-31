#include "auto_negative_base_rebate.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <limits>
#include <vector>

namespace negaflow::imaging::auto_base_detail {
namespace {

// `film_base_sampling` 의 `[base-cc]` 와 같은 관문입니다. 구조길이 왜 물러났는지는 자리마다
// 갈라 놓지 않으면 "안 고쳐졌다" 한 줄로만 남습니다.
[[nodiscard]] bool rebate_debug_enabled() noexcept {
    std::size_t length = 0U;
    return getenv_s(&length, nullptr, 0U, "NEGA_DEBUG") == 0 && length > 0U;
}

using film_base_detail::BaseMeasurement;
using film_base_detail::SampleGrid;
using film_base_detail::coherent_measurement;
using film_base_detail::is_component_candidate;
using film_base_detail::luma_of;

// 줄 길이의 이만큼이 **연속으로** 이어져야 그 줄이 수준 L 을 유지한 것으로 봅니다.
// 리베이트는 필름 폭을 가로지르므로 버티고, 먼지·흠집은 짧아서 못 버팁니다.
constexpr double run_fraction = 0.10;
constexpr std::size_t minimum_run = 4U;

// 찾은 띠가 이보다 두꺼우면 리베이트가 아니라 장면입니다. 기각하면 기존 값이 남습니다.
constexpr double maximum_band_fraction = 0.25;

// 최고 수준의 이 비율 위까지를 같은 띠로 봅니다.
constexpr double band_level_ratio = 0.90;

// 원본에서 이보다 많이 모이면 건너뛰며 읽습니다. 중앙값을 내는 데 필요한 것은 분포이지
// 화소 수가 아니고, 이 상한이 띠가 넓게 잡힌 최악의 경우에 비용을 묶어 둡니다.
// 5 만이면 리베이트 한 줄에서만 만 단위 표본이 나와 중앙값이 흔들리지 않습니다.
constexpr std::size_t measurement_sample_cap = 50000U;

/// 창 크기 <paramref name="window"/> 안 최솟값들의 최댓값입니다.
///
/// 후보가 아닌 칸은 0 으로 들어오므로 그 칸을 품은 창은 전부 0 이 되어 탈락합니다. 단조
/// 덱이라 줄 길이에 선형이고 분기가 없습니다.
[[nodiscard]] double sustained_level(
    const std::vector<double>& line,
    const std::size_t window) noexcept {
    if (window == 0U || line.size() < window) {
        return 0.0;
    }
    std::deque<std::size_t> ascending;
    double best = 0.0;
    for (std::size_t index = 0U; index < line.size(); ++index) {
        while (!ascending.empty() && line[ascending.back()] >= line[index]) {
            ascending.pop_back();
        }
        ascending.push_back(index);
        if (ascending.front() + window <= index) {
            ascending.pop_front();
        }
        if (index + 1U >= window) {
            best = std::max(best, line[ascending.front()]);
        }
    }
    return best;
}

/// 격자 한 줄의 값입니다 — 후보가 아니면 0 입니다.
void fill_line(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const bool horizontal,
    const std::uint32_t position,
    std::vector<double>& line) {
    const std::uint32_t length = horizontal ? grid.width : grid.height;
    line.resize(length);
    for (std::uint32_t step = 0U; step < length; ++step) {
        const std::size_t index = horizontal
            ? static_cast<std::size_t>(position) * grid.width + step
            : static_cast<std::size_t>(step) * grid.width + position;
        line[step] = is_component_candidate(grid.pixels[index], film_type)
            ? grid.lumas[index]
            : 0.0;
    }
}

struct Band final {
    bool horizontal{true};
    std::uint32_t first{};
    std::uint32_t last{};
    double level{};
};

/// 축소본에서 리베이트 띠의 **자리** 를 찾습니다. 값은 여기서 읽지 않습니다.
[[nodiscard]] std::optional<Band> locate_band(
    const SampleGrid& grid,
    const NegativeFilmType film_type) {
    std::optional<Band> best;
    std::vector<double> line;
    std::vector<double> levels;
    for (const bool horizontal : {true, false}) {
        const std::uint32_t count = horizontal ? grid.height : grid.width;
        const std::uint32_t length = horizontal ? grid.width : grid.height;
        const std::size_t window = std::max(
            minimum_run, static_cast<std::size_t>(static_cast<double>(length) * run_fraction));
        levels.assign(count, 0.0);
        for (std::uint32_t position = 0U; position < count; ++position) {
            fill_line(grid, film_type, horizontal, position, line);
            levels[position] = sustained_level(line, window);
        }
        const auto peak = std::max_element(levels.begin(), levels.end());
        if (peak == levels.end() || *peak <= 0.0) {
            continue;
        }
        if (best.has_value() && *peak <= best->level) {
            continue;
        }
        // 같은 띠로 볼 줄들을 최고점 양옆으로 넓힙니다. 띠에 기울기가 있으면 유지수준이
        // 줄마다 조금씩 다르므로 한 줄만 잡으면 재는 표본이 너무 적습니다.
        const auto index = static_cast<std::uint32_t>(std::distance(levels.begin(), peak));
        const double floor_level = *peak * band_level_ratio;
        std::uint32_t first = index;
        std::uint32_t last = index;
        while (first > 0U && levels[first - 1U] >= floor_level) {
            --first;
        }
        while (last + 1U < count && levels[last + 1U] >= floor_level) {
            ++last;
        }
        if (rebate_debug_enabled()) {
            std::fprintf(
                stderr,
                "[base-rebate] %s window=%zu peak=%.6f at=%u band=%u..%u of %u\n",
                horizontal ? "rows" : "cols", window, *peak, index, first, last, count);
        }
        // 두꺼우면 리베이트가 아니라 장면을 집은 것입니다.
        if (static_cast<double>(last - first + 1U) >
            static_cast<double>(count) * maximum_band_fraction) {
            continue;
        }
        best = Band{horizontal, first, last, *peak};
    }
    return best;
}

/// 찾은 자리를 **원본 해상도** 로 되돌려 그 안에서 다시 잽니다.
[[nodiscard]] std::optional<BaseMeasurement> measure_band(
    const WorkingImage& image,
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const Band& band) {
    const std::uint32_t grid_count = band.horizontal ? grid.height : grid.width;
    const std::uint32_t image_count = band.horizontal ? image.height : image.width;
    if (grid_count == 0U || image_count == 0U) {
        return std::nullopt;
    }
    const double scale = static_cast<double>(image_count) / static_cast<double>(grid_count);
    const auto begin = static_cast<std::uint32_t>(
        std::floor(static_cast<double>(band.first) * scale));
    const auto end = std::min(
        image_count,
        static_cast<std::uint32_t>(std::ceil(static_cast<double>(band.last + 1U) * scale)));
    if (begin >= end) {
        return std::nullopt;
    }
    const std::uint32_t across = band.horizontal ? image.width : image.height;
    const std::size_t total = static_cast<std::size_t>(end - begin) * across;
    const std::size_t stride = std::max<std::size_t>(1U, total / measurement_sample_cap);

    std::vector<negaflow::core::Rgba32F> pixels;
    std::vector<std::size_t> selected;
    pixels.reserve(std::min(total, measurement_sample_cap) + 1U);
    std::size_t visited = 0U;
    for (std::uint32_t along = begin; along < end; ++along) {
        for (std::uint32_t step = 0U; step < across; ++step, ++visited) {
            if (visited % stride != 0U) {
                continue;
            }
            const std::uint32_t x = band.horizontal ? step : along;
            const std::uint32_t y = band.horizontal ? along : step;
            const negaflow::core::Rgba32F pixel =
                image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x];
            if (!is_component_candidate(pixel, film_type)) {
                continue;
            }
            selected.push_back(pixels.size());
            pixels.push_back(pixel);
        }
    }
    if (rebate_debug_enabled()) {
        std::fprintf(
            stderr,
            "[base-rebate] measure %s %u..%u of %u  visited=%zu stride=%zu candidates=%zu\n",
            band.horizontal ? "rows" : "cols", begin, end, image_count, visited, stride,
            selected.size());
    }
    if (selected.size() < 24U) {
        return std::nullopt;
    }
    // 밝은 위 절반의 채널 중앙값 — 기존 경로가 쓰는 그 계산 그대로입니다. 다만 **전체를
    // 정렬할 이유가 없습니다.** 필요한 것은 "위 절반이 누구냐" 뿐이라 경계만 제자리에 놓습니다.
    const std::size_t keep = std::max(selected.size() / 2U, std::size_t{24U});
    if (keep < selected.size()) {
        std::nth_element(
            selected.begin(),
            selected.begin() + static_cast<std::ptrdiff_t>(keep),
            selected.end(),
            [&pixels](const std::size_t left, const std::size_t right) {
                return luma_of(pixels[left]) > luma_of(pixels[right]);
            });
    }
    selected.resize(keep);
    return coherent_measurement(pixels, selected);
}

}  // namespace

double brighter_than_base_fraction(
    const SampleGrid& grid,
    const std::array<float, 3>& dmin) noexcept {
    if (grid.lumas.empty()) {
        return 0.0;
    }
    const negaflow::core::Rgba32F base{dmin[0], dmin[1], dmin[2], 1.0F};
    if (!film_base_detail::finite_rgb(base)) {
        return 0.0;
    }
    const double level = luma_of(base);
    std::size_t brighter = 0U;
    for (const double luma : grid.lumas) {
        if (luma > level) {
            ++brighter;
        }
    }
    return static_cast<double>(brighter) / static_cast<double>(grid.lumas.size());
}

std::optional<BaseMeasurement> rebate_base(
    const WorkingImage& image,
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const bool gate_open) {
    if (!film_base_detail::has_compatible_layout(image) || grid.pixels.empty()) {
        return std::nullopt;
    }
    const std::optional<Band> band = locate_band(grid, film_type);
    if (!band.has_value()) {
        return std::nullopt;
    }
    // 축소본에서 이만큼 얇은 띠는 이웃과 평균되어 값이 뭉개집니다. 뭉개진 값은 장면보다는
    // 밝아 문지기에 안 걸리므로, 얇다는 것 자체를 원본을 볼 이유로 삼습니다.
    const std::uint32_t span = band->last - band->first + 1U;
    const std::uint32_t grid_count = band->horizontal ? grid.height : grid.width;
    const std::uint32_t image_count = band->horizontal ? image.height : image.width;
    const bool diluted = span <= 2U && grid_count > 0U && image_count / grid_count >= 3U;
    if (!gate_open && !diluted) {
        return std::nullopt;
    }
    const std::optional<BaseMeasurement> measured =
        measure_band(image, grid, film_type, *band);
    // **색으로는 거르지 않습니다.** 홀더를 지난 빛(R/B 1.5)과 C-41 베이스(R/B 4.7)를 가르는
    // 문턱을 두고 싶었지만, 코드가 이미 들고 있는 필름 표에 Harman Phoenix 200 (R/B 1.51)
    // 과 ORWO Wolfen NC400 (1.41) 이 있습니다 — 마스크가 옅은 진짜 컬러 네거티브가 홀더와
    // 같은 값입니다. 문턱을 두면 그 필름들이 죽습니다.
    //
    // 대신 실제로 좋아지는지를 봤습니다. 홀더 띠가 잡힌 사진도 바꾸면 현상 중앙값이 정상
    // 무리 안으로 들어오고 눌려 있던 그림자가 살아납니다(GT-X900-0005: 0.740 → 0.763,
    // 그림자 0.013 → 0.164). 더 밝은 답이 나왔다는 것 자체가 지금 값이 베이스가 아니었다는
    // 뜻이므로, 색을 묻지 않고 밝기와 포화만 봅니다.
    if (measured.has_value() && rebate_debug_enabled()) {
        std::fprintf(
            stderr,
            "[base-rebate] measured=(%.5f,%.5f,%.5f)\n",
            (*measured)[0], (*measured)[1], (*measured)[2]);
    }
    return measured;
}

bool accept_rebate_base(
    const BaseMeasurement& rebate,
    const std::array<float, 3>& current) noexcept {
    for (const double channel : rebate) {
        if (!std::isfinite(channel) || channel <= 0.0 || channel >= 1.0) {
            return false;
        }
    }
    // 베이스는 필름에서 가장 밝습니다. 지금 값보다 어두운 답은 고칠 것이 없다는 뜻입니다.
    const negaflow::core::Rgba32F now{current[0], current[1], current[2], 1.0F};
    const negaflow::core::Rgba32F next{
        static_cast<float>(rebate[0]),
        static_cast<float>(rebate[1]),
        static_cast<float>(rebate[2]),
        1.0F};
    // 여유를 둡니다. 띠 찾기를 늘 돌리므로 멀쩡한 사진에서도 같은 자리를 다시 재게 되는데,
    // 그때 나오는 값은 지금 값과 사실상 같습니다(실측 20 장에서 1.00~1.05 배). 여유가 없으면
    // 그 미세한 차이로 멀쩡한 사진이 바뀝니다. 실제로 고쳐야 하는 사진은 1.30 배 이상입니다.
    if (!film_base_detail::finite_rgb(now) || luma_of(next) < luma_of(now) * 1.15) {
        return false;
    }
    // 맨 광원은 센서 최대치에 붙습니다. 필름 베이스는 자기도 밀도가 있어 절대 포화되지
    // 않습니다 — 색이 없는 흑백에서 이것이 유일한 구분점입니다.
    return std::none_of(rebate.begin(), rebate.end(), [](const double channel) {
        return channel >= 0.985;
    });
}

}  // namespace negaflow::imaging::auto_base_detail
