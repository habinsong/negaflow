#pragma once

#include "grain_mend_component_types.h"
#include "grain_mend_detector.h"
#include "grain_mend_scratch_response_map.h"

#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// 건물 모서리·격자 같은 **정상 구조선**을 스크래치 후보에서 뺍니다. 나란하거나
// 같은 선 위에 놓인 비슷한 길이의 선분이 여럿 모이면 그것은 결함이 아니라 피사체입니다.
[[nodiscard]] std::vector<std::uint8_t> structure_grid_drops(
    const std::vector<Component>& scratch,
    const DetectionImage& image,
    int structure_radius_reference);

// 끊긴 선분이 프레임 밖으로 이어지는 증거가 있으면 남기고, 없으면 뺍니다.
// macOS `DefectStructureLineFilter.continuationDrops(scratch:response:width:height:)` —
// 타일 로컬 응답 배열용 진입점입니다.
[[nodiscard]] std::vector<std::uint8_t> continuation_drops(
    const std::vector<Component>& scratch,
    const DetectionImage& image,
    const std::vector<float>& scratch_response);

// macOS `rejectingGlobalStructureLines` 가 쓰는 진입점입니다 — 타일 검출이 모아 둔 전역
// 저해상도 응답 맵(`DefectScratchResponseMap`)을 같은 판정에 넘깁니다.
[[nodiscard]] std::vector<std::uint8_t> continuation_drops(
    const std::vector<Component>& scratch,
    std::uint32_t width,
    const ScratchResponseMap& scratch_response);

}  // namespace negaflow::imaging::grain_mend_detail
