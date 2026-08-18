#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/defect_heal_brush.h"

#include <cstddef>
#include <vector>

namespace negaflow::imaging::heal_brush_detail {

using negaflow::core::Rgba32F;

// 브러시 전체가 공유하는 조율값 한 표입니다. 획 자르기·마스크·검증이 같은 한계를 봐야
// 하므로 파일마다 다시 적지 않습니다.
namespace tuning {

inline constexpr double pi = 3.14159265358979323846;

// 이보다 짧은 선분은 길이가 0 인 것으로 봅니다.
inline constexpr double minimum_segment_length = 1.0e-6;

inline constexpr std::size_t maximum_strokes = 100'000U;
inline constexpr std::size_t maximum_points = 5'000'000U;

}  // namespace tuning

// 화소 좌표 한 점입니다. 정규 좌표인 DefectBrushPoint 와 구분하려고 따로 둡니다.
struct PixelPoint final {
    double x{0.0};
    double y{0.0};
};

// 화소 단위 반열린 사각형입니다.
struct Rect final {
    int left{0};
    int top{0};
    int right{0};
    int bottom{0};
};

// 한 번에 고칠 만큼으로 자른 획 조각입니다. 긴 획을 통째로 고치면 ROI 가 이미지만큼
// 커지므로 길이로 잘라 둡니다.
struct BrushChunk final {
    std::vector<DefectBrushPoint> points{};
    double thickness{0.0};
};

// 아직 이미지에 앉히지 않은, 조각 하나의 고친 결과입니다.
struct StoredPatch final {
    int left{0};
    int top{0};
    int width{0};
    int height{0};
    std::vector<Rgba32F> pixels{};
};

// 성한 화소를 어디서 끌어올지 나타내는 화소 변위입니다.
struct Displacement final {
    int dx{0};
    int dy{0};
};

// 손상되지 않은 자리에서 읽은 색과 거기까지의 걸음 수입니다.
struct ClearRgb final {
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
    int distance{0};
};

}  // namespace negaflow::imaging::heal_brush_detail
