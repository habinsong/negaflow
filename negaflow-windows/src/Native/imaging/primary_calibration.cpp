#include "negaflow/imaging/primary_calibration.h"

#include "negaflow/core/pointwise.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {
namespace {

constexpr float identity_epsilon = 1.0e-4F;
constexpr float chroma_epsilon = 1.0e-5F;
constexpr float band_width = 0.22F;
constexpr float hue_shift_scale = 0.08F;
constexpr float gate_low = 0.03F;
constexpr float gate_high = 0.16F;
constexpr std::array<float, 3> primary_centers{
    0.0F,
    0.333333F,
    0.666667F,
};

struct Rgb final {
    float red;
    float green;
    float blue;
};

struct Hsl final {
    float hue;
    float saturation;
    float lightness;
};

struct PreparedControls final {
    std::array<float, 3> hue;
    std::array<float, 3> saturation;
};

[[nodiscard]] float smoothstep(
    const float lower,
    const float upper,
    const float value) noexcept {
    const float t = std::clamp((value - lower) / (upper - lower), 0.0F, 1.0F);
    return t * t * (3.0F - (2.0F * t));
}

[[nodiscard]] Hsl rgb_to_hsl(const Rgb color) noexcept {
    const float maximum = std::max(color.red, std::max(color.green, color.blue));
    const float minimum = std::min(color.red, std::min(color.green, color.blue));
    const float lightness = (maximum + minimum) * 0.5F;
    const float difference = maximum - minimum;

    Hsl result{0.0F, 0.0F, lightness};
    if (difference <= chroma_epsilon) {
        return result;
    }

    result.saturation = lightness > 0.5F
        ? difference / (2.0F - maximum - minimum)
        : difference / (maximum + minimum);
    if (maximum == color.red) {
        result.hue = (color.green - color.blue) / difference;
        if (color.green < color.blue) {
            result.hue += 6.0F;
        }
    } else if (maximum == color.green) {
        result.hue = ((color.blue - color.red) / difference) + 2.0F;
    } else {
        result.hue = ((color.red - color.green) / difference) + 4.0F;
    }
    result.hue /= 6.0F;
    return result;
}

[[nodiscard]] float hue_to_rgb(
    const float lower,
    const float upper,
    float hue) noexcept {
    if (hue < 0.0F) {
        hue += 1.0F;
    }
    if (hue > 1.0F) {
        hue -= 1.0F;
    }
    if (hue < (1.0F / 6.0F)) {
        return lower + ((upper - lower) * 6.0F * hue);
    }
    if (hue < 0.5F) {
        return upper;
    }
    if (hue < (2.0F / 3.0F)) {
        return lower + ((upper - lower) * ((2.0F / 3.0F) - hue) * 6.0F);
    }
    return lower;
}

[[nodiscard]] Rgb hsl_to_rgb(const Hsl color) noexcept {
    if (color.saturation < chroma_epsilon) {
        return {color.lightness, color.lightness, color.lightness};
    }
    const float upper = color.lightness < 0.5F
        ? color.lightness * (1.0F + color.saturation)
        : color.lightness + color.saturation -
              (color.lightness * color.saturation);
    const float lower = (2.0F * color.lightness) - upper;
    return {
        hue_to_rgb(lower, upper, color.hue + (1.0F / 3.0F)),
        hue_to_rgb(lower, upper, color.hue),
        hue_to_rgb(lower, upper, color.hue - (1.0F / 3.0F)),
    };
}

[[nodiscard]] PreparedControls prepare_controls(
    const PrimaryCalibrationParameters& parameters) noexcept {
    return {
        {parameters.red_hue, parameters.green_hue, parameters.blue_hue},
        {
            parameters.red_saturation,
            parameters.green_saturation,
            parameters.blue_saturation,
        },
    };
}

[[nodiscard]] negaflow::core::KernelStatus validate_parameters(
    const PrimaryCalibrationParameters& parameters) noexcept {
    for (const float value : {
             parameters.red_hue,
             parameters.red_saturation,
             parameters.green_hue,
             parameters.green_saturation,
             parameters.blue_hue,
             parameters.blue_saturation,
         }) {
        if (!std::isfinite(value)) {
            return negaflow::core::KernelStatus::non_finite_parameter;
        }
        if (value < -1.0F || value > 1.0F) {
            return negaflow::core::KernelStatus::invalid_parameter;
        }
    }
    return negaflow::core::KernelStatus::ok;
}

[[nodiscard]] Rgb apply_primary_calibration_pixel(
    const Rgb source,
    const PreparedControls& controls) noexcept {
    Hsl hsl = rgb_to_hsl({
        std::clamp(source.red, 0.0F, 1.0F),
        std::clamp(source.green, 0.0F, 1.0F),
        std::clamp(source.blue, 0.0F, 1.0F),
    });

    float weight_sum = 0.0F;
    float hue_shift = 0.0F;
    float saturation_factor = 0.0F;
    for (std::size_t index = 0U; index < primary_centers.size(); ++index) {
        float distance = std::abs(hsl.hue - primary_centers[index]);
        distance = std::min(distance, 1.0F - distance);
        const float weight = std::max(0.0F, 1.0F - (distance / band_width));
        weight_sum += weight;
        hue_shift += weight * controls.hue[index];
        saturation_factor += weight * controls.saturation[index];
    }
    if (weight_sum > identity_epsilon) {
        hue_shift /= weight_sum;
        saturation_factor /= weight_sum;
    }

    const float gate = smoothstep(gate_low, gate_high, hsl.saturation);
    const float shifted_hue =
        hsl.hue + (hue_shift * hue_shift_scale * gate) + 1.0F;
    hsl.hue = shifted_hue - std::floor(shifted_hue);
    hsl.saturation = std::clamp(
        hsl.saturation * (1.0F + (saturation_factor * gate)),
        0.0F,
        1.0F);

    const Rgb result = hsl_to_rgb(hsl);
    return {
        std::clamp(result.red, 0.0F, 1.0F),
        std::clamp(result.green, 0.0F, 1.0F),
        std::clamp(result.blue, 0.0F, 1.0F),
    };
}

}  // namespace

