#pragma once

#include "grain_mend_component_types.h"
#include "grain_mend_detector.h"

#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// 두꺼운(뭉친) 먼지 컴포넌트가 덮은 화소 지도. 고립 판정의 배경입니다.
[[nodiscard]] std::vector<std::uint8_t> make_chunky_map(
    const std::vector<Component>& components,
    std::size_t count);

// 주변 링에 구조가 거의 없으면 고립된 결함입니다. 링이 붐비면 피사체의 일부입니다.
[[nodiscard]] bool is_isolated(
    const Component& component,
    const std::vector<std::uint8_t>& chunky,
    const DetectionImage& image) noexcept;

// 작은 컴포넌트가 한 자리에 빽빽하면 그것은 결함이 아니라 그레인입니다. 그런 밭에
// 놓인 후보를 먼지·스크래치 양쪽에서 뺍니다.
void mark_grain_field_drops(
    const std::vector<Component>& dust,
    const std::vector<Component>& scratch,
    std::uint32_t image_width,
    std::vector<std::uint8_t>& drop_dust,
    std::vector<std::uint8_t>& drop_scratch);

}  // namespace negaflow::imaging::grain_mend_detail
