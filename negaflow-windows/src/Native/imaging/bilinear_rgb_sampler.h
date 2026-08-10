#pragma once

#include "negaflow/core/pixel.h"

#include <cmath>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging::detail {

struct BilinearRgb final {
    double red;
    double green;
    double blue;
};

[[nodiscard]] inline negaflow::core::Rgba32F sample_or_transparent(
    const negaflow::core::ConstImageView image,
    const std::int64_t x,
    const std::int64_t y) noexcept {
    if (x < 0 || y < 0 ||
        x >= static_cast<std::int64_t>(image.width) ||
        y >= static_cast<std::int64_t>(image.height)) {
        return {};
    }
    return image.pixels[
        static_cast<std::size_t>(y) * image.stride_pixels +
        static_cast<std::size_t>(x)];
}

// Core Image affine transforms sample at output pixel centres and use transparent
// black outside the input extent. Keep the proxy statistics on that same coordinate
// contract so a short-axis rounding difference cannot move the whole-frame grade.
[[nodiscard]] inline BilinearRgb sample_bilinear_rgb_transparent(
    const negaflow::core::ConstImageView image,
    const double x,
    const double y) noexcept {
    const double floor_x = std::floor(x);
    const double floor_y = std::floor(y);
    const auto x0 = static_cast<std::int64_t>(floor_x);
    const auto y0 = static_cast<std::int64_t>(floor_y);
    const double tx = x - floor_x;
    const double ty = y - floor_y;
    const auto top_left = sample_or_transparent(image, x0, y0);
    const auto top_right = sample_or_transparent(image, x0 + 1, y0);
    const auto bottom_left = sample_or_transparent(image, x0, y0 + 1);
    const auto bottom_right = sample_or_transparent(image, x0 + 1, y0 + 1);
    const auto interpolate = [tx, ty](
                                 const float tl,
                                 const float tr,
                                 const float bl,
                                 const float br) noexcept {
        const double top = static_cast<double>(tl) +
            ((static_cast<double>(tr) - tl) * tx);
        const double bottom = static_cast<double>(bl) +
            ((static_cast<double>(br) - bl) * tx);
        return top + ((bottom - top) * ty);
    };
    return {
        interpolate(top_left.red, top_right.red, bottom_left.red, bottom_right.red),
        interpolate(top_left.green, top_right.green, bottom_left.green, bottom_right.green),
        interpolate(top_left.blue, top_right.blue, bottom_left.blue, bottom_right.blue),
    };
}

}  // namespace negaflow::imaging::detail
