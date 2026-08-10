#include "defect_component_repair_detail.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

namespace negaflow::imaging::defect_component_repair_detail {
namespace {

using negaflow::core::Rgba32F;

struct Direction final {
    int dx{0};
    int dy{0};
};

struct ClearSample final {
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
    int distance{0};
    int x{0};
    int y{0};
};

struct FillColor final {
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
};

constexpr std::array<Direction, 4U> standard_directions{{
    {1, 0},
    {0, 1},
    {1, 1},
    {1, -1},
}};

constexpr std::array<Direction, 8U> thin_directions{{
    {1, 0},
    {0, 1},
    {1, 1},
    {1, -1},
    {2, 1},
    {1, 2},
    {2, -1},
    {1, -2},
}};

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

template <std::size_t DirectionCount>
[[nodiscard]] std::optional<FillColor> directional_fill(
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const std::vector<std::uint8_t>* const structure_damaged,
    const int width,
    const int height,
    const int x,
    const int y,
    const int maximum_step,
    const std::optional<double> cross_angle,
    const std::array<Direction, DirectionCount>& directions) noexcept {
    std::optional<FillColor> best{};
    float best_score = std::numeric_limits<float>::max();
    std::optional<FillColor> best_structure{};
    float best_structure_score = std::numeric_limits<float>::max();
    std::optional<FillColor> one_sided{};
    int one_sided_distance = std::numeric_limits<int>::max();
    for (const Direction direction : directions) {
        const auto first = nearest_clear(
            source,
            damaged,
            width,
            height,
            x,
            y,
            -direction.dx,
            -direction.dy,
            maximum_step);
        const auto second = nearest_clear(
            source,
            damaged,
            width,
            height,
            x,
            y,
            direction.dx,
            direction.dy,
            maximum_step);
        if (first.has_value() && second.has_value()) {
            const float color_difference =
                std::abs(first->red - second->red) +
                std::abs(first->green - second->green) +
                std::abs(first->blue - second->blue);
            const float asymmetry = static_cast<float>(
                std::abs(first->distance - second->distance));
            const float penalty = cross_penalty(direction, cross_angle);
            const float score = color_difference + 0.02F * asymmetry +
                0.004F * static_cast<float>(
                    first->distance + second->distance) +
                penalty;
            const float position = static_cast<float>(first->distance) /
                static_cast<float>(first->distance + second->distance);
            const FillColor fill{
                first->red + (second->red - first->red) * position,
                first->green + (second->green - first->green) * position,
                first->blue + (second->blue - first->blue) * position,
            };
            const float structure = std::min(
                ridge_support(
                    source,
                    damaged,
                    width,
                    height,
                    *first,
                    direction),
                ridge_support(
                    source,
                    damaged,
                    width,
                    height,
                    *second,
                    direction));
            if (structure > 0.18F && color_difference < 0.22F) {
                const float structure_score = -structure +
                    0.002F * static_cast<float>(
                        first->distance + second->distance) +
                    penalty * 0.25F;
                if (structure_score < best_structure_score) {
                    best_structure_score = structure_score;
                    best_structure = fill;
                }
            }
            if (score < best_score) {
                best_score = score;
                best = fill;
            }
        } else {
            const auto& single = first.has_value() ? first : second;
            if (single.has_value() && single->distance < one_sided_distance) {
                one_sided_distance = single->distance;
                one_sided = FillColor{single->red, single->green, single->blue};
            }
        }

        if (structure_damaged == nullptr) {
            continue;
        }
        const auto structure_first = nearest_clear(
            source,
            *structure_damaged,
            width,
            height,
            x,
            y,
            -direction.dx,
            -direction.dy,
            maximum_step);
        const auto structure_second = nearest_clear(
            source,
            *structure_damaged,
            width,
            height,
            x,
            y,
            direction.dx,
            direction.dy,
            maximum_step);
        if (!structure_first.has_value() || !structure_second.has_value()) {
            continue;
        }
        const float color_difference =
            std::abs(structure_first->red - structure_second->red) +
            std::abs(structure_first->green - structure_second->green) +
            std::abs(structure_first->blue - structure_second->blue);
        const float structure = std::min(
            ridge_support(
                source,
                *structure_damaged,
                width,
                height,
                *structure_first,
                direction),
            ridge_support(
                source,
                *structure_damaged,
                width,
                height,
                *structure_second,
                direction));
        if (structure > 0.18F && color_difference < 0.22F) {
            const float position =
                static_cast<float>(structure_first->distance) /
                static_cast<float>(
                    structure_first->distance + structure_second->distance);
            const FillColor fill{
                structure_first->red +
                    (structure_second->red - structure_first->red) * position,
                structure_first->green +
                    (structure_second->green - structure_first->green) * position,
                structure_first->blue +
                    (structure_second->blue - structure_first->blue) * position,
            };
            const float penalty = cross_penalty(direction, cross_angle);
            const float score = -structure +
                0.002F * static_cast<float>(
                    structure_first->distance + structure_second->distance) +
                penalty * 0.25F;
            if (score < best_structure_score) {
                best_structure_score = score;
                best_structure = fill;
            }
        }
    }
    if (best_structure.has_value() && best.has_value() &&
        luma(*best_structure) < luma(*best) - 0.08F) {
        return best_structure;
    }
    if (best.has_value()) {
        return best;
    }
    return best_structure.has_value() ? best_structure : one_sided;
}

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
