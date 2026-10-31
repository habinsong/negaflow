#include "negaflow/imaging/auto_negative_base_resolver.h"

#include "auto_negative_base_candidates.h"
#include "auto_negative_base_exclusion.h"
#include "auto_negative_base_fallback.h"
#include "auto_negative_base_rebate.h"
#include "film_base_sampling.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

using namespace negaflow::imaging::auto_base_detail;

constexpr std::array<float, 3> color_fallback{0.86F, 0.68F, 0.50F};
constexpr std::array<float, 3> monochrome_fallback{0.80F, 0.80F, 0.80F};

using film_base_detail::BaseMeasurement;
using film_base_detail::SampleGrid;
using film_base_detail::SampleGridGeometry;
using film_base_detail::candidate_indices;
using film_base_detail::candidate_luma_peak;
using film_base_detail::coherent_measurement;
using film_base_detail::connected_component_base;
using film_base_detail::BaseSearchScope;
using film_base_detail::excluding_interior;
using film_base_detail::keeping_interior;
using film_base_detail::ring_mask_chroma;
using film_base_detail::finite_rgb;
using film_base_detail::has_compatible_layout;
using film_base_detail::is_component_candidate;
using film_base_detail::luma_of;
using film_base_detail::make_sample_grid;
using film_base_detail::make_sample_grid_geometry;
using film_base_detail::median;
using film_base_detail::percentile;
using film_base_detail::upper_median;

[[nodiscard]] std::array<float, 3> fallback_for(const NegativeFilmType film_type) noexcept {
    return film_type == NegativeFilmType::black_and_white ? monochrome_fallback : color_fallback;
}

[[nodiscard]] std::array<float, 3> narrow_measurement(const BaseMeasurement& measurement) noexcept {
    return {
        static_cast<float>(measurement[0]),
        static_cast<float>(measurement[1]),
        static_cast<float>(measurement[2]),
    };
}

// 이 지점을 넘으면 **틀렸다고 볼 이유가 있을 때만** 한 화소라도 더 읽습니다. 정상 20 장이
// 0.44~2.32%, 잘못 고른 2 장이 10.6~11.0% 로 갈립니다(실측 22 장).
constexpr double rebate_gate_fraction = 0.05;

/// <param name="grid">
/// 축소본을 **한 번만** 짓기 위한 자리입니다. 뒤이어 도는 문지기가 같은 격자를 보므로,
/// 여기서 지어 두고 넘겨줍니다 — 따로 지으면 18 Mpx 한 장에 39 ms 가 더 붙습니다(실측).
/// </param>
// 확신 있는 측정만 찾습니다(macOS `confidentOnly: true`). 띠 폴백·장면 가장자리 추정은 하지
// 않습니다 — 그것은 프레임 전체 탐색의 몫입니다. 띠는 띠의 비필름 마스크를, 사진은 마스크 없이
// 봅니다(사진은 전부 필름입니다).
[[nodiscard]] std::optional<std::pair<FilmBaseMeasurement, AutoNegativeBaseSource>> confident_base(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const BaseSearchScope scope,
    const bool demotes) {
    if (const std::optional<FilmBaseMeasurement> component =
            connected_component_base(grid, film_type, scope, demotes)) {
        return std::pair{*component, AutoNegativeBaseSource::connected_component};
    }
    const std::optional<std::vector<bool>> exclusion = scope == BaseSearchScope::ring
        ? non_film_exclusion(grid, film_type)
        : std::nullopt;
    const std::vector<bool>* excluded = exclusion.has_value() ? &*exclusion : nullptr;
    const std::optional<FilmBaseMeasurement> edge = continuous_border_base(grid, film_type, excluded);
    const std::optional<FilmBaseMeasurement> distributed = distributed_base(grid, film_type, excluded);
    if (edge.has_value() && distributed.has_value()) {
        const double edge_luma = (edge->rgb[0] + edge->rgb[1] + edge->rgb[2]) / 3.0;
        const double distributed_luma =
            (distributed->rgb[0] + distributed->rgb[1] + distributed->rgb[2]) / 3.0;
        return edge_luma >= distributed_luma * 0.85
            ? std::pair{*edge, AutoNegativeBaseSource::continuous_border}
            : std::pair{*distributed, AutoNegativeBaseSource::distributed_mask};
    }
    if (edge.has_value()) {
        return std::pair{*edge, AutoNegativeBaseSource::continuous_border};
    }
    if (distributed.has_value()) {
        return std::pair{*distributed, AutoNegativeBaseSource::distributed_mask};
    }
    return std::nullopt;
}

