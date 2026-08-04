#pragma once

#include "negaflow/core/pixel.h"

#include <array>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {

inline constexpr char color_mixer_algorithm_version[] =
    "chromabase-color-mixer-v1";
inline constexpr std::size_t color_mixer_band_count = 8U;

enum class ColorMixerBand : std::uint8_t {
    red = 0,
    orange,
    yellow,
    green,
    aqua,
    blue,
    purple,
    magenta,
};

struct ColorMixerParameters final {
    std::array<float, color_mixer_band_count> hue{};
    std::array<float, color_mixer_band_count> saturation{};
    std::array<float, color_mixer_band_count> luminance{};
};

[[nodiscard]] bool has_color_mixer_change(
    const ColorMixerParameters& parameters) noexcept;
[[nodiscard]] bool valid_color_mixer_parameters(
    const ColorMixerParameters& parameters) noexcept;

// Input/output is extended-linear sRGB. An active mixer follows the macOS
// bounded HSL boundary by clamping RGB to [0, 1] before its transform; alpha is
// preserved. Input and output may alias.
[[nodiscard]] negaflow::core::KernelStatus apply_color_mixer(
    negaflow::core::ConstImageView input,
    negaflow::core::ImageView output,
    const ColorMixerParameters& parameters) noexcept;

}  // namespace negaflow::imaging
