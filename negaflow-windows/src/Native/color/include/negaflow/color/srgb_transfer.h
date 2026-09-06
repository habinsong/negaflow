#pragma once
#include <cstdint>
#include <span>

namespace negaflow::color {

// Converts an sRGB-encoded component to linear light without clamping extended values.
[[nodiscard]] float srgb_encoded_to_linear(float encoded) noexcept;
[[nodiscard]] float srgb16_to_linear(std::uint16_t encoded) noexcept;
[[nodiscard]] std::span<const float, 65536U> srgb16_to_linear_table() noexcept;

// Converts a linear-light component to sRGB encoding without clamping extended values.
[[nodiscard]] float linear_to_srgb_encoded(float linear) noexcept;

}  // namespace negaflow::color
