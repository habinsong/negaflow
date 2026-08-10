#include "negaflow/imaging/color_mixer.h"

#include "negaflow/core/pointwise.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

namespace negaflow::imaging {
namespace {

constexpr float identity_epsilon = 1.0e-4F;
constexpr float chroma_epsilon = 1.0e-5F;
constexpr float band_width = 0.14F;
constexpr float hue_shift_scale = 0.0833F;
constexpr float luminance_shift_scale = 0.16F;
constexpr float gate_low = 0.04F;
constexpr float gate_high = 0.18F;
constexpr std::array<float, color_mixer_band_count> band_centers{
    0.0F,
    0.083333F,
    0.166667F,
    0.333333F,
    0.5F,
    0.666667F,
    0.75F,
    0.833333F,
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

[[nodiscard]] negaflow::core::KernelStatus validate_parameters(
    const ColorMixerParameters& parameters) noexcept {
    for (const auto* const controls : {
             &parameters.hue,
             &parameters.saturation,
             &parameters.luminance,
         }) {
        for (const float value : *controls) {
            if (!std::isfinite(value)) {
                return negaflow::core::KernelStatus::non_finite_parameter;
            }
            if (value < -1.0F || value > 1.0F) {
                return negaflow::core::KernelStatus::invalid_parameter;
            }
        }
    }
    return negaflow::core::KernelStatus::ok;
}

[[nodiscard]] Rgb apply_color_mixer_pixel(
    const Rgb source,
    const ColorMixerParameters& parameters) noexcept {
    Hsl hsl = rgb_to_hsl({
        std::clamp(source.red, 0.0F, 1.0F),
        std::clamp(source.green, 0.0F, 1.0F),
        std::clamp(source.blue, 0.0F, 1.0F),
    });

    float weight_sum = 0.0F;
    float hue_shift = 0.0F;
    float saturation_factor = 0.0F;
    float luminance_factor = 0.0F;
    for (std::size_t index = 0U; index < band_centers.size(); ++index) {
        float distance = std::abs(hsl.hue - band_centers[index]);
        distance = std::min(distance, 1.0F - distance);
        const float weight = std::max(0.0F, 1.0F - (distance / band_width));
        weight_sum += weight;
        hue_shift += weight * parameters.hue[index];
        saturation_factor += weight * parameters.saturation[index];
        luminance_factor += weight * parameters.luminance[index];
    }
    if (weight_sum > identity_epsilon) {
        hue_shift /= weight_sum;
        saturation_factor /= weight_sum;
        luminance_factor /= weight_sum;
    }

    const float gate = smoothstep(gate_low, gate_high, hsl.saturation);
    const float shifted_hue =
        hsl.hue + (hue_shift * hue_shift_scale * gate) + 1.0F;
    hsl.hue = shifted_hue - std::floor(shifted_hue);
    hsl.saturation = std::clamp(
        hsl.saturation * (1.0F + (saturation_factor * gate)),
        0.0F,
        1.0F);
    hsl.lightness = std::clamp(
        hsl.lightness + (luminance_factor * luminance_shift_scale * gate),
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

bool has_color_mixer_change(const ColorMixerParameters& parameters) noexcept {
    for (const auto* const controls : {
             &parameters.hue,
             &parameters.saturation,
             &parameters.luminance,
         }) {
        for (const float value : *controls) {
            if (std::abs(value) >= identity_epsilon) {
                return true;
            }
        }
    }
    return false;
}

bool valid_color_mixer_parameters(
    const ColorMixerParameters& parameters) noexcept {
    return validate_parameters(parameters) == negaflow::core::KernelStatus::ok;
}

negaflow::core::KernelStatus apply_color_mixer(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output,
    const ColorMixerParameters& parameters) noexcept {
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

    if (!has_color_mixer_change(parameters)) {
        negaflow::core::copy_validated_rows(input, output);
        return negaflow::core::KernelStatus::ok;
    }

    return negaflow::core::transform_validated_pointwise(
        input,
        output,
        [&parameters](const negaflow::core::Rgba32F source) noexcept {
            const Rgb result = apply_color_mixer_pixel(
                {source.red, source.green, source.blue},
                parameters);
            return negaflow::core::Rgba32F{
                result.red,
                result.green,
                result.blue,
                source.alpha,
            };
        });
}

}  // namespace negaflow::imaging
