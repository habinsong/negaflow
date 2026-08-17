#include "grain_mend_grain_field.h"

#include "grain_mend_component_gates.h"
#include "grain_mend_shape.h"

#include <algorithm>
#include <cmath>
#include <unordered_map>

namespace negaflow::imaging::grain_mend_detail {

// 조율값은 grain_mend_component_types.h 의 한 표에서만 옵니다.
using namespace tuning;

[[nodiscard]] std::vector<std::uint8_t> make_chunky_map(
    const std::vector<Component>& components,
    const std::size_t count) {
    std::vector<std::uint8_t> result(count, 0U);
    for (const Component& component : components) {
        if (component.pixels.size() < isolation_minimum_structure) {
            continue;
        }
        for (const std::size_t index : component.pixels) {
            result[index] = 1U;
        }
    }
    return result;
}

[[nodiscard]] bool is_isolated(
    const Component& component,
    const std::vector<std::uint8_t>& chunky,
    const DetectionImage& image) noexcept {
    const std::uint32_t box_width =
        component.maximum_x - component.minimum_x + 1U;
    const std::uint32_t box_height =
        component.maximum_y - component.minimum_y + 1U;
    const std::uint32_t padding = std::max(
        8U,
        std::min(
            isolation_maximum_ring_padding,
            2U * std::min(box_width, box_height)));
    const std::uint32_t x0 =
        component.minimum_x > padding ? component.minimum_x - padding : 0U;
    const std::uint32_t y0 =
        component.minimum_y > padding ? component.minimum_y - padding : 0U;
    const std::uint32_t x1 = std::min(
        image.width - 1U,
        component.maximum_x + padding);
    const std::uint32_t y1 = std::min(
        image.height - 1U,
        component.maximum_y + padding);
    std::size_t total = 0U;
    std::size_t hits = 0U;
    for (std::uint32_t y = y0; y <= y1; ++y) {
        const bool within_y =
            y >= component.minimum_y && y <= component.maximum_y;
        for (std::uint32_t x = x0; x <= x1; ++x) {
            if (within_y &&
                x >= component.minimum_x && x <= component.maximum_x) {
                continue;
            }
            ++total;
            if (chunky[static_cast<std::size_t>(y) * image.width + x] != 0U) {
                ++hits;
            }
        }
    }
    return total == 0U ||
           static_cast<double>(hits) / static_cast<double>(total) <=
               isolation_maximum_ring_density;
}

[[nodiscard]] std::int64_t bucket_key(const int x, const int y) noexcept {
    return static_cast<std::int64_t>(x) * 1'000'003LL +
           static_cast<std::int64_t>(y);
}

void mark_grain_field_drops(
    const std::vector<Component>& dust,
    const std::vector<Component>& scratch,
    const std::uint32_t width,
    std::vector<std::uint8_t>& drop_dust,
    std::vector<std::uint8_t>& drop_scratch) {
    std::vector<SmallComponent> small{};
    const auto add_small = [&](const std::vector<Component>& components,
                               const bool dust_kind) {
        for (std::size_t component_index = 0U;
             component_index < components.size();
             ++component_index) {
            const Component& component = components[component_index];
            if (component.pixels.size() > grain_field_small_component_maximum) {
                continue;
            }
            std::size_t sum_x = 0U;
            std::size_t sum_y = 0U;
            for (const std::size_t pixel : component.pixels) {
                sum_x += pixel % width;
                sum_y += pixel / width;
            }
            small.push_back({
                static_cast<int>(sum_x / component.pixels.size()),
                static_cast<int>(sum_y / component.pixels.size()),
                dust_kind,
                component_index,
            });
        }
    };
    add_small(dust, true);
    add_small(scratch, false);
    if (small.size() < static_cast<std::size_t>(grain_field_count)) {
        return;
    }

    std::unordered_map<std::int64_t, std::vector<std::size_t>> buckets{};
    for (std::size_t index = 0U; index < small.size(); ++index) {
        const SmallComponent& component = small[index];
        buckets[bucket_key(
            component.center_x / grain_field_radius,
            component.center_y / grain_field_radius)].push_back(index);
    }
    for (const SmallComponent& component : small) {
        const int bucket_x = component.center_x / grain_field_radius;
        const int bucket_y = component.center_y / grain_field_radius;
        int nearby = 0;
        for (int neighbor_x = bucket_x - 1;
             neighbor_x <= bucket_x + 1 && nearby < grain_field_count;
             ++neighbor_x) {
            for (int neighbor_y = std::max(0, bucket_y - 1);
                 neighbor_y <= bucket_y + 1 && nearby < grain_field_count;
                 ++neighbor_y) {
                const auto found = buckets.find(bucket_key(neighbor_x, neighbor_y));
                if (found == buckets.end()) {
                    continue;
                }
                for (const std::size_t index : found->second) {
                    const SmallComponent& other = small[index];
                    if (std::abs(other.center_x - component.center_x) <=
                            grain_field_radius &&
                        std::abs(other.center_y - component.center_y) <=
                            grain_field_radius) {
                        ++nearby;
                        if (nearby >= grain_field_count) {
                            break;
                        }
                    }
                }
            }
        }
        if (nearby >= grain_field_count) {
            if (component.dust) {
                drop_dust[component.component_index] = 1U;
            } else {
                drop_scratch[component.component_index] = 1U;
            }
        }
    }
}


}  // namespace negaflow::imaging::grain_mend_detail
