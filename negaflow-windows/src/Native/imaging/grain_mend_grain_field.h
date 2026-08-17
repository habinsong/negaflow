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
// `small_maximum` 은 macOS `grainFieldDrops(smallMax:)` 입니다 — 전체 프레임 자동은
// `grainFieldSmallMax`(12), 부분 ROI(가이드)는 `constrainedRegionGrainFieldSmallMax`(4)
// 를 씁니다. 가이드가 확장 스케일의 trusted 경로로 받은 고대비 입자도 1~2px 로 밀집하면
// 예외 없이 버리고, 3x3 이상 실제 먼지는 크기 범위 밖이라 보존됩니다.
void mark_grain_field_drops(
    const std::vector<Component>& dust,
    const std::vector<Component>& scratch,
    std::uint32_t image_width,
    std::vector<std::uint8_t>& drop_dust,
    std::vector<std::uint8_t>& drop_scratch,
    std::size_t small_maximum = tuning::grain_field_small_component_maximum);

}  // namespace negaflow::imaging::grain_mend_detail
