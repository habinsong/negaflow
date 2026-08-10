#pragma once

#include <algorithm>

namespace negaflow::imaging::detail {

inline void apply_vibrance_to_channels(
    float& red,
    float& green,
    float& blue,
    const float amount) noexcept {
    const float maximum = std::max(red, std::max(green, blue));
    const float minimum = std::min(red, std::min(green, blue));
    const float chroma = std::clamp(maximum - minimum, 0.0F, 1.0F);
    const float factor = 1.0F + (amount * (1.0F - chroma));
    const float luminance =
        (0.2126F * red) + (0.7152F * green) + (0.0722F * blue);
    red = luminance + ((red - luminance) * factor);
    green = luminance + ((green - luminance) * factor);
    blue = luminance + ((blue - luminance) * factor);
}

}  // namespace negaflow::imaging::detail
