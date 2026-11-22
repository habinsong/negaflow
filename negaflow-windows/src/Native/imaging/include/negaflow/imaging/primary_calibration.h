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
    // 사용자 슬라이더는 HSL 을 sRGB 인코딩 값에서 계산합니다(macOS `CalibrationStage`
    // `perceptual`). 디지털 필름 룩 프리셋은 감마 값을 넘기므로 false 입니다.
    bool perceptual{true};
};

[[nodiscard]] bool has_primary_calibration_change(
    const PrimaryCalibrationParameters& parameters) noexcept;
[[nodiscard]] bool valid_primary_calibration_parameters(
    const PrimaryCalibrationParameters& parameters) noexcept;

// This is the macOS creative R/G/B-primary stage, not scanner or display
// calibration. Input/output is extended-linear sRGB. An active transform
// adjusts the [0, 1] part (sRGB-encoded when `perceptual`) and, on the slider
// path, adds back what lay outside [0, 1]; alpha is preserved.
// Input and output may alias.
[[nodiscard]] negaflow::core::KernelStatus apply_primary_calibration(
    negaflow::core::ConstImageView input,
    negaflow::core::ImageView output,
    const PrimaryCalibrationParameters& parameters) noexcept;

}  // namespace negaflow::imaging