[[nodiscard]] AutoNegativeBaseResult measured_result(
    const std::pair<FilmBaseMeasurement, AutoNegativeBaseSource>& found) noexcept {
    AutoNegativeBaseResult result{};
    result.status = AutoNegativeBaseStatus::ok;
    result.dmin = narrow_measurement(found.first.rgb);
    result.source = found.second;
    result.diagnostics = found.first.diagnostics;
    return result;
}

[[nodiscard]] double luma_of_dmin(const std::array<float, 3>& dmin) noexcept {
    return (static_cast<double>(dmin[0]) + static_cast<double>(dmin[1]) + static_cast<double>(dmin[2])) / 3.0;
}

[[nodiscard]] bool looks_like_light(
    const std::array<float, 3>& candidate, const std::array<float, 3>& film);

// 고른 값이 물리적으로 말이 되는지 보고, 안 되면 리베이트 띠에서 원본 해상도로 다시 잽니다.
// 받아들이지 않으면 기존 값이 그대로 남습니다(macOS `rescuedWithRebate`).
[[nodiscard]] AutoNegativeBaseResult rescued_with_rebate(
    const WorkingImage& image,
    const SampleGrid& searched,
    const NegativeFilmType film_type,
    AutoNegativeBaseResult result,
    const bool ring_scope) noexcept {
    try {
        result.brighter_than_base =
            auto_base_detail::brighter_than_base_fraction(searched, result.dmin);
        // 띠 찾기는 축소본 위에서만 도는 선형 두 번이라 늘 돌려도 쌉니다. 원본을 다시 읽을지는
        // 그 안에서 정합니다 — 문지기가 열렸거나, 띠가 뭉개질 만큼 얇을 때만입니다.
        const std::optional<BaseMeasurement> rebate = auto_base_detail::rebate_base(
            image, searched, film_type, result.brighter_than_base > rebate_gate_fraction);
        if (!rebate.has_value() ||
            !auto_base_detail::accept_rebate_base(*rebate, result.dmin)) {
            return result;
        }
        // Mixed backlight boundaries can survive geometric masking. Compare the
        // two mask-chroma axes against the measured film in every search scope.
        if (film_type == NegativeFilmType::color &&
            looks_like_light(narrow_measurement(*rebate), result.dmin)) {
            return result;
        }
        // 띠에서는 베이스를 색도 증거로 골랐습니다. 리베이트 띠는 베이스 그 자체라 색도가
        // 같아야 합니다 — 마스크 색도만큼 덜 오렌지인 "더 밝은 띠" 는 광원입니다(바꾸지 않습니다).
        if (ring_scope && film_type == NegativeFilmType::color) {
            const auto log_red_blue = [](const double red, const double blue) {
                return std::log10(std::max(red, 1.0e-5) / std::max(blue, 1.0e-5));
            };
            if (log_red_blue((*rebate)[0], (*rebate)[2]) <
                log_red_blue(result.dmin[0], result.dmin[2]) - ring_mask_chroma().red_blue) {
                return result;
            }
        }
        result.dmin = narrow_measurement(*rebate);
        result.rebate_rescued = true;
    } catch (...) {
        // 구조길이 실패해도 기존 값은 그대로입니다. 고치려다 더 나쁘게 만들지 않습니다.
    }
    return result;
}

// 베이스 판정의 모순 문턱 — `contradicting_fraction` 의 실측(정상 0~0.8%, 모순 7.1%~).
constexpr double contradiction_fraction = 0.02;

