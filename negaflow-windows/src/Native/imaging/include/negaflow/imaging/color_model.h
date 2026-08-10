#pragma once

#include "negaflow/core/pixel.h"

namespace negaflow::imaging {

inline constexpr char color_model_algorithm_version[] =
    "chromabase-color-model-v1";

struct ColorModelParameters final {
    float warmth{0.0F};
    float tint{0.0F};
    float color_depth{0.0F};
    float vibrance{0.0F};
    float saturation{0.0F};
    float red_primary{0.0F};
    float green_primary{0.0F};
    float blue_primary{0.0F};
};

[[nodiscard]] bool has_color_model_change(
    const ColorModelParameters& parameters) noexcept;
[[nodiscard]] bool valid_color_model_parameters(
    const ColorModelParameters& parameters) noexcept;

// Applies the fixed macOS ColorModel order in extended-linear working RGB:
// warmth, tint, color depth, vibrance, saturation, then channel primaries.
// Input and output may alias; alpha and stride padding are preserved.
[[nodiscard]] negaflow::core::KernelStatus apply_color_model(
    negaflow::core::ConstImageView input,
    negaflow::core::ImageView output,
    const ColorModelParameters& parameters) noexcept;

}  // namespace negaflow::imaging
