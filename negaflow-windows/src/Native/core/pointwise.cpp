#include "negaflow/core/pointwise.h"

#include <algorithm>
#include <cmath>

namespace negaflow::core {

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
