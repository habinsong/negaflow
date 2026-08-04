#include "negaflow/imaging/working_tone_adjuster.h"

#include "negaflow/core/pointwise.h"

#include <cmath>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

constexpr float maximum_exposure_stops = 5.0F;
constexpr float maximum_tone_control = 1.0F;

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] bool finite_in_range(
    const float value,
    const float magnitude_limit) noexcept {
    return std::isfinite(value) && std::abs(value) <= magnitude_limit;
}

[[nodiscard]] negaflow::core::ConstImageView const_view(
    const WorkingImage& image) noexcept {
    return {
        image.pixels.data(),
        image.pixels.size(),
        image.width,
        image.height,
        image.stride_pixels,
    };
}

[[nodiscard]] negaflow::core::ImageView mutable_view(WorkingImage& image) noexcept {
    return {
        image.pixels.data(),
        image.pixels.size(),
        image.width,
        image.height,
        image.stride_pixels,
    };
}

}  // namespace

bool valid_working_tone_adjust_parameters(
    const WorkingToneAdjustParameters& parameters) noexcept {
    return finite_in_range(parameters.exposure_stops, maximum_exposure_stops) &&
           finite_in_range(parameters.basic.contrast, maximum_tone_control) &&
           finite_in_range(parameters.basic.density, maximum_tone_control) &&
           finite_in_range(parameters.basic.highlights, maximum_tone_control) &&
           finite_in_range(parameters.basic.shadows, maximum_tone_control) &&
           finite_in_range(parameters.basic.whites, maximum_tone_control) &&
           finite_in_range(parameters.basic.blacks, maximum_tone_control) &&
           finite_in_range(parameters.curve.highlights, maximum_tone_control) &&
           finite_in_range(parameters.curve.lights, maximum_tone_control) &&
           finite_in_range(parameters.curve.darks, maximum_tone_control) &&
           finite_in_range(parameters.curve.shadows, maximum_tone_control);
}

WorkingToneAdjustResult apply_working_tone_adjustments(
    WorkingImage image,
    const WorkingToneAdjustParameters& parameters,
    const ToneCurveMeasurementLimits& measurement_limits) noexcept {
    WorkingToneAdjustResult result{};
    result.image = std::move(image);
    if (!valid_working_tone_adjust_parameters(parameters)) {
        discard_pixels(result.image);
        return result;
    }

    result.info.kernel_status = negaflow::core::validate_image_view(
        const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = WorkingToneAdjustStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }

    const bool exposure_changes =
        std::abs(parameters.exposure_stops) > tone_change_threshold;
    const bool basic_changes = has_basic_tone_change(parameters.basic);
    const bool curve_changes = has_parametric_tone_curve_change(parameters.curve);
    if (!exposure_changes && !basic_changes && !curve_changes) {
        result.info.measurement.status = ToneCurveMeasurementStatus::ok;
        result.info.measurement.kernel_status = negaflow::core::KernelStatus::ok;
        result.info.kernel_status = negaflow::core::KernelStatus::ok;
        result.status = WorkingToneAdjustStatus::ok;
        return result;
    }

    if (exposure_changes) {
        result.info.kernel_status = negaflow::core::apply_exposure(
            const_view(result.image),
            mutable_view(result.image),
            parameters.exposure_stops);
        if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
            result.status = WorkingToneAdjustStatus::kernel_failed;
            discard_pixels(result.image);
            return result;
        }
        result.info.exposure_applied = true;
    }

    if (basic_changes) {
        result.info.kernel_status = apply_basic_tone(
            const_view(result.image),
            mutable_view(result.image),
            parameters.basic);
        if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
            result.status = WorkingToneAdjustStatus::kernel_failed;
            discard_pixels(result.image);
            return result;
        }
        result.info.basic_tone_applied = true;
    }

    if (curve_changes) {
        result.info.measurement = measure_parametric_tone_curve_bands(
            const_view(result.image),
            measurement_limits);
        if (result.info.measurement.status != ToneCurveMeasurementStatus::ok) {
            result.info.kernel_status = result.info.measurement.kernel_status;
            result.status = WorkingToneAdjustStatus::measurement_failed;
            discard_pixels(result.image);
            return result;
        }
        result.info.kernel_status = apply_parametric_tone_curve(
            const_view(result.image),
            mutable_view(result.image),
            parameters.curve,
            result.info.measurement.info.bands);
        if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
            result.status = WorkingToneAdjustStatus::kernel_failed;
            discard_pixels(result.image);
            return result;
        }
        result.info.parametric_curve_applied = true;
    } else {
        result.info.measurement.status = ToneCurveMeasurementStatus::ok;
        result.info.measurement.kernel_status = negaflow::core::KernelStatus::ok;
    }

    result.info.kernel_status = negaflow::core::KernelStatus::ok;
    result.status = WorkingToneAdjustStatus::ok;
    return result;
}

const char* working_tone_adjust_status_name(
    const WorkingToneAdjustStatus status) noexcept {
    switch (status) {
        case WorkingToneAdjustStatus::ok:
            return "ok";
        case WorkingToneAdjustStatus::invalid_parameter:
            return "invalid_parameter";
        case WorkingToneAdjustStatus::kernel_failed:
            return "kernel_failed";
        case WorkingToneAdjustStatus::measurement_failed:
            return "measurement_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
