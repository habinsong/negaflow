#pragma once

#include "grain_mend_detector.h"

#include <cstddef>
#include <cstdint>

namespace negaflow::imaging::grain_mend_detail {

// 검출 해상도의 한 변. 긴 변이 상한을 넘으면 비율을 지키며 줄입니다.
[[nodiscard]] std::uint32_t scaled_dimension(
    std::uint32_t value,
    std::uint32_t long_side) noexcept;

// 채널에서 휘도와 최댓값 채널을 채웁니다. 최댓값 채널은 macOS DefectContrastField 의
// `bright` 와 같은 max(r,g,b) 이며 분류기의 극성 판정이 이것을 읽습니다.
void finish_detection_channels(DetectionImage& image);

[[nodiscard]] std::size_t checked_pixel_count(
    std::uint32_t width,
    std::uint32_t height);

}  // namespace negaflow::imaging::grain_mend_detail
