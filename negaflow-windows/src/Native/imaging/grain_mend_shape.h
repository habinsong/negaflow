#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// 연결요소 형태 측정(2차 모멘트 PCA). macOS `Chromabase/DefectRemoval/DefectShape.swift` 의
// 이식이며, 그쪽과 같이 **형태 게이트와 분류기가 함께 씁니다** — 두 벌을 두면 게이트가 보는
// 모양과 분류가 보는 모양이 갈립니다.
//
// length     주축 변 길이. 길이 L 의 균일 선분은 λ₁=(L²−1)/12 이므로 √(12λ₁)≈L 이고,
//            1화소 컴포넌트도 length 1 이 되도록 +1 합니다.
// thickness  화소수/길이 = 평균 두께.
// aspect     length/thickness.
// angle_degrees 주축 방향 0~180, 0 이 수평. 라벨맵이 y-down 이라 화면 각도와 같습니다.
struct PcaMetrics final {
    double length{0.0};
    double thickness{1.0};
    double aspect{0.0};
    double angle_degrees{0.0};
};

// 화소 인덱스는 `index % width`, `index / width` 로 좌표를 냅니다.
[[nodiscard]] PcaMetrics pca_metrics(
    const std::vector<std::size_t>& pixels,
    std::uint32_t width) noexcept;

[[nodiscard]] PcaMetrics pca_metrics(
    const std::vector<int>& pixels,
    int width) noexcept;

}  // namespace negaflow::imaging::grain_mend_detail