// 고른 값보다 뚜렷이 밝은 필름이 있으면(모순) 필름에서 가장 밝은 5%(분산 샘플러)로 올립니다.
// 베이스가 화면에 없는 컷에서 성분 검출은 결이 있는 얇은 면 — 이웃 15% 문턱에 걸려 조각납니다 —
// 을 놓치고 더 어두운 매끈한 면을 고릅니다(2026-10-15 macOS 실측: 같은 롤 베이스 0.23/0.096/0.068,
// 고른 값 0.104/0.051/0.032, 그보다 밝은 필름 11% 가 반전에서 검정으로 잘렸습니다).
[[nodiscard]] AutoNegativeBaseResult lifted_to_film_envelope(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    AutoNegativeBaseResult result,
    const AnalysisRegion* interior_of,
    const std::vector<bool>* excluded) {
    if (auto_base_detail::contradicting_fraction(grid, result.dmin, film_type, interior_of, excluded) <=
        contradiction_fraction) {
        return result;
    }
    const std::optional<FilmBaseMeasurement> envelope = distributed_base(grid, film_type, excluded);
    if (!envelope.has_value() ||
        luma_of_dmin(narrow_measurement(envelope->rgb)) <= luma_of_dmin(result.dmin)) {
        return result;
    }
    if (film_type == NegativeFilmType::color &&
        looks_like_light(narrow_measurement(envelope->rgb), result.dmin)) {
        return result;
    }
    result.dmin = narrow_measurement(envelope->rgb);
    result.source = AutoNegativeBaseSource::distributed_mask;
    result.diagnostics = envelope->diagnostics;
    return result;
}

// `candidate` 가 `film` 을 비춘 광원처럼 보이는가. 필름 = 광원 × 마스크 × 장면 염료라, 광원이면
// 필름이 마스크 색도(띠 강등과 같은 문턱)만큼 두 축 모두 더 오렌지입니다(macOS `looksLikeLight`).
[[nodiscard]] bool looks_like_light(const std::array<float, 3>& candidate, const std::array<float, 3>& film) {
    const auto log_ratio = [](const float a, const float b) {
        return std::log10(std::max(static_cast<double>(a), 1.0e-5) / std::max(static_cast<double>(b), 1.0e-5));
    };
    const film_base_detail::RingMaskChroma mask = ring_mask_chroma();
    return log_ratio(film[0], film[1]) - log_ratio(candidate[0], candidate[1]) >= mask.red_green &&
        log_ratio(film[1], film[2]) - log_ratio(candidate[1], candidate[2]) >= mask.green_blue;
}

// ── 유제 색과 무관한 마지막 확인 ─────────────────────────────────────────────────
//
// 위의 탐색은 "베이스는 스캔에서 오렌지(R ≥ G ≥ B)" 라는 가정에 기댑니다
// (`is_component_candidate`). 그 가정은 필름에 따라 깨집니다. 2026-10-31 GT-X900 으로 스캔한
// Kodak Vision3 250D 롤(4~11번)은 프레임 사이 틈의 베이스가 0.30/0.34/0.33 처럼 초록·파랑이
// 빨강보다 밝아 후보에서 통째로 빠졌고, 사진 속 짙은 오렌지 면(10번: 0.13/0.08/0.08)이 베이스로
// 골라져 반전이 어둡고 붉게 잘렸습니다. 같은 스캐너로 찍은 다른 필름은 0.34/0.28/0.22 로
// 오렌지였습니다 — 베이스 색은 필름마다 다릅니다.
//
// 그래서 여기서는 색을 묻지 않고 물리를 봅니다. 필름 = 광원 × 베이스 × 장면 염료이고 염료는 빛을
// **덜어내기만** 하므로, 베이스는 필름에서 **모든 채널이 함께** 가장 밝습니다. 고른 값보다 모든
// 채널이 뚜렷이 밝은 필름이 넓게 있으면 그 값은 베이스가 아닙니다. 그때 모든 채널이 가장 밝은
// 매끈한 면으로 올립니다. 오렌지든 보라든 회색이든 같습니다.
//
// 그보다 밝은 것은 필름이 아닌 맨 광원뿐입니다. 포화 근처는 필름이 아니고(베이스도 밀도가 있어
// 포화되지 않습니다 — `accept_rebate_base` 와 같은 문턱), 포화되지 않은 광원은 기존과 같은 상대
// 색도(`looks_like_light`)로 거릅니다. 크롭이 있으면 사진 안만 증거로 삼으므로 광원은 증거에
// 끼지 않습니다. 남는 한계는 하나입니다 — 마스크가 회색이라 베이스와 광원의 색이 같고, 광원이
// 포화되지 않은 채 크롭 없이 넓게 찍혀 있으면 색으로도 밝기로도 가를 수 없습니다. 흑백 필름의
// 탐색과 같은 한계입니다.
constexpr double envelope_channel_factor = 1.15;
constexpr double envelope_saturation = 0.985;

