#include "defect_component_structure_probe.h"

#include <algorithm>
#include <cmath>
#include <cstddef>

namespace negaflow::imaging::defect_component_repair_detail {

using negaflow::core::Rgba32F;

[[nodiscard]] float luma(const FillColor color) noexcept {
    return color.red * 0.2126F + color.green * 0.7152F + color.blue * 0.0722F;
}

[[nodiscard]] std::optional<ClearSample> nearest_clear(
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const int x,
    const int y,
    const int dx,
    const int dy,
    const int maximum_step) noexcept {
    for (int step = 1; step <= maximum_step; ++step) {
        const int sample_x = x + dx * step;
        const int sample_y = y + dy * step;
        if (sample_x < 0 || sample_y < 0 || sample_x >= width ||
            sample_y >= height) {
            return std::nullopt;
        }
        const std::size_t index =
            static_cast<std::size_t>(sample_y) * width + sample_x;
        if (damaged[index] == 0U) {
            const Rgba32F sample = source[index];
            return ClearSample{
                sample.red,
                sample.green,
                sample.blue,
                step,
                sample_x,
                sample_y,
            };
        }
    }
    return std::nullopt;
}

[[nodiscard]] float ridge_support(
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const ClearSample endpoint,
    const Direction direction) noexcept {
    const int perpendicular_x = -direction.dy;
    const int perpendicular_y = direction.dx;
    float total = 0.0F;
    float count = 0.0F;
    for (const int sign : {-1, 1}) {
        float side = 0.0F;
        bool found = false;
        for (int step = 1; step <= 3; ++step) {
            const int x = endpoint.x + perpendicular_x * sign * step;
            const int y = endpoint.y + perpendicular_y * sign * step;
            if (x < 0 || y < 0 || x >= width || y >= height) {
                continue;
            }
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            if (damaged[index] != 0U) {
                continue;
            }
            const Rgba32F sample = source[index];
            const float difference =
                std::abs(endpoint.red - sample.red) +
                std::abs(endpoint.green - sample.green) +
                std::abs(endpoint.blue - sample.blue);
            side = std::max(side, difference);
            found = true;
        }
        if (found) {
            total += side;
            count += 1.0F;
        }
    }
    return count > 0.0F ? total / count : 0.0F;
}

[[nodiscard]] float cross_penalty(
    const Direction direction,
    const std::optional<double> cross_angle) noexcept {
    if (!cross_angle.has_value()) {
        return 0.0F;
    }
    double direction_angle = std::atan2(
        static_cast<double>(direction.dy),
        static_cast<double>(direction.dx)) *
        180.0 / 3.14159265358979323846;
    if (direction_angle < 0.0) {
        direction_angle += 180.0;
    }
    const double difference = std::fmod(
        std::abs(direction_angle - *cross_angle),
        180.0);
    const double acute = std::min(difference, 180.0 - difference);
    return static_cast<float>(acute / 90.0) * 0.20F;
}

}  // namespace negaflow::imaging::defect_component_repair_detail
