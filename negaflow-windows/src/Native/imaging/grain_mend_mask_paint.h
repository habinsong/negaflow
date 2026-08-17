#pragma once

#include "grain_mend_component_types.h"
#include "grain_mend_detector.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// 채택한 컴포넌트를 마스크에 칠합니다. `radius` 는 화소를 얼마나 부풀릴지이며, 먼지는 0,
// 스크래치는 1 입니다 — 가는 선은 한 화소 넓혀야 복원이 가장자리를 남기지 않습니다.
void paint_component(
    const Component& component,
    int radius,
    const DetectionImage& image,
    std::vector<std::uint8_t>& mask) noexcept;

// 먼지 안쪽에 남은 구멍을 메웁니다. 메우지 않으면 복원이 도넛을 남깁니다.
void fill_interior_holes(
    const Component& component,
    const DetectionImage& image,
    std::size_t maximum_dust_area,
    std::vector<std::uint8_t>& mask);

}  // namespace negaflow::imaging::grain_mend_detail
