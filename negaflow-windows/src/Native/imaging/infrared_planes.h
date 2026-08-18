#pragma once

#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::imaging::infrared_detail {

// 표본을 정렬해 분위값을 냅니다. 입력 벡터는 제자리에서 정렬됩니다.
[[nodiscard]] float quantile(std::vector<float>& values, double q);

// 제외 마스크를 뺀 화소에서 분위값을 냅니다. 큰 평면은 성글게 훑습니다.
[[nodiscard]] float percentile(
    std::span<const float> values,
    const std::vector<std::uint8_t>& excluded,
    double q);

// 평면을 (dx, dy) 만큼 옮깁니다. 원본 밖에서 끌어온 자리는 `excluded` 에 표시해 이후 통계가
// 그 화소를 세지 않게 합니다.
[[nodiscard]] std::vector<float> shift_plane(
    std::span<const float> source,
    std::uint32_t width,
    std::uint32_t height,
    std::int32_t dx,
    std::int32_t dy,
    std::vector<std::uint8_t>& excluded);

// 테두리에서 이어진 어두운 영역(홀더 그림자·빈 베드)을 제외 표시합니다. `rim` 만큼 안쪽으로
// 더 넓혀 경계 화소가 결함으로 잡히지 않게 합니다.
void exclude_border_dark(
    std::span<const float> plane,
    std::uint32_t width,
    std::uint32_t height,
    float threshold,
    std::uint32_t rim,
    std::vector<std::uint8_t>& excluded);

}  // namespace negaflow::imaging::infrared_detail
