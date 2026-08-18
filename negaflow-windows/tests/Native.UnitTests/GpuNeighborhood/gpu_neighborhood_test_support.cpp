#include "gpu_neighborhood_test_support.h"

#include <algorithm>
#include <cmath>
#include <iostream>

namespace gpu_neighborhood_tests {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

std::vector<Rgba32F> make_pattern() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const bool checker = ((x / 3U) + (y / 5U)) % 2U == 0U;
            const float u = static_cast<float>(x) / static_cast<float>(width - 1U);
            pixels[index_of(x, y, width)] = Rgba32F{
                checker ? 0.90F : 0.05F,
                u,
                checker ? 0.15F : 0.75F,
                1.0F};
        }
    }
    return pixels;
}

std::vector<Rgba32F> make_guided_input() {
    std::vector<Rgba32F> pixels = make_pattern();
    for (Rgba32F& pixel : pixels) {
        // 가이드는 휘도입니다 — `film_scan_denoise_tile.cpp:76` 이 그렇게 만듭니다.
        pixel.alpha = (pixel.red * 0.2126F) + (pixel.green * 0.7152F) + (pixel.blue * 0.0722F);
    }
    return pixels;
}

float worst_delta(
    const std::vector<Rgba32F>& reference,
    const std::vector<Rgba32F>& measured) noexcept {
    float worst = 0.0F;
    const std::size_t count = std::min(reference.size(), measured.size());
    for (std::size_t index = 0U; index < count; ++index) {
        worst = std::max(worst, std::abs(reference[index].red - measured[index].red));
        worst = std::max(worst, std::abs(reference[index].green - measured[index].green));
        worst = std::max(worst, std::abs(reference[index].blue - measured[index].blue));
        worst = std::max(worst, std::abs(reference[index].alpha - measured[index].alpha));
    }
    return worst;
}

void report(const char* const label, const char* const what, const int radius, const float worst) {
    if (worst > tolerance) {
        std::cerr << "FAIL: " << label << ' ' << what << " radius " << radius << " max delta "
                  << worst << '\n';
        ++failures;
        return;
    }
    std::cout << "[gpu] " << label << ' ' << what << " radius " << radius << " max delta " << worst
              << '\n';
}

}  // namespace gpu_neighborhood_tests
