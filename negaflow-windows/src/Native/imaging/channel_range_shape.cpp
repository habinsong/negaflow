#include "negaflow/imaging/channel_range_shape.h"

#include "negaflow/imaging/manual_negative_developer.h"

#include <cmath>

namespace negaflow::imaging {

bool channel_range_measurement_clipped(const std::array<float, 3>& measured) noexcept {
    const float clipped = channel_range_density_limit - 1.0e-6F;
    return !(measured[0] < clipped && measured[1] < clipped && measured[2] < clipped);
}

std::optional<std::array<float, 3>> sanitize_channel_range(const std::array<float, 3>& value) noexcept {
    for (const float channel : value) {
        if (!std::isfinite(channel) || !(channel > 0.0F)) {
            return std::nullopt;
        }
    }
    const double geometric = std::cbrt(
        static_cast<double>(value[0]) * static_cast<double>(value[1]) * static_cast<double>(value[2]));
    std::array<float, 3> normalized{};
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        normalized[channel] = static_cast<float>(static_cast<double>(value[channel]) / geometric);
        if (!(normalized[channel] >= minimum_channel_range_multiplier &&
              normalized[channel] <= maximum_channel_range_multiplier)) {
            return std::nullopt;
        }
    }
    return normalized;
}

std::optional<std::array<float, 3>> channel_range_shape(
    const std::array<float, 3>& measured_dmax) noexcept {
    if (channel_range_measurement_clipped(measured_dmax)) {
        return std::nullopt;
    }
    return sanitize_channel_range(measured_dmax);
}

}  // namespace negaflow::imaging
