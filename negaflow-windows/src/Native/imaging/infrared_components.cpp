#include "infrared_components.h"

#include <algorithm>

namespace negaflow::imaging::infrared_detail {

std::vector<RawComponent> label_components(
    const std::vector<std::uint8_t>& mask,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::size_t minimum_area) {
    std::vector<RawComponent> result{};
    std::vector<std::uint8_t> visited(mask.size(), 0U);
    std::vector<std::size_t> pending{};
    for (std::size_t seed = 0U; seed < mask.size(); ++seed) {
        if (mask[seed] == 0U || visited[seed] != 0U) continue;
        RawComponent component{};
        const auto seed_x = static_cast<std::uint32_t>(seed % width);
        const auto seed_y = static_cast<std::uint32_t>(seed / width);
        component.min_x = component.max_x = seed_x;
        component.min_y = component.max_y = seed_y;
        pending.clear();
        pending.push_back(seed);
        visited[seed] = 1U;
        while (!pending.empty()) {
            const std::size_t pixel = pending.back();
            pending.pop_back();
            component.pixels.push_back(pixel);
            const auto x = static_cast<std::uint32_t>(pixel % width);
            const auto y = static_cast<std::uint32_t>(pixel / width);
            component.min_x = std::min(component.min_x, x);
            component.max_x = std::max(component.max_x, x);
            component.min_y = std::min(component.min_y, y);
            component.max_y = std::max(component.max_y, y);
            const auto visit = [&](const std::size_t next) {
                if (mask[next] != 0U && visited[next] == 0U) {
                    visited[next] = 1U;
                    pending.push_back(next);
                }
            };
            for (std::int32_t delta_y = -1; delta_y <= 1; ++delta_y) {
                const auto next_y = static_cast<std::int64_t>(y) + delta_y;
                if (next_y < 0 || next_y >= static_cast<std::int64_t>(height)) continue;
                for (std::int32_t delta_x = -1; delta_x <= 1; ++delta_x) {
                    if (delta_x == 0 && delta_y == 0) continue;
                    const auto next_x = static_cast<std::int64_t>(x) + delta_x;
                    if (next_x < 0 || next_x >= static_cast<std::int64_t>(width)) continue;
                    visit(static_cast<std::size_t>(next_y) * width +
                          static_cast<std::uint32_t>(next_x));
                }
            }
        }
        if (component.pixels.size() >= minimum_area) {
            component.source_area = component.pixels.size();
            result.push_back(std::move(component));
        }
    }
    return result;
}

RawComponent fill_component_holes(
    RawComponent component,
    const std::uint32_t width) {
    const std::uint32_t box_width = component.max_x - component.min_x + 1U;
    const std::uint32_t box_height = component.max_y - component.min_y + 1U;
    const std::size_t box_area = static_cast<std::size_t>(box_width) * box_height;
    if (box_width < 3U || box_height < 3U || box_area > 512U * 512U ||
        box_area > component.pixels.size() * 64U) {
        return component;
    }
    std::vector<std::uint8_t> local(box_area, 0U);
    for (const std::size_t pixel : component.pixels) {
        const std::uint32_t x = static_cast<std::uint32_t>(pixel % width) - component.min_x;
        const std::uint32_t y = static_cast<std::uint32_t>(pixel / width) - component.min_y;
        local[static_cast<std::size_t>(y) * box_width + x] = 1U;
    }
    std::vector<std::uint8_t> outside(box_area, 0U);
    std::vector<std::size_t> pending{};
    const auto push = [&](const std::size_t index) {
        if (local[index] == 0U && outside[index] == 0U) {
            outside[index] = 1U;
            pending.push_back(index);
        }
    };
    for (std::uint32_t x = 0U; x < box_width; ++x) {
        push(x);
        push(static_cast<std::size_t>(box_height - 1U) * box_width + x);
    }
    for (std::uint32_t y = 0U; y < box_height; ++y) {
        push(static_cast<std::size_t>(y) * box_width);
        push(static_cast<std::size_t>(y) * box_width + box_width - 1U);
    }
    while (!pending.empty()) {
        const std::size_t index = pending.back();
        pending.pop_back();
        const std::uint32_t x = static_cast<std::uint32_t>(index % box_width);
        const std::uint32_t y = static_cast<std::uint32_t>(index / box_width);
        if (x > 0U) push(index - 1U);
        if (x + 1U < box_width) push(index + 1U);
        if (y > 0U) push(index - box_width);
        if (y + 1U < box_height) push(index + box_width);
    }
    for (std::size_t index = 0U; index < box_area; ++index) {
        if (local[index] == 0U && outside[index] == 0U) {
            const std::uint32_t x = static_cast<std::uint32_t>(index % box_width) +
                component.min_x;
            const std::uint32_t y = static_cast<std::uint32_t>(index / box_width) +
                component.min_y;
            component.pixels.push_back(static_cast<std::size_t>(y) * width + x);
        }
    }
    return component;
}

}  // namespace negaflow::imaging::infrared_detail
