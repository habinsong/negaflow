#pragma once

#include "negaflow/imaging/infrared_defect_detector.h"

#include <cstdint>
#include <span>

namespace negaflow::imaging::infrared_detail {

// IR 평면을 가시(적색) 평면에 맞춥니다. 먼저 결함 자국으로 맞춰 보고, 답이 없으면 축소한
// 두 평면의 질감 상관으로 거칠게 찾은 뒤 원본 해상도에서 다듬습니다. 어느 쪽으로 답했는지는
// 반환한 진단의 status 가 말합니다 - 호출부는 그 값으로 정렬을 믿을지 정합니다.
[[nodiscard]] InfraredAlignmentDiagnostics estimate_alignment(
    std::span<const float> infrared,
    std::span<const float> red,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t search_radius);

}  // namespace negaflow::imaging::infrared_detail
