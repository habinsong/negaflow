#pragma once

/* 텍스처 단계가 쓰는 화소 산술과 공용 타입입니다. 화소마다 불리므로 헤더에 inline 으로
   둡니다 - 언샤프·그레인·명료도·헐레이션·비네트가 같은 셈을 봐야 합니다. */

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/texture_stage.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>

namespace negaflow::imaging::texture_stage_detail {

struct Rgb final {
    float red;
    float green;
    float blue;
};

struct FilterSample final {
    Rgb color{};
    float alpha{0.0F};
};

enum class GaussianEdgeMode {
    clamp,
    mirror,
    transparent,
};

[[nodiscard]] inline std::size_t checked_count(
    const std::uint32_t width,
    const std::uint32_t height) {
    if (width == 0U || height == 0U ||
        static_cast<std::size_t>(width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(height)) {
        throw std::bad_alloc{};
    }
    return static_cast<std::size_t>(width) * height;
}

[[nodiscard]] inline std::size_t index_of(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t width) noexcept {
    return static_cast<std::size_t>(y) * width + x;
}

[[nodiscard]] inline Rgb rgb(const negaflow::core::Rgba32F value) noexcept {
    return {value.red, value.green, value.blue};
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

[[nodiscard]] inline Rgb mix(
    const Rgb first,
    const Rgb second,
    const float weight) noexcept {
    return first + (second - first) * weight;
}

[[nodiscard]] inline float luminance(const Rgb value) noexcept {
    return value.red * 0.2126F + value.green * 0.7152F +
           value.blue * 0.0722F;
}

[[nodiscard]] inline float smoothstep(
    const float edge0,
    const float edge1,
    const float value) noexcept {
    const float t = clamp_unit((value - edge0) / (edge1 - edge0));
    return t * t * (3.0F - 2.0F * t);
}

[[nodiscard]] inline std::uint32_t coordinate_hash(
    const std::uint32_t x,
    const std::uint32_t y) noexcept {
    std::uint32_t value = x * 0x9e3779b9U ^ y * 0x85ebca6bU ^ 0xc2b2ae35U;
    value ^= value >> 16U;
    value *= 0x7feb352dU;
    value ^= value >> 15U;
    value *= 0x846ca68bU;
    value ^= value >> 16U;
    return value;
}

}  // namespace negaflow::imaging::texture_stage_detail
