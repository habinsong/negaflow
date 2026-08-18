#include "negaflow/imaging/film_base_picker.h"

#include "film_base_sampling.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

namespace negaflow::imaging {
namespace {

using film_base_detail::BaseMeasurement;
using film_base_detail::SampleGrid;

// macOS `FilmBasePicker.snapWindowFraction`. 로컬 스냅 창 한 변 = 짧은 변 × 이 값입니다.
constexpr double snap_window_fraction = 0.12;

// macOS `FilmBasePicker.minimumBaseLumaRatio`. 스캔 전체의 베이스 수준 대비 하한입니다.
constexpr double minimum_base_luma_ratio = 0.5;

// macOS `snapToBase` 의 두 관문: 창 한 변 48 이상, 잘린 창 32×32 이상.
constexpr double minimum_snap_side = 48.0;
constexpr std::uint32_t minimum_snap_window = 32U;

[[nodiscard]] double clamp_unit(const double value) noexcept {
    return std::min(std::max(value, 0.0), 1.0);
}

// macOS 는 `CGRect.integral` 로 정수 경계에 스냅한 뒤 `intersection(extent.integral)` 을
// 씁니다. 여기서도 같은 뜻으로 floor/ceil 한 뒤 이미지 안으로 자릅니다.
struct PixelRect final {
    std::uint32_t left{};
    std::uint32_t top{};
    std::uint32_t width{};
    std::uint32_t height{};
};

[[nodiscard]] std::optional<PixelRect> integral_intersection(
    const double center_x,
    const double center_y,
    const double side,
    const std::uint32_t image_width,
    const std::uint32_t image_height) noexcept {
    const double half = side / 2.0;
    const double left = std::max(0.0, std::floor(center_x - half));
    const double top = std::max(0.0, std::floor(center_y - half));
    const double right = std::min(static_cast<double>(image_width), std::ceil(center_x + half));
    const double bottom = std::min(static_cast<double>(image_height), std::ceil(center_y + half));
    if (right <= left || bottom <= top) {
        return std::nullopt;
    }
    return PixelRect{
        static_cast<std::uint32_t>(left),
        static_cast<std::uint32_t>(top),
        static_cast<std::uint32_t>(right - left),
        static_cast<std::uint32_t>(bottom - top),
    };
}

// macOS `image.cropped(to:).transformed(by: translation)` 에 해당합니다 —
// `FilmBaseSampleGrid` 가 원점 (0,0) 을 가정하므로 창을 원점으로 옮겨 새 이미지로 만듭니다.
[[nodiscard]] WorkingImage crop(const WorkingImage& image, const PixelRect& rect) {
    WorkingImage cropped{};
    cropped.width = rect.width;
    cropped.height = rect.height;
    cropped.stride_pixels = rect.width;
    cropped.pixels.resize(static_cast<std::size_t>(rect.width) * rect.height);
    for (std::uint32_t y = 0U; y < rect.height; ++y) {
        const std::size_t source_row =
            ((static_cast<std::size_t>(rect.top) + y) * image.stride_pixels) + rect.left;
        const std::size_t target_row = static_cast<std::size_t>(y) * rect.width;
        for (std::uint32_t x = 0U; x < rect.width; ++x) {
            cropped.pixels[target_row + x] = image.pixels[source_row + x];
        }
    }
    return cropped;
}

// macOS `FilmBasePicker.baseReference` — 자동 추정이 쓰는 후보 luma p99 와 같은 값입니다.
// 그리드를 만들 수 없는 극소 이미지에서는 없음이며, 그때는 절대 판정만 적용합니다.
[[nodiscard]] std::optional<double> base_reference(
    const WorkingImage& image,
    const NegativeFilmType film_type) {
    const std::optional<SampleGrid> grid = film_base_detail::make_sample_grid(image);
    if (!grid.has_value()) {
        return std::nullopt;
    }
    const double peak = film_base_detail::candidate_luma_peak(*grid, film_type);
    return peak > 0.0 ? std::optional<double>{peak} : std::nullopt;
}

// macOS `FilmBasePicker.isPlausibleBase`.
[[nodiscard]] bool is_plausible_base(
    const BaseMeasurement& rgb,
    const std::optional<double>& reference,
    const NegativeFilmType film_type) noexcept {
    const negaflow::core::Rgba32F pixel{
        static_cast<float>(rgb[0]),
        static_cast<float>(rgb[1]),
        static_cast<float>(rgb[2]),
        1.0F,
    };
    if (!film_base_detail::is_component_candidate(pixel, film_type)) {
        return false;
    }
    if (!reference.has_value()) {
        return true;
    }
    const double luma = (rgb[0] + rgb[1] + rgb[2]) / 3.0;
    return luma >= *reference * minimum_base_luma_ratio;
}

[[nodiscard]] BaseMeasurement clamp_rgb(const BaseMeasurement& rgb) noexcept {
    return BaseMeasurement{clamp_unit(rgb[0]), clamp_unit(rgb[1]), clamp_unit(rgb[2])};
}

// macOS `FilmBasePicker.snapToBase` — 클릭 주변 로컬 창에서 베이스 연결 성분을 찾습니다.
// 창 안에 백라이트나 퍼포레이션이 있어도 성분 검출이 물리 불변량으로 걸러냅니다.
[[nodiscard]] std::optional<BaseMeasurement> snap_to_base(
    const WorkingImage& image,
    const double center_x,
    const double center_y,
    const NegativeFilmType film_type) {
    const double side =
        static_cast<double>(std::min(image.width, image.height)) * snap_window_fraction;
    if (side < minimum_snap_side) {
        return std::nullopt;
    }
    const std::optional<PixelRect> window =
        integral_intersection(center_x, center_y, side, image.width, image.height);
    if (!window.has_value() || window->width < minimum_snap_window ||
        window->height < minimum_snap_window) {
        return std::nullopt;
    }
    const WorkingImage window_image = crop(image, *window);
    const std::optional<SampleGrid> grid = film_base_detail::make_sample_grid(window_image);
    if (!grid.has_value()) {
        return std::nullopt;
    }
    const std::optional<BaseMeasurement> measurement =
        film_base_detail::connected_component_base(*grid, film_type);
    if (!measurement.has_value() || !std::isfinite((*measurement)[0]) ||
        !std::isfinite((*measurement)[1]) || !std::isfinite((*measurement)[2])) {
        return std::nullopt;
    }
    return clamp_rgb(*measurement);
}

// macOS `FilmBasePicker.medianRGB` — 영역의 채널별 <b>중앙값</b>입니다. 평균이 아닌 이유는
// 베이스 위 엣지 마킹 글자·바코드·먼지·퍼포레이션이 영역에 걸치면 평균이 어두운(또는 밝은)
// 쪽으로 끌려가 잘못된 Dmin 이 되기 때문입니다.
[[nodiscard]] std::optional<BaseMeasurement> median_rgb(
    const WorkingImage& image,
    const PixelRect& region) {
    std::vector<double> red;
    std::vector<double> green;
    std::vector<double> blue;
    const std::size_t capacity = static_cast<std::size_t>(region.width) * region.height;
    red.reserve(capacity);
    green.reserve(capacity);
    blue.reserve(capacity);
    for (std::uint32_t y = 0U; y < region.height; ++y) {
        const std::size_t row =
            ((static_cast<std::size_t>(region.top) + y) * image.stride_pixels) + region.left;
        for (std::uint32_t x = 0U; x < region.width; ++x) {
            const negaflow::core::Rgba32F pixel = image.pixels[row + x];
            if (!film_base_detail::finite_rgb(pixel)) {
                continue;
            }
            red.push_back(static_cast<double>(pixel.red));
            green.push_back(static_cast<double>(pixel.green));
            blue.push_back(static_cast<double>(pixel.blue));
        }
    }
    if (red.empty()) {
        return std::nullopt;
    }
    // macOS 는 `red[red.count / 2]` 로 위쪽 중앙값을 씁니다.
    return BaseMeasurement{
        film_base_detail::upper_median(std::move(red)),
        film_base_detail::upper_median(std::move(green)),
        film_base_detail::upper_median(std::move(blue)),
    };
}

}  // namespace

FilmBasePickResult sample_film_base(
    const WorkingImage& image,
    const double unit_x,
    const double unit_y,
    const NegativeFilmType film_type,
    const double region_fraction) noexcept {
    FilmBasePickResult result{};
    if (!film_base_detail::has_compatible_layout(image) || image.width <= 2U ||
        image.height <= 2U || !std::isfinite(unit_x) || !std::isfinite(unit_y) ||
        !std::isfinite(region_fraction) || region_fraction <= 0.0) {
        return result;
    }

    try {
        // macOS 는 CIImage 가 y-up 이라 `1.0 - v` 로 뒤집습니다. WorkingImage 는 y-down
        // 이므로 표시 정규 좌표를 그대로 씁니다.
        const double center_x = clamp_unit(unit_x) * static_cast<double>(image.width);
        const double center_y = clamp_unit(unit_y) * static_cast<double>(image.height);
        const std::optional<double> reference = base_reference(image, film_type);

        const std::optional<BaseMeasurement> snapped =
            snap_to_base(image, center_x, center_y, film_type);
        if (snapped.has_value() && is_plausible_base(*snapped, reference, film_type)) {
            result.status = FilmBasePickStatus::ok;
            result.rgb = {
                static_cast<float>((*snapped)[0]),
                static_cast<float>((*snapped)[1]),
                static_cast<float>((*snapped)[2]),
            };
            return result;
        }

        const double side = std::max(
            3.0,
            static_cast<double>(std::min(image.width, image.height)) * region_fraction);
        const std::optional<PixelRect> region =
            integral_intersection(center_x, center_y, side, image.width, image.height);
        if (!region.has_value()) {
            result.status = FilmBasePickStatus::implausible;
            return result;
        }
        const std::optional<BaseMeasurement> sampled = median_rgb(image, *region);
        if (!sampled.has_value() ||
            ((*sampled)[0] <= 0.0 && (*sampled)[1] <= 0.0 && (*sampled)[2] <= 0.0)) {
            result.status = FilmBasePickStatus::implausible;
            return result;
        }
        const BaseMeasurement clamped = clamp_rgb(*sampled);
        if (!is_plausible_base(clamped, reference, film_type)) {
            result.status = FilmBasePickStatus::implausible;
            return result;
        }
        result.status = FilmBasePickStatus::ok;
        result.rgb = {
            static_cast<float>(clamped[0]),
            static_cast<float>(clamped[1]),
            static_cast<float>(clamped[2]),
        };
        return result;
    } catch (...) {
        // 할당 실패가 noexcept ABI 경계를 넘게 두지 않습니다. 호출부는 Dmin 을 바꾸지
        // 않으므로 잘못된 베이스가 앉는 일은 없습니다.
        result.status = FilmBasePickStatus::invalid_image;
        return result;
    }
}

const char* film_base_pick_status_name(const FilmBasePickStatus status) noexcept {
    switch (status) {
        case FilmBasePickStatus::ok:
            return "ok";
        case FilmBasePickStatus::invalid_image:
            return "invalid_image";
        case FilmBasePickStatus::implausible:
            return "implausible";
    }
    return "unknown_film_base_pick_status";
}

}  // namespace negaflow::imaging
