#pragma once

#include "defect_component_structure_probe.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

namespace negaflow::imaging::defect_component_repair_detail {

// 손상 화소 하나를 이웃 평균으로 채웁니다. 반경 안에 성한 화소가 하나도 없으면 답하지
// 않습니다.
[[nodiscard]] std::optional<FillColor> neighborhood_fill(
    const std::vector<negaflow::core::Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    int width,
    int height,
    int x,
    int y,
    int radius) noexcept;

// 8이웃 중에 성한 화소가 하나라도 있는가. 바깥부터 안으로 채워 들어가는 순서를 정합니다.
[[nodiscard]] bool has_clear_neighbor(
    const std::vector<std::uint8_t>& damaged,
    int width,
    int height,
    int pixel) noexcept;

// 채운 색을 0…1 로 자르고 씁니다. 알파는 건드리지 않습니다.
void write_fill(
    std::vector<negaflow::core::Rgba32F>& destination,
    int pixel,
    FillColor fill) noexcept;

// 방향별로 양쪽 성한 화소를 찾아, 구조선을 잇는 방향을 골라 채웁니다.
//
// 방향 개수가 컴파일 시간에 정해지므로(보통 4, 가는 결함 8) 템플릿으로 두고 헤더에
// 정의합니다 - 호출부가 자기 방향표로 실체화합니다.
template <std::size_t DirectionCount>
[[nodiscard]] std::optional<FillColor> directional_fill(
    const std::vector<negaflow::core::Rgba32F>& source,
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

}  // namespace negaflow::imaging::defect_component_repair_detail

