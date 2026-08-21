#pragma once

#include "negaflow/core/pixel.h"

#include <cstdint>
#include <vector>

namespace negaflow::imaging {

// 축소본 한 장. 통계용 프록시를 만드는 유일한 경로다.
struct DownsampledProxy final {
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::vector<negaflow::core::Rgba32F> pixels;
};

// macOS 가 Core Image 로 렌더하는 프록시와 같은 방식으로 줄인다.
//
// GPU 축소는 밉맵 단계를 골라 그 단계에서 이중선형으로 뽑는다. 단계는
// floor(log2(원본폭 / 목표폭)) 이고, 각 단계는 2x2 평균의 반복이다. 남은 배율은
// 이중선형이 맡는다. 두 축 모두 원본폭/목표폭의 단일 배율을 쓰며, 정수 목표 높이에서
// 잘린 소수 나머지는 Core Image 좌표계와 같은 y-down 위쪽 절삭으로 반영한다.
//
// 한 번에 뭉개는 박스 평균과 다른 점은 **경계**다. 7.1 배를 한 박스로 평균하면 필름
// 베이스와 어두운 화면이 만나는 칸이 함께 뭉개져 베이스 근처 밝기가 무너진다. 실측에서
// 그 자리(p0.99)가 macOS 대비 8.77% 어긋났고, 이 경로로 바꾸자 0.64% 가 되었다.
// 나머지 여덟 지점도 함께 좋아졌다 — 한 지점을 위해 다른 지점을 내준 것이 아니다.
[[nodiscard]] DownsampledProxy downsample_for_statistics(
    negaflow::core::ConstImageView source,
    std::uint32_t target_width,
    std::uint32_t target_height);

}  // namespace negaflow::imaging
