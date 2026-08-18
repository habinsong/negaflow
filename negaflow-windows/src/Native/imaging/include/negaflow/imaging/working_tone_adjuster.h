#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/color_grading.h"
#include "negaflow/imaging/color_mixer.h"
#include "negaflow/imaging/point_curve.h"
#include "negaflow/imaging/primary_calibration.h"
#include "negaflow/imaging/scanner_to_working.h"
#include "negaflow/imaging/tone_curve_measurement.h"
#include "negaflow/imaging/tone_mapping.h"

#include <cstdint>

namespace negaflow::imaging {

// The bounds the validator enforces. They are declared here rather than kept inside the
// .cpp so the C ABI can report them: a UI that duplicates the numbers drifts silently the
// day one of them changes, and offers the user a value the engine will refuse.
inline constexpr float maximum_exposure_stops = 5.0F;
inline constexpr float maximum_tone_control = 1.0F;

// 흰색 계열 / 검정 계열만 ±2 입니다. macOS `DevelopToneRange.whites`·`blacks` 가
// `-2...2` 이고, 그 주석 원문 — *"끝점(백점·흑점) 제어라 ±1 로는 밀리지 않는 장면이 있어
// ±2 로 둔다. 커널 계수(basicTone 의 whites 0.12 / blacks 0.06)와 마스크는 바꾸지 않는다 —
// ±1 구간의 결과는 이전과 완전히 동일하고, 넓어진 구간만 같은 기울기로 이어진다."*
//
// 2026-08-18 이전 Windows 는 이것을 `maximum_tone_control`(±1)로 막아, macOS 에서 되는
// 조작이 여기서는 **요청 자체가 거부**되었습니다(픽셀을 버리고 실패로 돌아갔습니다).
inline constexpr float maximum_endpoint_tone_control = 2.0F;

enum class WorkingToneAdjustStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    kernel_failed,
    measurement_failed,
};

struct WorkingToneAdjustParameters final {
    float exposure_stops{0.0F};
    BasicToneParameters basic{};
    ParametricToneCurveParameters curve{};
    PointCurves point_curves{};
    ColorMixerParameters color_mixer{};
    ColorGradingParameters color_grading{};
    PrimaryCalibrationParameters primary_calibration{};
};

struct WorkingToneAdjustInfo final {
    bool exposure_applied{false};
    bool basic_tone_applied{false};
    bool parametric_curve_applied{false};
    bool point_curve_applied{false};
    bool color_mixer_applied{false};
    bool color_grading_applied{false};
    bool primary_calibration_applied{false};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::invalid_argument};
    ToneCurveMeasurementResult measurement{};
};

struct WorkingToneAdjustResult final {
    WorkingToneAdjustStatus status{WorkingToneAdjustStatus::invalid_parameter};
    WorkingToneAdjustInfo info{};
    WorkingImage image{};
};

[[nodiscard]] bool valid_working_tone_adjust_parameters(
    const WorkingToneAdjustParameters& parameters) noexcept;

// Applies the macOS order in place: exposure, basic tone, measurement, parametric curve,
// then the first post-pipeline stages (point curves, mixer, grading, calibration).
// User-facing bounds are enforced here: exposure [-5, 5], all tone controls [-1, 1].
[[nodiscard]] WorkingToneAdjustResult apply_working_tone_adjustments(
    WorkingImage image,
    const WorkingToneAdjustParameters& parameters,
    const ToneCurveMeasurementLimits& measurement_limits = {}) noexcept;

[[nodiscard]] const char* working_tone_adjust_status_name(
    WorkingToneAdjustStatus status) noexcept;

}  // namespace negaflow::imaging
