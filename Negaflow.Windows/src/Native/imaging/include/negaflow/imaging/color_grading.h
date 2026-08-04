#pragma once

#include "negaflow/core/pixel.h"

namespace negaflow::imaging {

inline constexpr char color_grading_algorithm_version[] =
    "chromabase-color-grading-v1";

struct ColorGradeRegion final {
    float hue_degrees{0.0F};
    float saturation{0.0F};
    float luminance{0.0F};
};

struct ColorGradingParameters final {
    ColorGradeRegion shadows{};
    ColorGradeRegion midtones{};
    ColorGradeRegion highlights{};
    float blending{0.5F};
    float balance{0.0F};
};

[[nodiscard]] bool has_color_grading_change(
    const ColorGradingParameters& parameters) noexcept;
[[nodiscard]] bool valid_color_grading_parameters(
    const ColorGradingParameters& parameters) noexcept;

// Input/output is extended-linear sRGB. An active grade follows the macOS
// bounded three-zone boundary and clamps RGB to [0, 1] after the transform;
// alpha is preserved. Input and output may alias.
[[nodiscard]] negaflow::core::KernelStatus apply_color_grading(
    negaflow::core::ConstImageView input,
    negaflow::core::ImageView output,
    const ColorGradingParameters& parameters) noexcept;

}  // namespace negaflow::imaging