[[nodiscard]] bool plausible_film_cell(const negaflow::core::Rgba32F& pixel) noexcept {
    if (!finite_rgb(pixel)) {
        return false;
    }
    const double luma = luma_of(pixel);
    const double peak = std::max(
        static_cast<double>(pixel.red),
        std::max(static_cast<double>(pixel.green), static_cast<double>(pixel.blue)));
    return luma >= 0.012 && luma <= 0.85 && peak < envelope_saturation;
}

[[nodiscard]] bool brighter_in_every_channel(
    const negaflow::core::Rgba32F& pixel,
    const std::array<float, 3>& base,
    const double factor) noexcept {
    return static_cast<double>(pixel.red) >= static_cast<double>(base[0]) * factor &&
        static_cast<double>(pixel.green) >= static_cast<double>(base[1]) * factor &&
        static_cast<double>(pixel.blue) >= static_cast<double>(base[2]) * factor;
}

// 고른 베이스보다 모든 채널이 1.15 배 이상 밝은 필름 칸의 비율입니다. 크롭이 있으면 사진 안만
// 셉니다(띠의 광원·홀더가 증거에 끼지 않게).
[[nodiscard]] double film_brighter_than(
    const SampleGrid& grid,
    const std::array<float, 3>& base,
    const std::optional<AnalysisRegion>& region) noexcept {
    std::size_t counted = 0U;
    std::size_t brighter = 0U;
    for (std::uint32_t y = 0U; y < grid.height; ++y) {
        for (std::uint32_t x = 0U; x < grid.width; ++x) {
            if (region.has_value() && !film_base_detail::is_interior(grid, *region, x, y)) {
                continue;
            }
            const negaflow::core::Rgba32F& pixel =
                grid.pixels[static_cast<std::size_t>(y) * grid.width + x];
            if (!finite_rgb(pixel)) {
                continue;
            }
            ++counted;
            if (plausible_film_cell(pixel) &&
                brighter_in_every_channel(pixel, base, envelope_channel_factor)) {
                ++brighter;
            }
        }
    }
    return counted > 0U ? static_cast<double>(brighter) / static_cast<double>(counted) : 0.0;
}

struct EnvelopeComponent final {
    std::vector<std::size_t> cells;
    double p75{0.0};
};

// 색을 묻지 않는 매끈한 밝은 면들입니다. 연결 성분 탐색(`connected_component_base`)과 같은 틀 —
// 이웃 2 칸 안에 1.15 배 넘게 밝은 칸이 없는 칸만 잇고, 격자의 0.4%(최소 24 칸)보다 작은 조각은
// 버립니다(퍼포레이션 구멍·먼지 같은 작은 광원이 여기서 빠집니다). 홀더 그늘은 밝은 필름의
// 10% 아래로 잘라 냅니다.
[[nodiscard]] std::vector<EnvelopeComponent> envelope_components(const SampleGrid& grid) {
    const std::uint32_t width = grid.width;
    const std::uint32_t height = grid.height;
    const std::size_t count = grid.pixels.size();
    std::vector<double> film_lumas;
    film_lumas.reserve(count);
    for (std::size_t index = 0U; index < count; ++index) {
        if (plausible_film_cell(grid.pixels[index])) {
            film_lumas.push_back(grid.lumas[index]);
        }
    }
    if (film_lumas.empty()) {
        return {};
    }
    const double floor = percentile(film_lumas, 0.99) * 0.10;
    std::vector<bool> smooth(count, false);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            if (!plausible_film_cell(grid.pixels[index]) || grid.lumas[index] < floor) {
                continue;
            }
            const double ceiling = grid.lumas[index] * 1.15;
            bool boundary = false;
            for (std::uint32_t ny = y > 2U ? y - 2U : 0U; ny <= std::min(height - 1U, y + 2U) && !boundary; ++ny) {
                for (std::uint32_t nx = x > 2U ? x - 2U : 0U; nx <= std::min(width - 1U, x + 2U); ++nx) {
                    if (grid.lumas[static_cast<std::size_t>(ny) * width + nx] > ceiling) {
                        boundary = true;
                        break;
                    }
                }
            }
            smooth[index] = !boundary;
        }
    }
    const std::size_t minimum_size = std::max<std::size_t>(24U, count * 4U / 1000U);
    std::vector<std::int32_t> labels(count, -1);
    std::vector<EnvelopeComponent> components;
    std::vector<std::size_t> queue;
    for (std::size_t start = 0U; start < count; ++start) {
        if (!smooth[start] || labels[start] >= 0) {
            continue;
        }
        const std::int32_t label = static_cast<std::int32_t>(components.size()) + 1;
        std::vector<std::size_t> cells;
        queue.clear();
        queue.push_back(start);
        labels[start] = label;
        while (!queue.empty()) {
            const std::size_t cell = queue.back();
            queue.pop_back();
            cells.push_back(cell);
            const std::uint32_t x = static_cast<std::uint32_t>(cell % width);
            const std::uint32_t y = static_cast<std::uint32_t>(cell / width);
            const std::array<std::pair<std::uint32_t, std::uint32_t>, 4> neighbors{{
                {x > 0U ? x - 1U : x, y}, {std::min(width - 1U, x + 1U), y},
                {x, y > 0U ? y - 1U : y}, {x, std::min(height - 1U, y + 1U)}}};
            for (const auto [nx, ny] : neighbors) {
                const std::size_t next = static_cast<std::size_t>(ny) * width + nx;
                if (next != cell && smooth[next] && labels[next] < 0) {
                    labels[next] = label;
                    queue.push_back(next);
                }
            }
        }
        if (cells.size() < minimum_size) {
            continue;
        }
        std::vector<double> values;
        values.reserve(cells.size());
        for (const std::size_t cell : cells) {
            values.push_back(grid.lumas[cell]);
        }
        const double p75 = percentile(values, 0.75);
        components.push_back({std::move(cells), p75});
    }
    std::sort(components.begin(), components.end(), [](const EnvelopeComponent& left, const EnvelopeComponent& right) {
        return left.p75 > right.p75;
    });
    return components;
}

