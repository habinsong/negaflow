#pragma once

#include "grain_mend_classifier.h"
#include "grain_mend_component_types.h"
#include "grain_mend_detector.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// 게이트를 통과한 컴포넌트를 분류해 담습니다. 채택 여부는 이미 끝났으므로 여기서는
// 메타데이터만 붙습니다 — macOS `DefectClassifier.classify` 가 서는 자리와 같습니다.
void collect_classified(
    const std::vector<Component>& dust,
    const std::vector<std::uint8_t>& drop_dust,
    const std::vector<Component>& scratch,
    const std::vector<std::uint8_t>& drop_scratch,
    const DetectionImage& image,
    const CandidateMaps* candidates,
    std::size_t maximum_dust_area,
    std::vector<ClassifiedComponent>& result);

}  // namespace negaflow::imaging::grain_mend_detail
