#pragma once

#include "infrared_detection_types.h"

#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::imaging::infrared_detail {

// 형태학적 닫힘으로 만든 기준선 대비 광학 밀도입니다. 기준선보다 밝은 자리는 0 입니다 -
// 결함은 언제나 어두워지는 쪽이므로 반대 방향은 신호가 아닙니다.
[[nodiscard]] std::vector<float> optical_density(
    std::span<const float> plane,
    std::span<const float> baseline);

// 밀도 분포의 중앙값과 로버스트 표준편차로 결함 문턱을 정합니다. `sensitivity` 는 0…1 이며
// 클수록 문턱이 낮아집니다. 표본이 모자라면 기본값(문턱 무한대)을 내어 아무것도 잡지 않습니다.
[[nodiscard]] SignalStatistics signal_statistics(
    std::span<const float> density,
    const std::vector<std::uint8_t>& excluded,
    double sensitivity);

}  // namespace negaflow::imaging::infrared_detail
