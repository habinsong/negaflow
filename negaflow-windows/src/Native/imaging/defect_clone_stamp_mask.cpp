#include "defect_clone_stamp_mask.h"

#include <algorithm>
#include <cmath>
#include <cstddef>

namespace negaflow::imaging::clone_stamp_detail {

[[nodiscard]] float stamp_alpha(
    const double normalized_distance,
    const double hardness,
    const double radius) noexcept {
    if (!(normalized_distance < 1.0)) {
        return 0.0F;
    }
    const double effective_hardness = std::clamp(
        hardness,
        0.0,
        std::max(0.0, 1.0 - antialias_pixels / std::max(radius, 1.0)));
    if (normalized_distance <= effective_hardness) {
        return 1.0F;
    }
    const double value = (normalized_distance - effective_hardness) /
        std::max(1.0 - effective_hardness, 1.0e-6);
    return static_cast<float>((1.0 - value) * (1.0 - value) *
                              (1.0 + 2.0 * value));
}

void paint_stamp(
    std::vector<float>& mask,
    const std::uint32_t mask_width,
    const std::uint32_t mask_height,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y,
    const PixelPoint center,
    const double radius,
    const double hardness) noexcept {
    const int left = std::max(
        static_cast<int>(origin_x),
        static_cast<int>(std::floor(center.x - radius - 1.0)));
    const int top = std::max(
        static_cast<int>(origin_y),
        static_cast<int>(std::floor(center.y - radius - 1.0)));
    const int right = std::min(
        static_cast<int>(origin_x + mask_width),
        static_cast<int>(std::ceil(center.x + radius + 1.0)));
    const int bottom = std::min(
        static_cast<int>(origin_y + mask_height),
        static_cast<int>(std::ceil(center.y + radius + 1.0)));
    for (int y = top; y < bottom; ++y) {
        const double dy = static_cast<double>(y) + 0.5 - center.y;
        const std::size_t row =
            static_cast<std::size_t>(y - static_cast<int>(origin_y)) *
            mask_width;
        for (int x = left; x < right; ++x) {
            const double dx = static_cast<double>(x) + 0.5 - center.x;
            const float alpha = stamp_alpha(
                std::sqrt(dx * dx + dy * dy) / radius,
                hardness,
                radius);
            if (alpha <= 0.0F) {
                continue;
            }
            float& destination =
                mask[row + static_cast<std::size_t>(
                    x - static_cast<int>(origin_x))];
            destination += alpha * (1.0F - destination);
        }
    }
}

void rasterize_stroke(
    const std::vector<PixelPoint>& points,
    const double spacing,
    const double radius,
    const double hardness,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y,
    const std::uint32_t width,
    const std::uint32_t height,
    std::vector<float>& mask) noexcept {
    if (points.empty()) {
        return;
    }
    paint_stamp(
        mask, width, height, origin_x, origin_y, points.front(), radius, hardness);
    if (points.size() == 1U) {
        return;
    }
    double distance_since_stamp = 0.0;
    PixelPoint previous = points.front();
    for (std::size_t index = 1U; index < points.size(); ++index) {
        const PixelPoint target = points[index];
        PixelPoint segment_start = previous;
        double remaining = std::hypot(
            target.x - segment_start.x,
            target.y - segment_start.y);
        while (distance_since_stamp + remaining >= spacing &&
               remaining > minimum_segment_length) {
            const double needed = spacing - distance_since_stamp;
            const double ratio = needed / remaining;
            const PixelPoint center{
                segment_start.x + (target.x - segment_start.x) * ratio,
                segment_start.y + (target.y - segment_start.y) * ratio,
            };
            paint_stamp(
                mask, width, height, origin_x, origin_y, center, radius, hardness);
            segment_start = center;
            remaining -= needed;
            distance_since_stamp = 0.0;
        }
        distance_since_stamp += remaining;
        previous = target;
    }
}

}  // namespace negaflow::imaging::clone_stamp_detail
