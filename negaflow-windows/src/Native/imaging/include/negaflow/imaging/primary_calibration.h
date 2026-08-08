#pragma once

#include "negaflow/core/pixel.h"

namespace negaflow::imaging {

inline constexpr char primary_calibration_algorithm_version[] =
    "chromabase-calibration-primaries-v1";

struct PrimaryCalibrationParameters final {
    float red_hue{0.0F};
    float red_saturation{0.0F};
    float green_hue{0.0F};
    float green_saturation{0.0F};
    float blue_hue{0.0F};
    float blue_saturation{0.0F};
};

[[nodiscard]] bool has_primary_calibration_change(
    const PrimaryCalibrationParameters& parameters) noexcept;
[[nodiscard]] bool valid_primary_calibration_parameters(
    const PrimaryCalibrationParameters& parameters) noexcept;

// This is the macOS creative R/G/B-primary stage, not scanner or display
// calibration. Input/output is extended-linear sRGB. An active transform
// clamps RGB to [0, 1] before and after HSL adjustment; alpha is preserved.
// Input and output may alias.
[[nodiscard]] negaflow::core::KernelStatus apply_primary_calibration(
    negaflow::core::ConstImageView input,
    negaflow::core::ImageView output,
    const PrimaryCalibrationParameters& parameters) noexcept;

}  // namespace negaflow::imaging
