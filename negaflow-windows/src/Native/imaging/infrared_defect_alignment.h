#pragma once

#include "infrared_detection_types.h"

#include <cstdint>
#include <optional>
#include <span>

namespace negaflow::imaging::infrared_detail {

// 결함 자국 자체로 IR 과 가시 채널을 맞춥니다. 장면 질감이 아니라 어두운 자국을 보므로
// 질감이 없는 프레임에서도 답이 나옵니다. 자국이 모자라거나 최고점이 평균과 구분되지
// 않으면 답을 내지 않고 호출부가 질감 상관으로 넘어갑니다.
[[nodiscard]] std::optional<DefectAlignment> estimate_defect_alignment(
    std::span<const float> infrared,
    std::span<const float> red,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t search_radius);

}  // namespace negaflow::imaging::infrared_detail
