#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/color_grading.h"
#include "negaflow/imaging/color_mixer.h"
#include "negaflow/imaging/point_curve.h"
#include "negaflow/imaging/scanner_to_working.h"
#include "negaflow/imaging/tone_curve_measurement.h"
#include "negaflow/imaging/tone_mapping.h"

#include <cstdint>

namespace negaflow::imaging {

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
};

struct WorkingToneAdjustInfo final {
    bool exposure_applied{false};
    bool basic_tone_applied{false};
    bool parametric_curve_applied{false};
    bool point_curve_applied{false};
    bool color_mixer_applied{false};
    bool color_grading_applied{false};
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
// then the first post-pipeline stages (point curves, HSL mixer, three-zone grading).
// User-facing bounds are enforced here: exposure [-5, 5], all tone controls [-1, 1].
[[nodiscard]] WorkingToneAdjustResult apply_working_tone_adjustments(
    WorkingImage image,
    const WorkingToneAdjustParameters& parameters,
    const ToneCurveMeasurementLimits& measurement_limits = {}) noexcept;

[[nodiscard]] const char* working_tone_adjust_status_name(
    WorkingToneAdjustStatus status) noexcept;

}  // namespace negaflow::imaging
