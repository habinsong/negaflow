#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/analysis_region.h"

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

// 크롭 사각형(`rect`, 원본 화소 y-down)만 줄인 통계 프록시입니다 — macOS 의 "측정 영역으로
// 자른 뒤 축소" 자리입니다. 단계 선택과 표본 위치는 위 함수가 사각형을 원본으로 보았을 때와
// 같습니다.
//
// 밉맵은 **전체 화상**에서 짓고 사각형 좌표로 이중선형 표본을 뽑습니다. 화상이 GPU 에 머물러
// 있으면 호스트 사본이 낡아 부분 뷰로는 읽을 수 없고, 상주 밉맵(전체 화상 기준)은 그대로
// 쓸 수 있기 때문입니다. GPU 밉맵을 못 쓰는 갈래(축소 단계 0, GPU 실패)에서는 호스트에서
// 읽기 전에 상주 화상을 내립니다.
[[nodiscard]] DownsampledProxy downsample_region_for_statistics(
    negaflow::core::ConstImageView source,
    const AnalysisPixelRect& rect,
    std::uint32_t target_width,
    std::uint32_t target_height);

}  // namespace negaflow::imaging
