#pragma once

#include "defect_heal_brush_types.h"

#include <optional>
#include <vector>

namespace negaflow::imaging::heal_brush_detail {

// 정규 좌표 두 점 사이의 화소 거리입니다.
[[nodiscard]] double pixel_distance(
    DefectBrushPoint first,
    DefectBrushPoint second,
    int width,
    int height) noexcept;

// 획 하나를 길이 한계로 잘라 조각 목록을 냅니다. 자른 자리는 두 조각이 같은 점을 공유해
// 이음매가 생기지 않습니다.
[[nodiscard]] std::vector<BrushChunk> make_chunks(
    const DefectBrushStroke& stroke,
    int width,
    int height);

// 조각 하나를 고칠 ROI 입니다. 획 굵기와 이미지 크기로 후광(halo)을 붙여 주변 질감을
// 함께 봅니다.
[[nodiscard]] Rect repair_bounds(
    const BrushChunk& chunk,
    int width,
    int height) noexcept;

// 점과 선분 사이의 최단 거리입니다.
[[nodiscard]] double point_segment_distance(
    double x,
    double y,
    PixelPoint first,
    PixelPoint second) noexcept;

// 조각을 ROI 안의 0…1 마스크로 굽습니다.
[[nodiscard]] std::vector<float> rasterize_mask(
    const BrushChunk& chunk,
    Rect bounds,
    int image_width,
    int image_height);

// 조각의 주축 각도(도)입니다. 점이 모자라거나 방향성이 약하면 답하지 않습니다 - 그때는
// 성분 자체의 PCA 각도를 씁니다.
[[nodiscard]] std::optional<double> stroke_angle(
    const BrushChunk& chunk,
    int width,
    int height) noexcept;

}  // namespace negaflow::imaging::heal_brush_detail