[[nodiscard]] AutoNegativeBaseResult lifted_to_physical_envelope(
    const SampleGrid& grid,
    const std::optional<AnalysisRegion>& region,
    AutoNegativeBaseResult result) {
    if (film_brighter_than(grid, result.dmin, region) <= contradiction_fraction) {
        return result;
    }
    const std::vector<EnvelopeComponent> components = envelope_components(grid);
    // 성분마다 밝은 절반(최소 24 칸)을 잽니다 — 연결 성분 탐색이 베이스를 재는 방식과 같습니다.
    std::vector<std::optional<FilmBaseMeasurement>> measurements;
    measurements.reserve(components.size());
    for (const EnvelopeComponent& component : components) {
        std::vector<std::size_t> members = component.cells;
        std::sort(members.begin(), members.end(), [&grid](const std::size_t left, const std::size_t right) {
            return grid.lumas[left] > grid.lumas[right];
        });
        members.resize(std::max(members.size() / 2U, std::min(members.size(), std::size_t{24U})));
        measurements.push_back(build_film_base_measurement(
            FilmBaseMeasurementMethod::connected_component,
            static_cast<int>(grid.pixels.size()),
            static_cast<int>(component.cells.size()),
            film_base_detail::samples_from_indices(grid, members),
            static_cast<int>(grid.width),
            static_cast<int>(grid.height)));
    }
    const double current_luma = luma_of_dmin(result.dmin);
    for (std::size_t index = 0U; index < components.size(); ++index) {
        if (!measurements[index].has_value()) {
            continue;
        }
        const FilmBaseMeasurement& measured = *measurements[index];
        const std::array<float, 3> candidate = narrow_measurement(measured.rgb);
        // 밝은 순서이므로 지금 값보다 뚜렷이 밝지 않은 성분이 나오면 더 볼 것이 없습니다.
        if (luma_of_dmin(candidate) < current_luma * envelope_channel_factor) {
            break;
        }
        // 오렌지로 보이는 면은 위의 탐색이 이미 보고 판정했습니다(그리고 광원이면 강등했습니다).
        // 여기서는 그 탐색이 **보지 못한** 면 — 오렌지가 아닌 밝은 필름만 구제합니다. 그래야 따뜻한
        // 백라이트를 다시 베이스로 끌어올리지 않습니다.
        const negaflow::core::Rgba32F candidate_pixel{candidate[0], candidate[1], candidate[2], 1.0F};
        if (is_component_candidate(candidate_pixel, NegativeFilmType::color)) {
            continue;
        }
        const bool saturated = std::any_of(candidate.begin(), candidate.end(), [](const float channel) {
            return static_cast<double>(channel) >= envelope_saturation;
        });
        // 베이스는 지금 값보다 어느 채널도 어둡지 않습니다.
        const bool not_darker = candidate[0] >= result.dmin[0] && candidate[1] >= result.dmin[1] &&
            candidate[2] >= result.dmin[2];
        if (saturated || !not_darker || looks_like_light(candidate, result.dmin) ||
            film_brighter_than(grid, candidate, region) > contradiction_fraction) {
            continue;
        }
        // 광원은 그것이 비춘 필름보다 마스크 색도만큼 덜 오렌지입니다(베이스 = 광원 × 마스크).
        // 색 공간과 무관한 **상대** 관계라, 카메라 RGB 처럼 초록이 큰 공간에서도 성립합니다. 띠
        // 강등과 같은 밝기 창(0.12~0.87 배) 안에 그런 더 어두운 면이 있으면 이 면은 광원입니다.
        bool lit_film_below = false;
        for (std::size_t darker = index + 1U; darker < components.size() && !lit_film_below; ++darker) {
            const double ratio = components[darker].p75 / std::max(components[index].p75, 1.0e-9);
            if (ratio > 0.87 || ratio < 0.12 || !measurements[darker].has_value()) {
                continue;
            }
            lit_film_below = looks_like_light(candidate, narrow_measurement(measurements[darker]->rgb));
        }
        if (lit_film_below) {
            continue;
        }
        std::size_t debug_length = 0U;
        if (getenv_s(&debug_length, nullptr, 0U, "NEGA_DEBUG") == 0 && debug_length > 0U) {
            std::fprintf(stderr, "[base-envelope] (%.5f,%.5f,%.5f) -> (%.5f,%.5f,%.5f) cells=%zu\n",
                static_cast<double>(result.dmin[0]), static_cast<double>(result.dmin[1]),
                static_cast<double>(result.dmin[2]), static_cast<double>(candidate[0]),
                static_cast<double>(candidate[1]), static_cast<double>(candidate[2]),
                components[index].cells.size());
        }
        result.dmin = candidate;
        result.source = AutoNegativeBaseSource::connected_component;
        result.diagnostics = measured.diagnostics;
        return result;
    }
    return result;
}

