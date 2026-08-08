#include "negaflow/core/pointwise.h"

#include <algorithm>
#include <cmath>

namespace negaflow::core {
namespace {

[[nodiscard]] bool finite_rgb(const Rgba32F pixel) noexcept {
    return std::isfinite(pixel.red) && std::isfinite(pixel.green) &&
           std::isfinite(pixel.blue);
}

template <typename Transform>
[[nodiscard]] KernelStatus apply_pointwise(
    const ConstImageView input,
    const ImageView output,
    Transform transform) noexcept {
    const KernelStatus compatibility_status = validate_compatible_views(input, output);
    if (compatibility_status != KernelStatus::ok) {
        return compatibility_status;
    }
    const KernelStatus input_status = validate_finite_pixels(input);
    if (input_status != KernelStatus::ok) {
        return input_status;
    }

    for (std::uint32_t row = 0U; row < input.height; ++row) {
        const std::size_t input_offset = static_cast<std::size_t>(row) * input.stride_pixels;
        const std::size_t output_offset = static_cast<std::size_t>(row) * output.stride_pixels;
        for (std::uint32_t column = 0U; column < input.width; ++column) {
            const Rgba32F source = input.pixels[input_offset + column];
            const Rgba32F result = transform(source);
            if (!finite_rgb(result)) {
                return KernelStatus::non_finite_output;
            }
            output.pixels[output_offset + column] = result;
        }
    }
    return KernelStatus::ok;
}

}  // namespace

KernelStatus apply_exposure(
    const ConstImageView input,
    const ImageView output,
    const float stops) noexcept {
    if (!std::isfinite(stops)) {
        return KernelStatus::non_finite_parameter;
    }
    const float multiplier = std::exp2(stops);
    if (!std::isfinite(multiplier)) {
        return KernelStatus::invalid_parameter;
    }

    return apply_pointwise(input, output, [multiplier](const Rgba32F source) noexcept {
        return Rgba32F{
            source.red * multiplier,
            source.green * multiplier,
            source.blue * multiplier,
            source.alpha,
        };
    });
}

KernelStatus apply_color_matrix(
    const ConstImageView input,
    const ImageView output,
    const ColorMatrix3x4& matrix) noexcept {
    if (!std::ranges::all_of(matrix.values, [](const float value) {
            return std::isfinite(value);
        })) {
        return KernelStatus::non_finite_parameter;
    }

    return apply_pointwise(input, output, [&matrix](const Rgba32F source) noexcept {
        const auto& m = matrix.values;
        return Rgba32F{
            (m[0] * source.red) + (m[1] * source.green) +
                (m[2] * source.blue) + m[3],
            (m[4] * source.red) + (m[5] * source.green) +
                (m[6] * source.blue) + m[7],
            (m[8] * source.red) + (m[9] * source.green) +
                (m[10] * source.blue) + m[11],
            source.alpha,
        };
    });
}

}  // namespace negaflow::core
