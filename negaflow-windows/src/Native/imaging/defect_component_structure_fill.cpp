#include "defect_component_structure_fill.h"

#include <algorithm>
#include <cstddef>

namespace negaflow::imaging::defect_component_repair_detail {

using negaflow::core::Rgba32F;

[[nodiscard]] std::optional<FillColor> neighborhood_fill(
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const int x,
    const int y,
    const int radius) noexcept {
    FillColor sum{};
    float count = 0.0F;
    for (int sample_y = std::max(0, y - radius);
         sample_y <= std::min(height - 1, y + radius);
         ++sample_y) {
        for (int sample_x = std::max(0, x - radius);
             sample_x <= std::min(width - 1, x + radius);
             ++sample_x) {
            const std::size_t index =
                static_cast<std::size_t>(sample_y) * width + sample_x;
            if (damaged[index] != 0U) {
                continue;
            }
            const Rgba32F sample = source[index];
            sum.red += sample.red;
            sum.green += sample.green;
            sum.blue += sample.blue;
            count += 1.0F;
        }
    }
    if (count == 0.0F) {
        return std::nullopt;
    }
    return FillColor{sum.red / count, sum.green / count, sum.blue / count};
}

[[nodiscard]] bool has_clear_neighbor(
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const int pixel) noexcept {
    const int y = pixel / width;
    const int x = pixel - y * width;
    for (int neighbor_y = std::max(0, y - 1);
         neighbor_y <= std::min(height - 1, y + 1);
         ++neighbor_y) {
        for (int neighbor_x = std::max(0, x - 1);
             neighbor_x <= std::min(width - 1, x + 1);
             ++neighbor_x) {
            if (neighbor_x == x && neighbor_y == y) {
                continue;
            }
            if (damaged[
                    static_cast<std::size_t>(neighbor_y) * width + neighbor_x] ==
                0U) {
                return true;
            }
        }
    }
    return false;
}

void write_fill(
    std::vector<Rgba32F>& destination,
    const int pixel,
    const FillColor fill) noexcept {
    Rgba32F& output = destination[static_cast<std::size_t>(pixel)];
    output.red = std::clamp(fill.red, 0.0F, 1.0F);
    output.green = std::clamp(fill.green, 0.0F, 1.0F);
    output.blue = std::clamp(fill.blue, 0.0F, 1.0F);
}

}  // namespace negaflow::imaging::defect_component_repair_detail