bool has_primary_calibration_change(
    const PrimaryCalibrationParameters& parameters) noexcept {
    for (const float value : {
             parameters.red_hue,
             parameters.red_saturation,
             parameters.green_hue,
             parameters.green_saturation,
             parameters.blue_hue,
             parameters.blue_saturation,
         }) {
        if (std::abs(value) >= identity_epsilon) {
            return true;
        }
    }
    return false;
}

bool valid_primary_calibration_parameters(
    const PrimaryCalibrationParameters& parameters) noexcept {
    return validate_parameters(parameters) == negaflow::core::KernelStatus::ok;
}

negaflow::core::KernelStatus apply_primary_calibration(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output,
    const PrimaryCalibrationParameters& parameters) noexcept {
    const negaflow::core::KernelStatus parameter_status =
        validate_parameters(parameters);
    if (parameter_status != negaflow::core::KernelStatus::ok) {
        return parameter_status;
    }
    const negaflow::core::KernelStatus compatibility_status =
        negaflow::core::validate_compatible_views(input, output);
    if (compatibility_status != negaflow::core::KernelStatus::ok) {
        return compatibility_status;
    }
    const negaflow::core::KernelStatus input_status =
        negaflow::core::validate_finite_pixels(input);
    if (input_status != negaflow::core::KernelStatus::ok) {
        return input_status;
    }

    if (!has_primary_calibration_change(parameters)) {
        negaflow::core::copy_validated_rows(input, output);
        return negaflow::core::KernelStatus::ok;
    }

    const PreparedControls controls = prepare_controls(parameters);
    return negaflow::core::transform_validated_pointwise(
        input,
        output,
        [&controls](const negaflow::core::Rgba32F source) noexcept {
            const Rgb result = apply_primary_calibration_pixel(
                {source.red, source.green, source.blue},
                controls);
            return negaflow::core::Rgba32F{
                result.red,
                result.green,
                result.blue,
                source.alpha,
            };
        });
}

}  // namespace negaflow::imaging
