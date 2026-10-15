#include "negaflow/core/pointwise.h"

#include <algorithm>
#include <cmath>

namespace negaflow::core {

double exposed_luminance(
    const double luminance,
    const double stops,
    const double headroom_stops) noexcept {
    const double exposed = luminance * std::exp2(stops);
    const double knee = static_cast<double>(exposure_shoulder_knee());
    if (!(stops > 0.0) || exposed <= knee || !(headroom_stops > 0.0)) {
        return exposed;
    }
    const double room = 1.0 - knee;
    const double shoulder = 1.0 - (room * std::exp(-(exposed - knee) / room));
    return exposed + ((shoulder - exposed) * std::clamp(stops / headroom_stops, 0.0, 1.0));
}

KernelStatus apply_exposure(
    const ConstImageView input,
    const ImageView output,
    const float stops,
    const float headroom_stops) noexcept {
    if (!std::isfinite(stops) || !std::isfinite(headroom_stops)) {
        return KernelStatus::non_finite_parameter;
    }
    const float multiplier = std::exp2(stops);
    if (!std::isfinite(multiplier) || !(headroom_stops > 0.0F)) {
        return KernelStatus::invalid_parameter;
    }

    const float blend = exposure_shoulder_blend(stops, headroom_stops);
    if (blend <= 0.0F) {
        return apply_pointwise(input, output, [multiplier](const Rgba32F source) noexcept {
            return Rgba32F{
                source.red * multiplier,
                source.green * multiplier,
                source.blue * multiplier,
                source.alpha,
            };
        });
    }
    const float knee = exposure_shoulder_knee();
    const float room = 1.0F - knee;
    return apply_pointwise(
        input, output, [multiplier, knee, room, blend](const Rgba32F source) noexcept {
            const float red = source.red * multiplier;
            const float green = source.green * multiplier;
            const float blue = source.blue * multiplier;
            const float luminance = (0.2126F * red) + (0.7152F * green) + (0.0722F * blue);
            if (luminance <= knee) {
                return Rgba32F{red, green, blue, source.alpha};
            }
            const float shoulder = 1.0F - (room * std::exp(-(luminance - knee) / room));
            const float scale = (luminance + ((shoulder - luminance) * blend)) / luminance;
            return Rgba32F{red * scale, green * scale, blue * scale, source.alpha};
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
