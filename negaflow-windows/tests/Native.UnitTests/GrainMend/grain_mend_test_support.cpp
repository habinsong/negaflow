#include "grain_mend_test_support.h"

#include "grain_mend_detector.h"
#include "grain_mend_resample.h"
#include "grain_mend_stitch.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace grain_mend_tests {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] negaflow::imaging::WorkingImage make_clean_image(
    const std::uint32_t width,
    const std::uint32_t height) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float value = 0.18F + 0.24F *
                static_cast<float>(x) / static_cast<float>(width - 1U);
            image.pixels[static_cast<std::size_t>(y) * width + x] =
                {value, value * 0.96F, value * 0.91F, 1.0F};
        }
    }
    return image;
}

[[nodiscard]] negaflow::imaging::WorkingImage make_uniform_image(
    const std::uint32_t width,
    const std::uint32_t height,
    const float value) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.assign(
        static_cast<std::size_t>(width) * height,
        negaflow::core::Rgba32F{value, value, value, 1.0F});
    return image;
}

[[nodiscard]] bool same_pixels(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept {
    return left.size() == right.size() &&
           std::memcmp(
               left.data(),
               right.data(),
               left.size() * sizeof(negaflow::core::Rgba32F)) == 0;
}

void add_chromatic_grain(
    negaflow::imaging::WorkingImage& image,
    const std::uint32_t seed,
    const std::uint32_t probability_per_thousand,
    const float amplitude) {
    std::uint32_t state = seed;
    for (auto& pixel : image.pixels) {
        float* const channels[] = {&pixel.red, &pixel.green, &pixel.blue};
        for (float* const channel : channels) {
            state = state * 1664525U + 1013904223U;
            if ((state >> 16U) % 1000U >= probability_per_thousand) {
                continue;
            }
            state = state * 1664525U + 1013904223U;
            *channel = std::clamp(
                *channel + ((state & 1U) == 0U ? -amplitude : amplitude),
                0.0F,
                1.0F);
        }
    }
}

void add_dark_micro_speck(
    negaflow::imaging::WorkingImage& image,
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t size,
    const float drop) {
    for (std::uint32_t row = y; row < y + size; ++row) {
        for (std::uint32_t column = x; column < x + size; ++column) {
            auto& pixel = image.pixels[static_cast<std::size_t>(row) * image.width + column];
            pixel.red -= drop;
            pixel.green -= drop;
            pixel.blue -= drop;
        }
    }
}

[[nodiscard]] float pixel_error(
    const negaflow::core::Rgba32F actual,
    const negaflow::core::Rgba32F expected) noexcept {
    return std::abs(actual.red - expected.red) +
           std::abs(actual.green - expected.green) +
           std::abs(actual.blue - expected.blue);
}

[[nodiscard]] std::vector<std::size_t> draw_faint_scratch(
    negaflow::imaging::WorkingImage& image,
    const double angle_degrees) {
    constexpr double pi = 3.14159265358979323846;
    const double radians = angle_degrees * pi / 180.0;
    const double dx = std::cos(radians);
    const double dy = std::sin(radians);
    const double center_x = static_cast<double>(image.width - 1U) * 0.5;
    const double center_y = static_cast<double>(image.height - 1U) * 0.5;
    std::vector<std::size_t> pixels{};
    for (int t = -100; t <= 100; ++t) {
        const int x = static_cast<int>(std::lround(center_x + dx * t));
        const int y = static_cast<int>(std::lround(center_y + dy * t));
        if (x < 0 || y < 0 ||
            x >= static_cast<int>(image.width) ||
            y >= static_cast<int>(image.height)) {
            continue;
        }
        const std::size_t index =
            static_cast<std::size_t>(y) * image.width +
            static_cast<std::size_t>(x);
        if (std::find(pixels.begin(), pixels.end(), index) != pixels.end()) {
            continue;
        }
        pixels.push_back(index);
        image.pixels[index].red += 0.08F;
        image.pixels[index].green += 0.08F;
        image.pixels[index].blue += 0.08F;
    }
    return pixels;
}

}  // namespace grain_mend_tests
