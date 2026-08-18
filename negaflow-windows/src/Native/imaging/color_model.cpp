#include "negaflow/imaging/color_model.h"

#include "vibrance_math.h"

#include "negaflow/imaging/kernel_accelerator.h"

#include "negaflow/core/pointwise.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {
namespace {

constexpr float identity_threshold = 1.0e-3F;

struct Rgb final {
    float red;
    float green;
    float blue;
};

[[nodiscard]] float luminance(const Rgb color) noexcept {
    return (0.2126F * color.red) + (0.7152F * color.green) +
           (0.0722F * color.blue);
}

[[nodiscard]] Rgb apply_saturation(
    const Rgb color,
    const float factor) noexcept {
    const float y = luminance(color);
    return {
        y + ((color.red - y) * factor),
        y + ((color.green - y) * factor),
        y + ((color.blue - y) * factor),
    };
}

[[nodiscard]] negaflow::core::KernelStatus validate_parameters(
    const ColorModelParameters& parameters) noexcept {
    for (const float value : {
             parameters.warmth,
             parameters.tint,
             parameters.color_depth,
             parameters.vibrance,
             parameters.saturation,
             parameters.red_primary,
             parameters.green_primary,
             parameters.blue_primary,
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

[[nodiscard]] Rgb apply_pixel(
    Rgb color,
    const ColorModelParameters& parameters) noexcept {
    if (std::abs(parameters.warmth) > identity_threshold) {
        color.red *= 1.0F + (parameters.warmth * 0.18F);
        color.green *= 1.0F + (parameters.warmth * 0.03F);
        color.blue *= 1.0F - (parameters.warmth * 0.18F);
    }
    if (std::abs(parameters.tint) > identity_threshold) {
        const float red_blue = 1.0F - (parameters.tint * 0.12F);
        color.red *= red_blue;
        color.green *= 1.0F + (parameters.tint * 0.24F);
        color.blue *= red_blue;
    }
    if (std::abs(parameters.color_depth) > identity_threshold) {
        color = apply_saturation(
            color,
            1.0F + (parameters.color_depth * 0.35F));
    }
    if (std::abs(parameters.vibrance) > identity_threshold) {
        const float amount = parameters.vibrance * 0.8F;
        detail::apply_vibrance_to_channels(
            color.red,
            color.green,
            color.blue,
            amount);
    }
    if (std::abs(parameters.saturation) > identity_threshold) {
        color = apply_saturation(
            color,
            1.0F + (parameters.saturation * 0.6F));
    }
    if (std::abs(parameters.red_primary) > identity_threshold ||
        std::abs(parameters.green_primary) > identity_threshold ||
        std::abs(parameters.blue_primary) > identity_threshold) {
        color.red *= 1.0F + (parameters.red_primary * 0.32F);
        color.green *= 1.0F + (parameters.green_primary * 0.32F);
        color.blue *= 1.0F + (parameters.blue_primary * 0.32F);
    }
    return color;
}

}  // namespace

bool has_color_model_change(
    const ColorModelParameters& parameters) noexcept {
    for (const float value : {
             parameters.warmth,
             parameters.tint,
             parameters.color_depth,
             parameters.vibrance,
             parameters.saturation,
             parameters.red_primary,
             parameters.green_primary,
             parameters.blue_primary,
         }) {
        if (std::abs(value) > identity_threshold) {
            return true;
        }
    }
    return false;
}

bool valid_color_model_parameters(
    const ColorModelParameters& parameters) noexcept {
    return validate_parameters(parameters) == negaflow::core::KernelStatus::ok;
}

negaflow::core::KernelStatus apply_color_model(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output,
    const ColorModelParameters& parameters) noexcept {
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

    const bool active = has_color_model_change(parameters);
    // ☠️ **근사입니다**(33³ 표의 삼선형 + 곱셈). 입출력이 같은 버퍼일 때만 GPU 로
    //    보냅니다 — GPU 판은 텍스처 두 장을 오가므로 겹침이 없습니다.
    if (active && approximate_acceleration_allowed() &&
        input.pixels == output.pixels && input.stride_pixels == output.stride_pixels &&
        output.stride_pixels <= 0xFFFFFFFFULL) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->color_model != nullptr) {
            if (table->color_model(
                    reinterpret_cast<float*>(output.pixels),
                    output.width,
                    output.height,
                    static_cast<std::uint32_t>(output.stride_pixels),
                    &parameters)) {
                return negaflow::core::KernelStatus::ok;
            }
        }
    }
    return negaflow::core::transform_validated_pointwise(
        input,
        output,
        [active, &parameters](const negaflow::core::Rgba32F source) noexcept {
            const Rgb color = active
                ? apply_pixel({source.red, source.green, source.blue}, parameters)
                : Rgb{source.red, source.green, source.blue};
            return negaflow::core::Rgba32F{
                color.red,
                color.green,
                color.blue,
                source.alpha,
            };
        });
}

}  // namespace negaflow::imaging
