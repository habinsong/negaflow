#pragma once

#include <cmath>

namespace negaflow::imaging {

// Empirically measured from the fixed macOS Core Image radius anchors. Core
// Image's small-radius CIGaussianBlur is slightly wider than a mathematical
// Gaussian with sigma equal to inputRadius.
inline constexpr float coreimage_gaussian_variance_bias = 0.08F;

[[nodiscard]] inline float coreimage_gaussian_effective_sigma(
    const float radius) noexcept {
    return std::sqrt(
        radius * radius + coreimage_gaussian_variance_bias);
}

[[nodiscard]] inline int coreimage_gaussian_support_radius(
    const float radius) noexcept {
    return static_cast<int>(
        std::ceil(3.0F * coreimage_gaussian_effective_sigma(radius)));
}

}  // namespace negaflow::imaging
