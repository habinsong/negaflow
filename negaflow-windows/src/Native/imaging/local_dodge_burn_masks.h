#pragma once

#include "local_dodge_burn_types.h"

#include <vector>

namespace negaflow::imaging::local_dodge_burn_detail {

// 두 점을 잇는 선분을 마스크에 굵기 `radius` 로 굽습니다.
void rasterize_segment(
    std::vector<float>& mask,
    const WorkingImage& image,
    PixelPoint first,
    PixelPoint second,
    float radius) noexcept;

[[nodiscard]] MaskResult brush_mask(
    const LocalDodgeBurnMask& source,
    const WorkingImage& image);

[[nodiscard]] MaskResult radial_mask(
    const LocalDodgeBurnMask& source,
    const WorkingImage& image);

[[nodiscard]] MaskResult linear_mask(
    const LocalDodgeBurnMask& source,
    const WorkingImage& image);

[[nodiscard]] bool point_inside_polygon(
    float sample_x,
    float sample_y,
    const std::vector<PixelPoint>& points) noexcept;

[[nodiscard]] MaskResult polygon_mask(
    const LocalDodgeBurnMask& source,
    const WorkingImage& image);

// 마스크 종류에 맞는 굽기를 고릅니다.
[[nodiscard]] MaskResult make_mask(
    const LocalDodgeBurnMask& mask,
    const WorkingImage& image);

// 마스크에 0 보다 큰 무게가 하나라도 있는가. 없으면 그 조정은 건너뜁니다.
[[nodiscard]] bool mask_has_weight(const std::vector<float>& mask) noexcept;

}  // namespace negaflow::imaging::local_dodge_burn_detail
