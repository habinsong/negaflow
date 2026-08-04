#pragma once

namespace negaflow::color {

// Converts an sRGB-encoded component to linear light without clamping extended values.
[[nodiscard]] float srgb_encoded_to_linear(float encoded) noexcept;

// Converts a linear-light component to sRGB encoding without clamping extended values.
[[nodiscard]] float linear_to_srgb_encoded(float linear) noexcept;

}  // namespace negaflow::color
