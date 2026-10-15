#include "negaflow/imaging/analysis_region.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <numbers>

namespace negaflow::imaging {
namespace {

constexpr double straighten_threshold = 1.0e-4;
// 역변환을 거친 경계는 정수에서 1ulp 쯤 벗어납니다(830.00000000000011). 그대로 올림하면
// 사각형이 한 화소 넓어져 크롭 밖이 섞이므로, 정수에 이만큼 가까우면 그 정수로 봅니다.
constexpr double pixel_snap = 1.0e-6;

[[nodiscard]] double snapped_floor(const double value) noexcept {
    return std::floor(value + pixel_snap);
}

[[nodiscard]] double snapped_ceil(const double value) noexcept {
    return std::ceil(value - pixel_snap);
}

}  // namespace

std::optional<AnalysisRegion> make_analysis_region(
    const double left,
    const double top,
    const double width,
    const double height) noexcept {
    if (!std::isfinite(left) || !std::isfinite(top) || !std::isfinite(width) ||
        !std::isfinite(height)) {
        return std::nullopt;
    }
    const double x0 = std::max(left, 0.0);
    const double y0 = std::max(top, 0.0);
    const double x1 = std::min(left + width, 1.0);
    const double y1 = std::min(top + height, 1.0);
    if (x1 - x0 <= 0.02 || y1 - y0 <= 0.02) {
        return std::nullopt;
    }
    // 사실상 전체 프레임이면 영역이 없는 것과 같습니다.
    if (x1 - x0 >= 0.999 && y1 - y0 >= 0.999) {
        return std::nullopt;
    }
    return AnalysisRegion{x0, y0, x1 - x0, y1 - y0};
}

NormalizedPoint display_unit_to_base(
    const ImageTransformParameters& transform,
    const NormalizedPoint display,
    const std::uint32_t source_width,
    const std::uint32_t source_height) noexcept {
    double x = display.x;
    double y = display.y;

    // 1) 크롭을 풉니다. 크롭 사각형은 y-up 입니다.
    if (transform.has_crop) {
        const double up = 1.0 - y;
        x = transform.crop.x + (x * transform.crop.width);
        y = 1.0 - (transform.crop.y + (up * transform.crop.height));
    }

    // 2) 수평 보정을 풉니다 — 중심 기준 회전과 같은 비율 최대 내접 크롭의 역입니다.
    //    회전(90/270)은 비율을 뒤집으므로 그 뒤의 크기를 씁니다.
    if (std::abs(transform.straighten_angle) > straighten_threshold &&
        source_width > 0U && source_height > 0U) {
        const bool swaps = transform.rotation == ImageRotation::degrees_90 ||
                           transform.rotation == ImageRotation::degrees_270;
        const double sw = static_cast<double>(swaps ? source_height : source_width);
        const double sh = static_cast<double>(swaps ? source_width : source_height);
        const double theta = transform.straighten_angle * std::numbers::pi / 180.0;
        const double ct = std::abs(std::cos(theta));
        const double st = std::abs(std::sin(theta));
        const double hp = std::min(sw * sh / ((sw * ct) + (sh * st)),
                                   sh * sh / ((sw * st) + (sh * ct)));
        const double wp = (sw / sh) * hp;
        const double cx = sw / 2.0;
        const double cy = sh / 2.0;
        const double up = 1.0 - y;
        const double pxp = (x * wp) + (cx - (wp / 2.0));
        const double pyp = (up * hp) + (cy - (hp / 2.0));
        const double dxp = pxp - cx;
        const double dyp = pyp - cy;
        const double cosine = std::cos(theta);
        const double sine = std::sin(theta);
        const double dx = (dxp * cosine) - (dyp * sine);
        const double dy = (dxp * sine) + (dyp * cosine);
        x = (cx + dx) / sw;
        y = 1.0 - ((cy + dy) / sh);
    }

    // 3) 4분 회전을 풉니다(y-down 정규 좌표).
    switch (transform.rotation) {
        case ImageRotation::degrees_0:
            break;
        case ImageRotation::degrees_90: {
            const double rx = y;
            y = 1.0 - x;
            x = rx;
            break;
        }
        case ImageRotation::degrees_180:
            x = 1.0 - x;
            y = 1.0 - y;
            break;
        case ImageRotation::degrees_270: {
            const double rx = 1.0 - y;
            y = x;
            x = rx;
            break;
        }
    }

    // 4) 상하, 5) 좌우 뒤집기를 풉니다.
    if (transform.flip_vertical) {
        y = 1.0 - y;
    }
    if (transform.flip_horizontal) {
        x = 1.0 - x;
    }
    return {x, y};
}

std::optional<AnalysisRegion> analysis_region_from_transform(
    const ImageTransformParameters& transform,
    const std::uint32_t source_width,
    const std::uint32_t source_height) noexcept {
    if ((!transform.has_crop && std::abs(transform.straighten_angle) <= straighten_threshold) ||
        source_width == 0U || source_height == 0U) {
        return std::nullopt;
    }
    constexpr std::array<NormalizedPoint, 4> corners{{{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}, {1.0, 1.0}}};
    std::array<double, 4> xs{};
    std::array<double, 4> ys{};
    for (std::size_t index = 0U; index < corners.size(); ++index) {
        const NormalizedPoint base =
            display_unit_to_base(transform, corners[index], source_width, source_height);
        xs[index] = base.x;
        ys[index] = base.y;
    }
    // 수평 보정이 있으면 표시 사각형은 원본에서 기운 사각형입니다. 각 축의 두 번째로 작은 값과
    // 두 번째로 큰 값이 만드는 사각형은 기운 사각형 안에 들어갑니다(45° 미만) — 크롭 밖이
    // 섞이지 않습니다.
    std::sort(xs.begin(), xs.end());
    std::sort(ys.begin(), ys.end());
    return make_analysis_region(xs[1], ys[1], xs[2] - xs[1], ys[2] - ys[1]);
}

std::optional<AnalysisPixelRect> analysis_measurement_rect(
    const std::optional<AnalysisRegion>& region,
    const std::uint32_t image_width,
    const std::uint32_t image_height) noexcept {
    if (!region.has_value() || image_width == 0U || image_height == 0U) {
        return std::nullopt;
    }
    const double width = static_cast<double>(image_width);
    const double height = static_cast<double>(image_height);
    // macOS 처럼 y-up 사각형을 바깥으로 넓힙니다(아래 내림, 위 올림). 같은 화소를 고르도록
    // y-up 경계로 계산한 뒤 행 번호로 바꿉니다.
    const double up_min = 1.0 - (region->top + region->height);
    const double up_max = 1.0 - region->top;
    const double x0 = std::clamp(snapped_floor(region->left * width), 0.0, width);
    const double x1 = std::clamp(snapped_ceil((region->left + region->width) * width), 0.0, width);
    const double y_up0 = std::clamp(snapped_floor(up_min * height), 0.0, height);
    const double y_up1 = std::clamp(snapped_ceil(up_max * height), 0.0, height);
    const double rect_width = x1 - x0;
    const double rect_height = y_up1 - y_up0;
    if (rect_width <= 8.0 || rect_height <= 8.0) {
        return std::nullopt;
    }
    return AnalysisPixelRect{
        static_cast<std::uint32_t>(x0),
        static_cast<std::uint32_t>(height - y_up1),
        static_cast<std::uint32_t>(rect_width),
        static_cast<std::uint32_t>(rect_height),
    };
}

negaflow::core::ConstImageView analysis_subview(
    const negaflow::core::ConstImageView image,
    const AnalysisPixelRect& rect) noexcept {
    const std::size_t offset =
        (static_cast<std::size_t>(rect.y) * image.stride_pixels) + rect.x;
    if (rect.width == 0U || rect.height == 0U || offset >= image.pixel_capacity ||
        rect.x + rect.width > image.width || rect.y + rect.height > image.height) {
        return image;
    }
    return {
        image.pixels + offset,
        image.pixel_capacity - offset,
        rect.width,
        rect.height,
        image.stride_pixels,
    };
}

} // namespace negaflow::imaging
