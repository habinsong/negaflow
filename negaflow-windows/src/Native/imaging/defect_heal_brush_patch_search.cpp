#include "defect_heal_brush_patch_search.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>

namespace negaflow::imaging::heal_brush_detail {

void add_displacement(
    std::vector<Displacement>& values,
    const double angle,
    const double distance) {
    const int dx = static_cast<int>(std::llround(std::cos(angle) * distance));
    const int dy = static_cast<int>(std::llround(std::sin(angle) * distance));
    if (dx != 0 || dy != 0) {
        values.push_back({dx, dy});
        values.push_back({-dx, -dy});
    }
}

std::vector<int> context_ring(
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const defect_component_repair_detail::ComponentBounds& bounds) {
    std::vector<int> ring{};
    const int x0 = std::max(0, bounds.min_x - 5);
    const int x1 = std::min(width - 1, bounds.max_x + 5);
    const int y0 = std::max(0, bounds.min_y - 5);
    const int y1 = std::min(height - 1, bounds.max_y + 5);
    for (int y = y0; y <= y1; ++y) {
        for (int x = x0; x <= x1; ++x) {
            const int pixel = y * width + x;
            if (damaged[static_cast<std::size_t>(pixel)] == 0U) {
                ring.push_back(pixel);
            }
        }
    }
    if (ring.size() <= 96U) {
        return ring;
    }
    const std::size_t step = ring.size() / 96U;
    std::vector<int> sampled{};
    for (std::size_t index = 0U; index < ring.size(); index += step) {
        sampled.push_back(ring[index]);
    }
    return sampled;
}

double context_ssd(
    const std::vector<int>& ring,
    const Displacement displacement,
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height) noexcept {
    if (ring.empty()) {
        return std::numeric_limits<double>::max();
    }
    double sum = 0.0;
    std::size_t count = 0U;
    for (const int pixel : ring) {
        const int y = pixel / width;
        const int x = pixel - y * width;
        const int sx = x + displacement.dx;
        const int sy = y + displacement.dy;
        if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
            continue;
        }
        const int other = sy * width + sx;
        if (damaged[static_cast<std::size_t>(other)] != 0U) {
            continue;
        }
        const Rgba32F first = source[static_cast<std::size_t>(pixel)];
        const Rgba32F second = source[static_cast<std::size_t>(other)];
        const double dr = first.red - second.red;
        const double dg = first.green - second.green;
        const double db = first.blue - second.blue;
        sum += dr * dr + dg * dg + db * db;
        ++count;
    }
    return count * 2U >= ring.size()
        ? sum / static_cast<double>(count)
        : std::numeric_limits<double>::max();
}

std::optional<ClearRgb> find_clear(
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const int x,
    const int y,
    const double dx,
    const double dy,
    const double sign) noexcept {
    for (int step = 1; step <= 160; ++step) {
        const int sx = x + static_cast<int>(std::llround(
            dx * sign * static_cast<double>(step)));
        const int sy = y + static_cast<int>(std::llround(
            dy * sign * static_cast<double>(step)));
        if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
            break;
        }
        const std::size_t pixel =
            static_cast<std::size_t>(sy) * width + sx;
        if (damaged[pixel] == 0U) {
            const Rgba32F value = source[pixel];
            return ClearRgb{value.red, value.green, value.blue, step};
        }
    }
    return std::nullopt;
}

std::optional<Rgba32F> cross_fill(
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const int x,
    const int y,
    const double axis) noexcept {
    const std::array<double, 2U> directions{{axis + tuning::pi * 0.5, axis}};
    for (const double direction : directions) {
        const double dx = std::cos(direction);
        const double dy = std::sin(direction);
        const auto first = find_clear(
            source, damaged, width, height, x, y, dx, dy, 1.0);
        const auto second = find_clear(
            source, damaged, width, height, x, y, dx, dy, -1.0);
        if (first.has_value() && second.has_value()) {
            const float position = static_cast<float>(first->distance) /
                static_cast<float>(first->distance + second->distance);
            return Rgba32F{
                first->red + (second->red - first->red) * position,
                first->green + (second->green - first->green) * position,
                first->blue + (second->blue - first->blue) * position,
                1.0F,
            };
        }
        const auto& only = first.has_value() ? first : second;
        if (only.has_value()) {
            return Rgba32F{only->red, only->green, only->blue, 1.0F};
        }
    }
    return std::nullopt;
}

}  // namespace negaflow::imaging::heal_brush_detail
