#pragma once

#include "negaflow/imaging/defect_clone_stamp.h"

#include <cstdint>
#include <vector>

namespace negaflow::imaging::clone_stamp_detail {

// 복제 도장 전체가 공유하는 조율값 한 표입니다. 마스크·패치·검증이 같은 값을 봐야
// 하므로 파일마다 다시 적지 않습니다.

// 도장 사이 간격은 지름의 이만큼입니다. 촘촘할수록 획이 매끄럽지만 느려집니다.
inline constexpr double stamp_spacing_fraction = 0.25;

// 가장자리를 이만큼 화소로 흐려 계단을 없앱니다.
inline constexpr double antialias_pixels = 1.0;

// 이보다 짧은 선분은 길이가 0 인 것으로 봅니다.
inline constexpr double minimum_segment_length = 1.0e-6;

// 화소 좌표 한 점입니다.
struct PixelPoint final {
    double x{0.0};
    double y{0.0};
};

// 아직 이미지에 앉히지 않은 획 하나의 결과입니다. 16비트로 들고 있어야 겹친 획이 부동소수
// 누적으로 흘러가지 않습니다.
struct StoredPatch final {
    std::uint32_t x{0U};
    std::uint32_t y{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::vector<std::uint16_t> rgba16{};
};

}  // namespace negaflow::imaging::clone_stamp_detail
