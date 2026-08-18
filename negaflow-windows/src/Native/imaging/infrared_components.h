#pragma once

#include "infrared_detection_types.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::infrared_detail {

// 후보 마스크를 8이웃 연결요소로 묶습니다. `minimum_area` 보다 작은 요소는 버립니다.
[[nodiscard]] std::vector<RawComponent> label_components(
    const std::vector<std::uint8_t>& mask,
    std::uint32_t width,
    std::uint32_t height,
    std::size_t minimum_area);

// 성분 안쪽 구멍을 메웁니다. 경계상자가 성분 면적에 비해 지나치게 크면(가늘고 긴 스크래치)
// 그대로 둡니다 - 메우면 없는 자리를 고치게 됩니다.
[[nodiscard]] RawComponent fill_component_holes(
    RawComponent component,
    std::uint32_t width);

}  // namespace negaflow::imaging::infrared_detail
