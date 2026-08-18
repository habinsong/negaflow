#pragma once

#include "film_scan_denoise_types.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>

namespace negaflow::imaging::film_scan_denoise_detail {

// 화소 단위 산술입니다. 거르기·타일·공개 진입점이 모두 같은 셈을 써야 하므로 한 곳에
// 두고, 화소마다 불리므로 헤더에 inline 으로 둡니다.

// 곱이 넘치면 할당 실패로 냅니다 - 넘친 채로 계속 가면 버퍼가 모자란 줄 모르고 씁니다.
[[nodiscard]] inline std::size_t pixel_count(
    const std::uint32_t width,
    const std::uint32_t height) {
    if (width == 0U || height == 0U ||
        static_cast<std::size_t>(width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(height)) {
        throw std::bad_alloc{};
    }
    return static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
}

[[nodiscard]] inline std::size_t index_of(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t width) noexcept {
    return static_cast<std::size_t>(y) * width + x;
}

[[nodiscard]] inline float clamp_unit(const float value) noexcept {
    return std::clamp(value, 0.0F, 1.0F);
}

[[nodiscard]] inline Rgb clamp_unit(const Rgb value) noexcept {
    return {
        clamp_unit(value.red),
        clamp_unit(value.green),
        clamp_unit(value.blue),
    };
}

[[nodiscard]] inline Rgb operator+(const Rgb left, const Rgb right) noexcept {
    return {
        left.red + right.red,
        left.green + right.green,
        left.blue + right.blue,
    };
}

[[nodiscard]] inline Rgb operator-(const Rgb left, const Rgb right) noexcept {
    return {
        left.red - right.red,
        left.green - right.green,
        left.blue - right.blue,
    };
}

[[nodiscard]] inline Rgb operator*(const Rgb value, const float scale) noexcept {
    return {
        value.red * scale,
        value.green * scale,
        value.blue * scale,
    };
}

[[nodiscard]] inline float luminance(const Rgb value) noexcept {
    return value.red * 0.2126F + value.green * 0.7152F +
           value.blue * 0.0722F;
}

[[nodiscard]] inline Rgb chroma(const Rgb value, const float luma) noexcept {
    return {
        value.red - luma,
        value.green - luma,
        value.blue - luma,
    };
}

[[nodiscard]] inline float length(const Rgb value) noexcept {
    return std::sqrt(
        value.red * value.red + value.green * value.green +
        value.blue * value.blue);
}

[[nodiscard]] inline float smoothstep(
    const float edge0,
    const float edge1,
    const float value) noexcept {
    const float t = clamp_unit((value - edge0) / (edge1 - edge0));
    return t * t * (3.0F - 2.0F * t);
}

[[nodiscard]] inline float mix(
    const float first,
    const float second,
    const float weight) noexcept {
    return first + (second - first) * weight;
}

[[nodiscard]] inline Rgb mix(
    const Rgb first,
    const Rgb second,
    const float weight) noexcept {
    return first + (second - first) * weight;
}

}  // namespace negaflow::imaging::film_scan_denoise_detail
