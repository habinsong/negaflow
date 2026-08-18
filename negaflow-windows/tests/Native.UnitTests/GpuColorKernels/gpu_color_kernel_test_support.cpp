#include "gpu_color_kernel_test_support.h"

#include <iostream>

namespace gpu_color_kernel_tests {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

std::vector<Rgba32F> make_ramp() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float u = static_cast<float>(x) / static_cast<float>(width - 1U);
            const float v = static_cast<float>(y) / static_cast<float>(height - 1U);
            pixels[(static_cast<std::size_t>(y) * width) + x] =
                Rgba32F{(u * 1.20F) - 0.10F, v, (1.0F - u) * (0.20F + (0.80F * v)), 1.0F};
        }
    }
    return pixels;
}

}  // namespace gpu_color_kernel_tests
