#pragma once

namespace negaflow::color {

// Converts an sRGB-encoded component to linear light without clamping extended values.
[[nodiscard]] float srgb_encoded_to_linear(float encoded) noexcept;

}  // namespace negaflow::color