// 크롭이 있을 때의 베이스(macOS `estimateAroundCrop`). 디카 스캔은 원본에 퍼포레이션·백라이트·
// 홀더가 함께 찍혀 프레임 전체를 뒤지면 광원을 베이스로 잡기 쉽습니다 — 그래서 크롭이 있으면 프레임
// 전체로 가지 않습니다.
//  1. 크롭 바깥 띠(리베이트)에서 찾고, 그 값이 크롭 안 사진과 모순이 없으면 씁니다.
//  2. 모순이면 띠의 광원 강등이 틀렸을 수 있습니다 — 강등 없이 띠에서 가장 밝은 성분을 보고, 사진과
//     모순이 없고 광원처럼 보이지도 않으면 씁니다.
//  3. 띠에 베이스가 없으면(크롭이 리베이트를 잘라 냄) 크롭 안 사진에서 가장 얇은 필름 면을 씁니다.
// 셋 다 없을 때만 nullopt — 그때는 예전처럼 프레임 전체에서 찾습니다.
[[nodiscard]] std::optional<AutoNegativeBaseResult> resolve_around_crop(
    const WorkingImage& image,
    const NegativeFilmType film_type,
    const SampleGrid& grid,
    const AnalysisRegion& region) {
    const SampleGrid ring = excluding_interior(grid, region);
    const auto ring_answer = [&](const bool demotes) -> std::optional<AutoNegativeBaseResult> {
        const auto found = confident_base(ring, film_type, BaseSearchScope::ring, demotes);
        if (!found.has_value()) {
            return std::nullopt;
        }
        return rescued_with_rebate(image, ring, film_type, measured_result(*found), true);
    };
    const auto contradicted = [&](const AutoNegativeBaseResult& candidate) {
        return auto_base_detail::contradicting_fraction(grid, candidate.dmin, film_type, &region, nullptr) >
            contradiction_fraction;
    };
    // 사진 안 탐색은 띠가 실패했을 때만 돕니다(대부분의 프레임은 띠에서 끝납니다).
    std::optional<std::optional<AutoNegativeBaseResult>> cached_photo;
    const auto photo = [&]() -> std::optional<AutoNegativeBaseResult> {
        if (!cached_photo.has_value()) {
            const SampleGrid photo_grid = keeping_interior(grid, region);
            const auto found = confident_base(photo_grid, film_type, BaseSearchScope::photo, true);
            cached_photo = found.has_value()
                ? std::optional{lifted_to_film_envelope(photo_grid, film_type, measured_result(*found), &region, nullptr)}
                : std::nullopt;
        }
        return *cached_photo;
    };
    const std::optional<AutoNegativeBaseResult> demoted = ring_answer(true);
    if (!demoted.has_value()) {
        return photo();
    }
    if (!contradicted(*demoted)) {
        return demoted;
    }
    // 2026-10-15 macOS 실측: 오른쪽 띠의 리베이트(0.34/0.158/0.092)를 광원으로 강등하고 짙은 장면
    // (0.11/0.032/0.012)을 골랐습니다 — 사진의 97% 가 그보다 밝았습니다.
    if (film_type == NegativeFilmType::color) {
        if (const std::optional<AutoNegativeBaseResult> top = ring_answer(false);
            top.has_value() && top->dmin != demoted->dmin && !contradicted(*top)) {
            const std::optional<AutoNegativeBaseResult> film = photo();
            if (!film.has_value() || !looks_like_light(top->dmin, film->dmin)) {
                return top;
            }
        }
    }
    return photo();
}

