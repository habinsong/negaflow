#include "defect_component_repair_detail.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::defect_component_repair_detail {
namespace {

using negaflow::core::Rgba32F;

struct Rgb final {
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
};

[[nodiscard]] float luma(const Rgb color) noexcept {
    return color.red * 0.2126F + color.green * 0.7152F + color.blue * 0.0722F;
}

[[nodiscard]] float percentile(
    const std::vector<float>& sorted,
    const double probability) noexcept {
    const double position = std::clamp(
        probability * static_cast<double>(sorted.size() - 1U),
        0.0,
        static_cast<double>(sorted.size() - 1U));
    const std::size_t low = static_cast<std::size_t>(std::floor(position));
    const std::size_t high = static_cast<std::size_t>(std::ceil(position));
    if (low == high) {
        return sorted[low];
    }
    const float weight = static_cast<float>(position - static_cast<double>(low));
    return sorted[low] + (sorted[high] - sorted[low]) * weight;
}

}  // namespace

void for_each_component(
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const ComponentCallback& callback) {
    const std::size_t count = static_cast<std::size_t>(width) * height;
    std::vector<std::uint8_t> visited(count, 0U);
    std::vector<int> stack{};
    std::vector<int> component{};
    for (std::size_t start = 0U; start < count; ++start) {
        if (damaged[start] == 0U || visited[start] != 0U) {
            continue;
        }
        stack.clear();
        component.clear();
        stack.push_back(static_cast<int>(start));
        visited[start] = 1U;
        ComponentBounds bounds{width, 0, height, 0};
        while (!stack.empty()) {
            const int pixel = stack.back();
            stack.pop_back();
            component.push_back(pixel);
            const int y = pixel / width;
            const int x = pixel - y * width;
            bounds.min_x = std::min(bounds.min_x, x);
            bounds.max_x = std::max(bounds.max_x, x);
            bounds.min_y = std::min(bounds.min_y, y);
            bounds.max_y = std::max(bounds.max_y, y);
            for (int neighbor_y = std::max(0, y - 1);
                 neighbor_y <= std::min(height - 1, y + 1);
                 ++neighbor_y) {
                for (int neighbor_x = std::max(0, x - 1);
                     neighbor_x <= std::min(width - 1, x + 1);
                     ++neighbor_x) {
                    if (neighbor_x == x && neighbor_y == y) {
                        continue;
                    }
                    const std::size_t next =
                        static_cast<std::size_t>(neighbor_y) * width + neighbor_x;
                    if (damaged[next] != 0U && visited[next] == 0U) {
                        visited[next] = 1U;
                        stack.push_back(static_cast<int>(next));
                    }
                }
            }
        }
        callback(component, bounds);
    }
}

std::vector<std::uint8_t> refine_broad_damage_mask(
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height) {
    std::vector<std::uint8_t> refined = damaged;
    for_each_component(
        damaged,
        width,
        height,
        [&](const std::vector<int>& component, const ComponentBounds& bounds) {
            const int maximum_side = std::max(
                bounds.max_x - bounds.min_x,
                bounds.max_y - bounds.min_y) + 1;
            const double average_thickness =
                static_cast<double>(component.size()) /
                static_cast<double>(std::max(1, maximum_side));
            const int box_area = std::max(
                1,
                (bounds.max_x - bounds.min_x + 1) *
                    (bounds.max_y - bounds.min_y + 1));
            const double fill_ratio = static_cast<double>(component.size()) /
                static_cast<double>(box_area);
            if (component.size() <= 700U || average_thickness <= 10.0 ||
                fill_ratio <= 0.25) {
                return;
            }
            std::vector<float> values{};
            values.reserve(component.size());
            for (const int pixel : component) {
                const Rgba32F sample = source[static_cast<std::size_t>(pixel)];
                values.push_back(luma({sample.red, sample.green, sample.blue}));
            }
            std::sort(values.begin(), values.end());
            const float median = percentile(values, 0.5);
            std::vector<float> deviations{};
            deviations.reserve(values.size());
            for (const float value : values) {
                deviations.push_back(std::abs(value - median));
            }
            std::sort(deviations.begin(), deviations.end());
            const float median_deviation = percentile(deviations, 0.5);
            const float threshold = std::max(0.055F, median_deviation * 5.0F);
            const float grow_threshold = std::max(
                0.04F,
                std::min(threshold * 0.75F, threshold - 0.015F));
            std::vector<int> keep{};
            keep.reserve(component.size() / 8U);
            for (const int pixel : component) {
                const Rgba32F sample = source[static_cast<std::size_t>(pixel)];
                if (std::abs(
                        luma({sample.red, sample.green, sample.blue}) - median) >=
                    threshold) {
                    keep.push_back(pixel);
                }
            }
            if (keep.empty() ||
                keep.size() >= static_cast<std::size_t>(
                    static_cast<double>(component.size()) * 0.85)) {
                return;
            }
            for (const int pixel : component) {
                refined[static_cast<std::size_t>(pixel)] = 0U;
            }
            for (const int pixel : keep) {
                const int y = pixel / width;
                const int x = pixel - y * width;
                for (int sample_y = std::max(bounds.min_y, y - 5);
                     sample_y <= std::min(bounds.max_y, y + 5);
                     ++sample_y) {
                    for (int sample_x = std::max(bounds.min_x, x - 5);
                         sample_x <= std::min(bounds.max_x, x + 5);
                         ++sample_x) {
                        const int dx = sample_x - x;
                        const int dy = sample_y - y;
                        if (dx * dx + dy * dy > 25) {
                            continue;
                        }
                        const std::size_t sample_index =
                            static_cast<std::size_t>(sample_y) * width + sample_x;
                        const Rgba32F sample = source[sample_index];
                        if (std::abs(
                                luma({sample.red, sample.green, sample.blue}) -
                                median) >= grow_threshold) {
                            refined[sample_index] = 1U;
                        }
                    }
                }
            }
        });
    return refined;
}

}  // namespace negaflow::imaging::defect_component_repair_detail
