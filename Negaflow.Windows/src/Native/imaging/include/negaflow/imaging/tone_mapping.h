#pragma once

#include "negaflow/core/pixel.h"

namespace negaflow::imaging {

inline constexpr char tone_mapping_algorithm_version[] = "chromabase-tone-v1";
inline constexpr float tone_change_threshold = 1.0e-3F;

struct BasicToneParameters final {
    float contrast{0.0F};
    float density{0.0F};
    float highlights{0.0F};
    float shadows{0.0F};
    float whites{0.0F};
    float blacks{0.0F};
};

struct ParametricToneCurveParameters final {
    float highlights{0.0F};
    float lights{0.0F};
    float darks{0.0F};
    float shadows{0.0F};
};

struct ParametricToneCurveBands final {
    float shadow_low{0.05F};
    float shadow_high{0.24F};
    float dark_low{0.18F};
    float dark_high{0.36F};
    float light_low{0.34F};
    float light_high{0.68F};
    float highlight_low{0.36F};
    float highlight_high{0.50F};
};

[[nodiscard]] constexpr ParametricToneCurveBands
fallback_parametric_tone_curve_bands() noexcept {
    return {};
}

[[nodiscard]] bool has_basic_tone_change(
    const BasicToneParameters& parameters) noexcept;
[[nodiscard]] bool has_parametric_tone_curve_change(
    const ParametricToneCurveParameters& parameters) noexcept;

// These pointwise kernels reproduce the macOS Chromabase Metal scalar formulas.
// Input and output may alias. RGB is mapped to display-referred [0, 1], while alpha is preserved.
[[nodiscard]] negaflow::core::KernelStatus apply_basic_tone(
    negaflow::core::ConstImageView input,
    negaflow::core::ImageView output,
    const BasicToneParameters& parameters) noexcept;

[[nodiscard]] negaflow::core::KernelStatus apply_parametric_tone_curve(
    negaflow::core::ConstImageView input,
    negaflow::core::ImageView output,
    const ParametricToneCurveParameters& parameters,
    const ParametricToneCurveBands& bands) noexcept;

}  // namespace negaflow::imaging
