#pragma once

#include "negaflow/core/pixel.h"

namespace negaflow::imaging {

inline constexpr char tone_mapping_algorithm_version[] = "chromabase-tone-v2";
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

// 파라메트릭 커브(macOS `ParametricToneCurve`)는 인코딩(sRGB 감마) 휘도 위의 단조 곡선입니다.
// 네 슬라이더가 매듭 하나씩을 움직입니다. 매듭은 장면 휘도의 10·35·65·90 백분위(네 영역의 가운데)를
// 인코딩해 양 끝·서로 0.10 이상 떨어뜨린 자리이고, ±1 은 그 매듭을 이웃 매듭까지 거리의 0.45 배만큼
// 올리거나 내립니다. 매듭 사이는 Fritsch–Carlson 단조 3차 Hermite 입니다(Fritsch & Carlson 1980).
// 0.45 < 0.5 라 마주 움직이는 매듭도 엇갈리지 않고, 매듭 값이 증가하면 보간이 단조라 어떤 조합에서도
// 톤이 뒤집히지 않습니다. 예전 식(영역 마스크 × 고정 덧셈, 선형 휘도)은 ±1 에서 화소 중앙값 10~36% 가
// 뒤집혔습니다(2026-11-08 macOS 사용자 카탈로그 198장 실측).
//
// `knots` 가 그 네 매듭 자리입니다. 기본값은 측정을 못 할 때의 매듭 — Lightroom 기본 분할
// (25·50·75%)로 나눈 네 영역의 가운데입니다.
struct ParametricToneCurveBands final {
    double knots[4]{0.125, 0.375, 0.625, 0.875};
};

[[nodiscard]] constexpr ParametricToneCurveBands
fallback_parametric_tone_curve_bands() noexcept {
    return {};
}

// 선형 휘도 10·35·65·90 백분위 → 매듭 자리(macOS `ParametricToneCurve.knots`).
[[nodiscard]] ParametricToneCurveBands parametric_tone_curve_bands_from_percentiles(
    double p10, double p35, double p65, double p90) noexcept;

// 매듭 여섯 개(양 끝 0·1 포함)의 자리·값·기울기입니다.
struct ParametricToneCurveShape final {
    double x[6]{};
    double y[6]{};
    double tangent[6]{};
};

[[nodiscard]] ParametricToneCurveShape parametric_tone_curve_shape(
    const ParametricToneCurveParameters& parameters,
    const ParametricToneCurveBands& bands) noexcept;

// 인코딩 휘도 하나의 곡선 값입니다(커널과 같은 식, double).
[[nodiscard]] double evaluate_parametric_tone_curve(
    const ParametricToneCurveShape& shape, double encoded) noexcept;

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
