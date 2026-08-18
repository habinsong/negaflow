#pragma once

#include "defect_heal_brush_types.h"

#include "defect_component_repair_detail.h"

#include <cstdint>
#include <optional>
#include <vector>

namespace negaflow::imaging::heal_brush_detail {

// 각도와 거리로 변위 후보 한 쌍(정방향·역방향)을 넣습니다. 0 변위는 넣지 않습니다.
void add_displacement(
    std::vector<Displacement>& values,
    double angle,
    double distance);

// 성분 둘레의 성한 화소를 96개까지 성글게 뽑습니다. 변위 후보를 비교할 기준입니다.
[[nodiscard]] std::vector<int> context_ring(
    const std::vector<std::uint8_t>& damaged,
    int width,
    int height,
    const defect_component_repair_detail::ComponentBounds& bounds);

// 둘레 화소를 변위만큼 옮겨 비교한 평균 제곱 차입니다. 비교 가능한 화소가 절반에 못
// 미치면 후보에서 뺍니다.
[[nodiscard]] double context_ssd(
    const std::vector<int>& ring,
    Displacement displacement,
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    int width,
    int height) noexcept;

// 한 방향으로 160걸음까지 걸으며 처음 만나는 성한 화소를 냅니다.
[[nodiscard]] std::optional<ClearRgb> find_clear(
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    int width,
    int height,
    int x,
    int y,
    double dx,
    double dy,
    double sign) noexcept;

// 획 축과 그 수직 방향으로 양쪽 성한 화소를 찾아 거리 비례로 섞습니다. 한쪽만 찾으면
// 그 값을 그대로 씁니다.
[[nodiscard]] std::optional<Rgba32F> cross_fill(
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    int width,
    int height,
    int x,
    int y,
    double axis) noexcept;

}  // namespace negaflow::imaging::heal_brush_detail
