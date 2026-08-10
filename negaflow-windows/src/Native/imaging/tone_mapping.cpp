#include "negaflow/imaging/tone_mapping.h"

#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/pointwise.h"
#include "negaflow/imaging/display_gamut_map.h"

#include <algorithm>
#include <array>
#include <cmath>

namespace negaflow::imaging {
namespace {

constexpr std::array<float, 3> luma_coefficients{0.2126F, 0.7152F, 0.0722F};

[[nodiscard]] float clamp_unit(const float value) noexcept {
    return std::clamp(value, 0.0F, 1.0F);
}

[[nodiscard]] float smoothstep(
    const float edge_low,
    const float edge_high,
    const float value) noexcept {
    if (edge_low == edge_high) {
        return value < edge_low ? 0.0F : 1.0F;
    }
    const float position = clamp_unit((value - edge_low) / (edge_high - edge_low));
    return position * position * (3.0F - (2.0F * position));
}

[[nodiscard]] float luma(const negaflow::core::Rgba32F pixel) noexcept {
    return (pixel.red * luma_coefficients[0]) +
           (pixel.green * luma_coefficients[1]) +
           (pixel.blue * luma_coefficients[2]);
}


using negaflow::core::apply_pointwise;

[[nodiscard]] bool finite_basic_parameters(
    const BasicToneParameters& parameters) noexcept {
    return std::isfinite(parameters.contrast) && std::isfinite(parameters.density) &&
           std::isfinite(parameters.highlights) && std::isfinite(parameters.shadows) &&
           std::isfinite(parameters.whites) && std::isfinite(parameters.blacks);
}

[[nodiscard]] bool finite_curve_parameters(
    const ParametricToneCurveParameters& parameters) noexcept {
    return std::isfinite(parameters.highlights) && std::isfinite(parameters.lights) &&
           std::isfinite(parameters.darks) && std::isfinite(parameters.shadows);
}

[[nodiscard]] bool finite_bands(const ParametricToneCurveBands& bands) noexcept {
    return std::isfinite(bands.shadow_low) && std::isfinite(bands.shadow_high) &&
           std::isfinite(bands.dark_low) && std::isfinite(bands.dark_high) &&
           std::isfinite(bands.light_low) && std::isfinite(bands.light_high) &&
           std::isfinite(bands.highlight_low) && std::isfinite(bands.highlight_high);
}

}  // namespace

bool has_basic_tone_change(const BasicToneParameters& parameters) noexcept {
    return std::abs(parameters.contrast) > tone_change_threshold ||
           std::abs(parameters.density) > tone_change_threshold ||
           std::abs(parameters.highlights) > tone_change_threshold ||
           std::abs(parameters.shadows) > tone_change_threshold ||
           std::abs(parameters.whites) > tone_change_threshold ||
           std::abs(parameters.blacks) > tone_change_threshold;
}

bool has_parametric_tone_curve_change(
    const ParametricToneCurveParameters& parameters) noexcept {
    return std::abs(parameters.highlights) > tone_change_threshold ||
           std::abs(parameters.lights) > tone_change_threshold ||
           std::abs(parameters.darks) > tone_change_threshold ||
           std::abs(parameters.shadows) > tone_change_threshold;
}

negaflow::core::KernelStatus apply_basic_tone(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output,
    const BasicToneParameters& parameters) noexcept {
    if (!finite_basic_parameters(parameters)) {
        return negaflow::core::KernelStatus::non_finite_parameter;
    }

    return apply_pointwise(input, output, [&parameters](
        const negaflow::core::Rgba32F source) noexcept {
        const negaflow::core::Rgba32F safe =
            negaflow::imaging::tone_safe_unit_rgb(source);
        const float source_luma = luma(safe);
        const float encoded_luma = negaflow::color::linear_to_srgb_encoded(
            clamp_unit(source_luma));
        float target = encoded_luma;

        const float contrast = std::clamp(parameters.contrast, -1.0F, 1.0F);
        if (std::abs(contrast) > 1.0e-4F) {
            constexpr float pivot = 0.46F;
            const float exponent = std::pow(
                2.0F,
                contrast * (contrast > 0.0F ? 0.9F : 0.7F));
            const float curved = target < pivot
                                     ? pivot * std::pow(target / pivot, exponent)
                                     : 1.0F - ((1.0F - pivot) * std::pow(
                                           (1.0F - target) / (1.0F - pivot),
                                           exponent));
            const float blend = contrast > 0.0F
                                    ? 1.0F
                                    : smoothstep(0.12F, 0.30F, target);
            target += (curved - target) * blend;
        }

        const float mid_mask = smoothstep(0.18F, 0.36F, encoded_luma) *
                               (1.0F - smoothstep(0.58F, 0.76F, encoded_luma));
        target -= parameters.density * 0.10F * mid_mask;

        const float highlight_mask = smoothstep(0.55F, 0.80F, encoded_luma);
        target += parameters.highlights * 0.10F * highlight_mask;

        const float shadow_mask = smoothstep(0.02F, 0.08F, encoded_luma) *
                                  (1.0F - smoothstep(0.32F, 0.46F, encoded_luma));
        target += parameters.shadows * 0.10F * shadow_mask;

        const float white_mask = smoothstep(0.68F, 0.92F, encoded_luma);
        target += parameters.whites * 0.12F * white_mask;

        const float black_mask = smoothstep(0.0F, 0.03F, encoded_luma) *
                                 (1.0F - smoothstep(0.14F, 0.30F, encoded_luma));
        target += parameters.blacks * 0.06F * black_mask;

        const float new_luma = negaflow::color::srgb_encoded_to_linear(
            clamp_unit(target));
        const float delta = new_luma - source_luma;
        return negaflow::core::Rgba32F{
            clamp_unit(safe.red + delta),
            clamp_unit(safe.green + delta),
            clamp_unit(safe.blue + delta),
            source.alpha,
        };
    });
}

negaflow::core::KernelStatus apply_parametric_tone_curve(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output,
    const ParametricToneCurveParameters& parameters,
    const ParametricToneCurveBands& bands) noexcept {
    if (!finite_curve_parameters(parameters) || !finite_bands(bands)) {
        return negaflow::core::KernelStatus::non_finite_parameter;
    }

    return apply_pointwise(input, output, [&parameters, &bands](
        const negaflow::core::Rgba32F source) noexcept {
        const negaflow::core::Rgba32F safe =
            negaflow::imaging::tone_safe_unit_rgb(source);
        const float source_luma = luma(safe);
        const float shadow_mask =
            (1.0F - smoothstep(bands.shadow_low, bands.shadow_high, source_luma)) *
            smoothstep(0.0F, 0.045F, source_luma);
        const float dark_mask =
            smoothstep(bands.shadow_low, bands.shadow_high, source_luma) *
            (1.0F - smoothstep(bands.dark_low, bands.dark_high, source_luma));
        const float light_mask =
            smoothstep(bands.dark_low, bands.dark_high, source_luma) *
            (1.0F - smoothstep(bands.light_low, bands.light_high, source_luma));
        const float highlight_mask =
            smoothstep(bands.highlight_low, bands.highlight_high, source_luma);

        const float delta =
            (parameters.shadows * 0.160F * shadow_mask) +
            (parameters.darks * 0.155F * dark_mask) +
            (parameters.lights * 0.165F * light_mask) +
            (parameters.highlights * 0.150F * highlight_mask);
        const float target = clamp_unit(source_luma + delta);
        const float luma_delta = target - source_luma;
        return negaflow::core::Rgba32F{
            clamp_unit(safe.red + luma_delta),
            clamp_unit(safe.green + luma_delta),
            clamp_unit(safe.blue + luma_delta),
            source.alpha,
        };
    });
}

}  // namespace negaflow::imaging