/// <param name="from_crop">
/// 크롭 영역에서 답이 나왔으면 참입니다 — 그 답은 리베이트 확인·모순 판정을 이미 거쳤습니다.
/// </param>
[[nodiscard]] AutoNegativeBaseResult resolve_without_rebate(
    const WorkingImage& image,
    const NegativeFilmType film_type,
    std::optional<SampleGrid>& grid,
    const std::optional<AnalysisRegion>& region,
    bool& from_crop) noexcept {
    from_crop = false;
    AutoNegativeBaseResult result{};
    if (!has_compatible_layout(image)) {
        return result;
    }

    result.status = AutoNegativeBaseStatus::ok;
    result.dmin = fallback_for(film_type);
    const auto with_chromogenic_fallback = [&image, film_type, &region](
                                               const AutoNegativeBaseResult resolved) {
        if (film_type != NegativeFilmType::black_and_white ||
            resolved.status != AutoNegativeBaseStatus::ok) {
            return resolved;
        }
        const double maximum = std::max(
            static_cast<double>(resolved.dmin[0]),
            std::max(
                static_cast<double>(resolved.dmin[1]),
                static_cast<double>(resolved.dmin[2])));
        const double minimum = std::min(
            static_cast<double>(resolved.dmin[0]),
            std::min(
                static_cast<double>(resolved.dmin[1]),
                static_cast<double>(resolved.dmin[2])));
        // macOS's estimator returns nil when neutral-base measurement fails.  Its
        // fallback constant is applied only after the chromogenic retry, so the
        // Windows fallback must not be mistaken for a measured neutral base here.
        if (resolved.source != AutoNegativeBaseSource::fallback &&
            (minimum <= 1.0e-6 || maximum / minimum <= 1.25)) {
            return resolved;
        }
        const AutoNegativeBaseResult chromogenic =
            resolve_auto_negative_base(image, NegativeFilmType::color, region);
        return chromogenic.status == AutoNegativeBaseStatus::ok &&
                chromogenic.source != AutoNegativeBaseSource::fallback
            ? chromogenic
            : resolved;
    };
    if (image.width <= 4U || image.height <= 4U) {
        return result;
    }

    try {
        if (!grid.has_value()) {
            grid = make_sample_grid(image);
        }
        if (!grid.has_value()) {
            return result;
        }
        const auto apply = [&result](const FilmBaseMeasurement& measurement,
                                     const AutoNegativeBaseSource source) {
            result.dmin = narrow_measurement(measurement.rgb);
            result.source = source;
            result.diagnostics = measurement.diagnostics;
        };
        if (region.has_value()) {
            if (const std::optional<AutoNegativeBaseResult> cropped =
                    resolve_around_crop(image, film_type, *grid, *region)) {
                from_crop = true;
                return with_chromogenic_fallback(*cropped);
            }
        }
        // 실험 knob: NEGA_BASE_SKIP_CC=1 이면 연결 성분을 건너뛰고 폴백 경로를 봅니다.
        // macOS 표본 그리드에서 성분이 최소 크기를 못 넘겨 폴백으로 갔는지 재기 위한 자리입니다.
        std::size_t skip_length = 0U;
        const bool skip_component =
            getenv_s(&skip_length, nullptr, 0U, "NEGA_BASE_SKIP_CC") == 0 && skip_length > 0U;
        if (const std::optional<FilmBaseMeasurement> component =
                skip_component ? std::nullopt : connected_component_base(*grid, film_type)) {
            apply(*component, AutoNegativeBaseSource::connected_component);
            return with_chromogenic_fallback(result);
        }
        const std::optional<std::vector<bool>> exclusion = non_film_exclusion(*grid, film_type);
        const std::vector<bool>* excluded = exclusion.has_value() ? &*exclusion : nullptr;
        const std::optional<FilmBaseMeasurement> edge =
            continuous_border_base(*grid, film_type, excluded);
        const std::optional<FilmBaseMeasurement> distributed =
            distributed_base(*grid, film_type, excluded);
        if (edge.has_value() && distributed.has_value()) {
            const double edge_luma =
                (edge->rgb[0] + edge->rgb[1] + edge->rgb[2]) / 3.0;
            const double distributed_luma =
                (distributed->rgb[0] + distributed->rgb[1] + distributed->rgb[2]) / 3.0;
            const bool use_edge = edge_luma >= distributed_luma * 0.85;
            apply(
                use_edge ? *edge : *distributed,
                use_edge
                    ? AutoNegativeBaseSource::continuous_border
                    : AutoNegativeBaseSource::distributed_mask);
            return with_chromogenic_fallback(result);
        }
        if (edge.has_value()) {
            apply(*edge, AutoNegativeBaseSource::continuous_border);
            return with_chromogenic_fallback(result);
        }
        if (distributed.has_value()) {
            apply(*distributed, AutoNegativeBaseSource::distributed_mask);
            return with_chromogenic_fallback(result);
        }
        if (const std::optional<FilmBaseMeasurement> strip =
                strip_fallback_base(*grid, film_type, excluded)) {
            apply(*strip, AutoNegativeBaseSource::strip_fallback);
            return with_chromogenic_fallback(result);
        }
        if (const std::optional<BaseMeasurement> scene_edge =
                scene_edge_fallback_base(image, film_type)) {
            result.dmin = narrow_measurement(*scene_edge);
            result.source = AutoNegativeBaseSource::scene_edge;
        }
    } catch (...) {
        // The documented fallback is preferable to allowing an allocation failure to cross a
        // noexcept ABI boundary. It remains distinguishable from a manual base in request mode.
    }
    return with_chromogenic_fallback(result);
}

}  // namespace

