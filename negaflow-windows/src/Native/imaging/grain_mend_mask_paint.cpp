#include "grain_mend_mask_paint.h"

#include <algorithm>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// 조율값은 grain_mend_component_types.h 의 한 표에서만 옵니다.
using namespace tuning;

void paint_component(
    const Component& component,
    const int radius,
    const DetectionImage& image,
    std::vector<std::uint8_t>& mask) noexcept {
    for (const std::size_t pixel : component.pixels) {
        const int y = static_cast<int>(pixel / image.width);
        const int x = static_cast<int>(pixel % image.width);
        for (int dy = -radius; dy <= radius; ++dy) {
            for (int dx = -radius; dx <= radius; ++dx) {
                const int mask_x = x + dx;
                const int mask_y = y + dy;
                if (mask_x >= 0 && mask_y >= 0 &&
                    mask_x < static_cast<int>(image.width) &&
                    mask_y < static_cast<int>(image.height)) {
                    mask[static_cast<std::size_t>(mask_y) * image.width +
                         static_cast<std::size_t>(mask_x)] = 1U;
                }
            }
        }
    }
}

void fill_interior_holes(
    const Component& component,
    const DetectionImage& image,
    const std::size_t maximum_dust_area,
    std::vector<std::uint8_t>& mask) {
    const std::uint32_t x0 = component.minimum_x == 0U
        ? 0U
        : component.minimum_x - 1U;
    const std::uint32_t y0 = component.minimum_y == 0U
        ? 0U
        : component.minimum_y - 1U;
    const std::uint32_t x1 = std::min(
        image.width - 1U,
        component.maximum_x + 1U);
    const std::uint32_t y1 = std::min(
        image.height - 1U,
        component.maximum_y + 1U);
    const std::uint32_t box_width = x1 - x0 + 1U;
    const std::uint32_t box_height = y1 - y0 + 1U;
    if (box_width <= 2U || box_height <= 2U) {
        return;
    }
    const std::size_t local_count =
        static_cast<std::size_t>(box_width) * box_height;
    std::vector<std::uint8_t> outside(local_count, 0U);
    std::vector<std::size_t> stack{};
    const auto local_index = [&](const std::uint32_t x,
                                 const std::uint32_t y) noexcept {
        return static_cast<std::size_t>(y - y0) * box_width + (x - x0);
    };
    const auto defect = [&](const std::uint32_t x,
                            const std::uint32_t y) noexcept {
        return mask[static_cast<std::size_t>(y) * image.width + x] != 0U;
    };
    const auto seed = [&](const std::uint32_t x, const std::uint32_t y) {
        const std::size_t index = local_index(x, y);
        if (!defect(x, y) && outside[index] == 0U) {
            outside[index] = 1U;
            stack.push_back(index);
        }
    };
    for (std::uint32_t x = x0; x <= x1; ++x) {
        seed(x, y0);
        seed(x, y1);
    }
    for (std::uint32_t y = y0; y <= y1; ++y) {
        seed(x0, y);
        seed(x1, y);
    }
    constexpr std::array<std::pair<int, int>, 4U> neighbors{{
        {1, 0}, {-1, 0}, {0, 1}, {0, -1},
    }};
    while (!stack.empty()) {
        const std::size_t current = stack.back();
        stack.pop_back();
        const int x = static_cast<int>(current % box_width + x0);
        const int y = static_cast<int>(current / box_width + y0);
        for (const auto [dx, dy] : neighbors) {
            const int neighbor_x = x + dx;
            const int neighbor_y = y + dy;
            if (neighbor_x < static_cast<int>(x0) ||
                neighbor_y < static_cast<int>(y0) ||
                neighbor_x > static_cast<int>(x1) ||
                neighbor_y > static_cast<int>(y1)) {
                continue;
            }
            const auto nx = static_cast<std::uint32_t>(neighbor_x);
            const auto ny = static_cast<std::uint32_t>(neighbor_y);
            const std::size_t next = local_index(nx, ny);
            if (outside[next] == 0U && !defect(nx, ny)) {
                outside[next] = 1U;
                stack.push_back(next);
            }
        }
    }

    std::vector<std::size_t> holes{};
    for (std::uint32_t y = y0; y <= y1; ++y) {
        for (std::uint32_t x = x0; x <= x1; ++x) {
            if (!defect(x, y) && outside[local_index(x, y)] == 0U) {
                holes.push_back(static_cast<std::size_t>(y) * image.width + x);
            }
        }
    }
    const std::size_t maximum_hole_area = std::min(
        maximum_dust_area,
        component.pixels.size() * 2U);
    if (holes.empty() || holes.size() > maximum_hole_area) {
        return;
    }
    for (const std::size_t pixel : holes) {
        mask[pixel] = 1U;
    }
}


}  // namespace negaflow::imaging::grain_mend_detail
