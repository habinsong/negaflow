#include "negaflow/imaging/color_grading.h"

#include "negaflow/core/pointwise.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {
namespace {

constexpr float identity_epsilon = 1.0e-4F;
constexpr float red_luma = 0.2126F;
constexpr float green_luma = 0.7152F;
constexpr float blue_luma = 0.0722F;
constexpr float tint_scale = 0.75F;
constexpr float luminance_scale = 0.22F;

struct Rgb final {
    float red;
    float green;
    float blue;
};

struct PreparedRegion final {
    Rgb offset;
};

[[nodiscard]] float luma(const Rgb color) noexcept {
    return (color.red * red_luma) + (color.green * green_luma) +
           (color.blue * blue_luma);
}

[[nodiscard]] float smoothstep(
    const float lower,
    const float upper,
    const float value) noexcept {
    const float t = std::clamp((value - lower) / (upper - lower), 0.0F, 1.0F);
    return t * t * (3.0F - (2.0F * t));
}

[[nodiscard]] Rgb hsv_tint(
    const float hue_degrees,
    const float saturation) noexcept {
    const double hue = static_cast<double>(hue_degrees) / 360.0;
    const double wrapped = std::fmod(std::fmod(hue, 1.0) + 1.0, 1.0) * 6.0;
    const int sector = static_cast<int>(wrapped);
    const double fraction = wrapped - static_cast<double>(sector);
    const double p = 0.0;
    const double q = 1.0 - fraction;
    const double t = fraction;

    std::array<double, 3> rgb{};
    switch (sector % 6) {
        case 0:
            rgb = {1.0, t, p};
            break;
        case 1:
            rgb = {q, 1.0, p};
            break;
        case 2:
            rgb = {p, 1.0, t};
            break;
        case 3:
            rgb = {p, q, 1.0};
            break;
        case 4:
            rgb = {t, p, 1.0};
            break;
        default:
            rgb = {1.0, p, q};
            break;
    }

    const double amount = static_cast<double>(saturation);
    return {
        static_cast<float>(rgb[0] * amount),
        static_cast<float>(rgb[1] * amount),
        static_cast<float>(rgb[2] * amount),
    };
}

[[nodiscard]] PreparedRegion prepare_region(
    const ColorGradeRegion& region) noexcept {
    const Rgb tint = hsv_tint(region.hue_degrees, region.saturation);
    const float tint_luma = luma(tint);
    const float luminance_offset = region.luminance * luminance_scale;
    return {
        {
            ((tint.red - tint_luma) * tint_scale) + luminance_offset,
            ((tint.green - tint_luma) * tint_scale) + luminance_offset,
            ((tint.blue - tint_luma) * tint_scale) + luminance_offset,
        },
    };
}

[[nodiscard]] float apply_region_channel(
    const float source,
    const float weight,
    const float offset) noexcept {
    return source + (weight * offset);
}

[[nodiscard]] Rgb apply_color_grading_pixel(
    const Rgb source,
    const PreparedRegion& shadows,
    const PreparedRegion& midtones,
    const PreparedRegion& highlights,
    const float pivot,
    const float width) noexcept {
    const float source_luma = luma(source);
    const float transition = smoothstep(
        pivot - width,
        pivot + width,
        source_luma);
    const float shadow_weight = 1.0F - transition;
    const float highlight_weight = transition;
    const float midtone_weight = std::clamp(
        1.0F - (std::abs(source_luma - pivot) / width),
        0.0F,
        1.0F);

    Rgb result = source;
    result.red = apply_region_channel(
        result.red,
        shadow_weight,
        shadows.offset.red);
    result.green = apply_region_channel(
        result.green,
        shadow_weight,
        shadows.offset.green);
    result.blue = apply_region_channel(
        result.blue,
        shadow_weight,
        shadows.offset.blue);

    result.red = apply_region_channel(
        result.red,
        midtone_weight,
        midtones.offset.red);
    result.green = apply_region_channel(
        result.green,
        midtone_weight,
        midtones.offset.green);
    result.blue = apply_region_channel(
        result.blue,
        midtone_weight,
        midtones.offset.blue);

    result.red = apply_region_channel(
        result.red,
        highlight_weight,
        highlights.offset.red);
    result.green = apply_region_channel(
        result.green,
        highlight_weight,
        highlights.offset.green);
    result.blue = apply_region_channel(
        result.blue,
        highlight_weight,
        highlights.offset.blue);
    return {
        std::clamp(result.red, 0.0F, 1.0F),
        std::clamp(result.green, 0.0F, 1.0F),
        std::clamp(result.blue, 0.0F, 1.0F),
    };
}

[[nodiscard]] negaflow::core::KernelStatus validate_parameters(
    const ColorGradingParameters& parameters) noexcept {
    for (const auto* const region : {
             &parameters.shadows,
             &parameters.midtones,
             &parameters.highlights,
         }) {
        if (!std::isfinite(region->hue_degrees) ||
            !std::isfinite(region->saturation) ||
            !std::isfinite(region->luminance)) {
            return negaflow::core::KernelStatus::non_finite_parameter;
        }
        if (region->hue_degrees < 0.0F || region->hue_degrees > 360.0F ||
            region->saturation < 0.0F || region->saturation > 1.0F ||
            region->luminance < -1.0F || region->luminance > 1.0F) {
            return negaflow::core::KernelStatus::invalid_parameter;
        }
    }
    if (!std::isfinite(parameters.blending) ||
        !std::isfinite(parameters.balance)) {
        return negaflow::core::KernelStatus::non_finite_parameter;
    }
    if (parameters.blending < 0.0F || parameters.blending > 1.0F ||
        parameters.balance < -1.0F || parameters.balance > 1.0F) {
        return negaflow::core::KernelStatus::invalid_parameter;
    }
    return negaflow::core::KernelStatus::ok;
}

[[nodiscard]] bool region_has_change(const ColorGradeRegion& region) noexcept {
    return region.saturation > identity_epsilon ||
           std::abs(region.luminance) > identity_epsilon;
}

}  // namespace

bool has_color_grading_change(
    const ColorGradingParameters& parameters) noexcept {
    return region_has_change(parameters.shadows) ||
           region_has_change(parameters.midtones) ||
           region_has_change(parameters.highlights);
}

bool valid_color_grading_parameters(
    const ColorGradingParameters& parameters) noexcept {
    return validate_parameters(parameters) == negaflow::core::KernelStatus::ok;
}

negaflow::core::KernelStatus apply_color_grading(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output,
    const ColorGradingParameters& parameters) noexcept {
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

    if (!has_color_grading_change(parameters)) {
        negaflow::core::copy_validated_rows(input, output);
        return negaflow::core::KernelStatus::ok;
    }

    const PreparedRegion shadows = prepare_region(parameters.shadows);
    const PreparedRegion midtones = prepare_region(parameters.midtones);
    const PreparedRegion highlights = prepare_region(parameters.highlights);
    const float pivot = std::clamp(
        0.5F + (parameters.balance * 0.30F),
        0.15F,
        0.85F);
    const float width =
        (0.10F * (1.0F - parameters.blending)) +
        (0.50F * parameters.blending);
    return negaflow::core::transform_validated_pointwise(
        input,
        output,
        [shadows, midtones, highlights, pivot, width](
            const negaflow::core::Rgba32F source) noexcept {
            const Rgb result = apply_color_grading_pixel(
                {source.red, source.green, source.blue},
                shadows,
                midtones,
                highlights,
                pivot,
                width);
            return negaflow::core::Rgba32F{
                result.red,
                result.green,
                result.blue,
                source.alpha,
            };
        });
}

}  // namespace negaflow::imaging