AutoNegativeBaseResult resolve_auto_negative_base(
    const WorkingImage& image,
    const NegativeFilmType film_type,
    const std::optional<AnalysisRegion>& region) noexcept {
    // 축소본은 기존 경로가 이미 지었습니다. 문지기가 그것을 그대로 봅니다.
    std::optional<SampleGrid> grid;
    bool from_crop = false;
    AutoNegativeBaseResult result = resolve_without_rebate(image, film_type, grid, region, from_crop);
    if (result.status != AutoNegativeBaseStatus::ok || !grid.has_value()) {
        return result;
    }
    try {
        if (!from_crop && result.source != AutoNegativeBaseSource::fallback) {
            result = rescued_with_rebate(image, *grid, film_type, result, false);
            const std::optional<std::vector<bool>> exclusion = non_film_exclusion(*grid, film_type);
            result = lifted_to_film_envelope(
                *grid, film_type, result, nullptr, exclusion.has_value() ? &*exclusion : nullptr);
        }
        // 컬러 네거티브만입니다. 흑백 탐색은 처음부터 색을 묻지 않습니다(`is_component_candidate`).
        if (film_type == NegativeFilmType::color) {
            result = lifted_to_physical_envelope(*grid, region, result);
        }
    } catch (...) {
        // 구조길이 실패해도 기존 값은 그대로입니다. 고치려다 더 나쁘게 만들지 않습니다.
    }
    return result;
}

const char* auto_negative_base_status_name(const AutoNegativeBaseStatus status) noexcept {
    switch (status) {
        case AutoNegativeBaseStatus::ok:
            return "ok";
        case AutoNegativeBaseStatus::invalid_image:
            return "invalid_image";
    }
    return "unknown_auto_negative_base_status";
}


}  // namespace negaflow::imaging
