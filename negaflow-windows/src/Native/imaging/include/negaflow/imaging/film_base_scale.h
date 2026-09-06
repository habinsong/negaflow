#pragma once

#include <algorithm>
#include <array>
#include <cmath>

namespace negaflow::imaging {
[[nodiscard]] inline bool valid_film_base_scale(const double scale) noexcept {
    return std::isfinite(scale) && scale >= 0.5 && scale <= 1.5;
}

[[nodiscard]] inline std::array<float, 3> scale_auto_film_base(
    const std::array<float, 3>& reference, const double scale) noexcept {
    if (scale == 1.0) { return reference; }
    auto result = reference;
    for (auto& channel : result) {
        channel = static_cast<float>(std::clamp(static_cast<double>(channel) * scale, 0.0, 1.0));
    }
    return result;
}
}  // namespace negaflow::imaging
