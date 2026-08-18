#pragma once

#include "infrared_detection_types.h"

#include <cstdint>
#include <span>

namespace negaflow::imaging::infrared_detail {

// 블록 평균으로 평면을 줄입니다. factor 가 1 이하면 원본을 그대로 복사합니다.
[[nodiscard]] DownsampledPlane block_mean(
    std::span<const float> source,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t factor);

// 두 평면을 (dx, dy) 만큼 어긋나게 두고 잰 정규화 상관입니다. 표본이 모자라거나 분산이
// 없으면 -1 을 내어 후보에서 빠집니다.
[[nodiscard]] double correlation(
    std::span<const float> first,
    std::span<const float> second,
    std::uint32_t width,
    std::uint32_t height,
    std::int32_t dx,
    std::int32_t dy,
    std::uint32_t stride) noexcept;

}  // namespace negaflow::imaging::infrared_detail
