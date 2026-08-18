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

// 화소마다 같은 값이라 한 번만 계산합니다. GPU 경로가 이것을 상수 버퍼로 올립니다 —
// **다시 구현하지 마십시오.** 두 벌이 되면 조용히 갈라집니다.
struct ColorGradingSetup final {
    // 영역별 RGB 오프셋입니다. `(tint - tint_luma) * 0.75 + luminance * 0.22`.
    float shadow_offset[3]{0.0F, 0.0F, 0.0F};
    float midtone_offset[3]{0.0F, 0.0F, 0.0F};
    float highlight_offset[3]{0.0F, 0.0F, 0.0F};
    // `clamp(0.5 + balance * 0.30, 0.15, 0.85)`
    float pivot{0.5F};
    // `0.10 * (1 - blending) + 0.50 * blending` — 항상 0.10 이상입니다.
    float width{0.30F};
};

[[nodiscard]] ColorGradingSetup prepare_color_grading(
    const ColorGradingParameters& parameters) noexcept;

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
