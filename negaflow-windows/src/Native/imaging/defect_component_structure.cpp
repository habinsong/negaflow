#include "defect_component_repair_detail.h"

#include "defect_component_structure_fill.h"
#include "defect_component_structure_probe.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace negaflow::imaging::defect_component_repair_detail {
namespace {

using negaflow::core::Rgba32F;

void repair_component(
    std::vector<Rgba32F>& source,
    std::vector<Rgba32F>& repaired,
    std::vector<std::uint8_t>& damaged,
    const std::vector<std::uint8_t>& damaged_original,
    const int width,
    const int height,
    const std::vector<int>& component,
    const ComponentBounds& bounds,
    const std::optional<double> cross_angle,
    std::uint64_t& seed,
    std::size_t& repaired_pixel_count) {
    const int span = std::max(
        bounds.max_x - bounds.min_x,
        bounds.max_y - bounds.min_y) + 1;
    const int maximum_step = std::min(128, span + 8);
    const auto sigma = grain_sigma_rgb(
        source,
        damaged_original,
        width,
        height,
        bounds);
    std::vector<int> filled{};
    filled.reserve(component.size());
    const int thickness = std::min(
        bounds.max_x - bounds.min_x,
        bounds.max_y - bounds.min_y) + 1;
    if (thickness <= 3) {
        for (const int pixel : component) {
            const int y = pixel / width;
            const int x = pixel - y * width;
            auto fill = directional_fill(
                source,
                damaged,
                nullptr,
                width,
                height,
                x,
                y,
                maximum_step,
                cross_angle,
                thin_directions);
            if (!fill.has_value()) {
                fill = neighborhood_fill(
                    source,
                    damaged,
                    width,
                    height,
                    x,
                    y,
                    4);
            }
            if (!fill.has_value()) {
                continue;
            }
            write_fill(repaired, pixel, *fill);
            filled.push_back(pixel);
        }
    } else {
        std::vector<int> remaining = component;
        std::vector<int> layer{};
        std::vector<int> next_remaining{};
        layer.reserve(component.size());
        next_remaining.reserve(component.size());
        while (!remaining.empty()) {
            layer.clear();
            for (const int pixel : remaining) {
                if (has_clear_neighbor(damaged, width, height, pixel)) {
                    layer.push_back(pixel);
                }
            }
            if (layer.empty()) {
                layer = remaining;
            }
            const std::size_t before = remaining.size();
            for (const int pixel : layer) {
                const int y = pixel / width;
                const int x = pixel - y * width;
                auto fill = directional_fill(
                    source,
                    damaged,
                    &damaged_original,
                    width,
                    height,
                    x,
                    y,
                    maximum_step,
                    cross_angle,
                    standard_directions);
                if (!fill.has_value()) {
                    fill = neighborhood_fill(
                        source,
                        damaged,
                        width,
                        height,
                        x,
                        y,
                        4);
                }
                if (!fill.has_value()) {
                    continue;
                }
                write_fill(repaired, pixel, *fill);
                Rgba32F& feedback = source[static_cast<std::size_t>(pixel)];
                feedback.red = fill->red;
                feedback.green = fill->green;
                feedback.blue = fill->blue;
                damaged[static_cast<std::size_t>(pixel)] = 0U;
                filled.push_back(pixel);
            }
            next_remaining.clear();
            for (const int pixel : remaining) {
                if (damaged[static_cast<std::size_t>(pixel)] != 0U) {
                    next_remaining.push_back(pixel);
                }
            }
            if (next_remaining.size() == before) {
                break;
            }
            remaining.swap(next_remaining);
        }
    }
    transfer_component_texture(
        repaired,
        source,
        damaged_original,
        width,
        height,
        filled,
        component.size(),
        bounds,
        cross_angle,
        sigma,
        seed);
    repaired_pixel_count += filled.size();
}

}  // namespace

StructureRepairInfo repair_component_structures(
    std::vector<Rgba32F>& source,
    std::vector<Rgba32F>& repaired,
    std::vector<std::uint8_t>& damaged,
    const std::vector<std::uint8_t>& damaged_original,
    const int width,
    const int height,
    const std::optional<double> cross_angle,
    std::uint64_t& seed) {
    StructureRepairInfo info{};
    for_each_component(
        damaged_original,
        width,
        height,
        [&](const std::vector<int>& component, const ComponentBounds& bounds) {
            ++info.component_count;
            repair_component(
                source,
                repaired,
                damaged,
                damaged_original,
                width,
                height,
                component,
                bounds,
                cross_angle,
                seed,
                info.repaired_pixels);
        });
    return info;
}

}  // namespace negaflow::imaging::defect_component_repair_detail
