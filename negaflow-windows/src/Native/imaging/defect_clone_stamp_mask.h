#pragma once

#include "defect_clone_stamp_types.h"

#include <cstdint>
#include <vector>

namespace negaflow::imaging::clone_stamp_detail {

// 도장 한 개의 반지름 방향 알파입니다. 경도(hardness)가 1 이라도 가장자리 한 화소는
// 반드시 흐려 계단이 남지 않게 합니다.
[[nodiscard]] float stamp_alpha(
    double normalized_distance,
    double hardness,
    double radius) noexcept;

// 마스크에 도장 하나를 찍습니다. 이미 찍힌 알파 위에 겹쳐 쌓습니다.
void paint_stamp(
    std::vector<float>& mask,
    std::uint32_t mask_width,
    std::uint32_t mask_height,
    std::uint32_t origin_x,
    std::uint32_t origin_y,
    PixelPoint center,
    double radius,
    double hardness) noexcept;

// 획을 따라 일정 간격으로 도장을 찍어 마스크를 굽습니다.
void rasterize_stroke(
    const std::vector<PixelPoint>& points,
    double spacing,
    double radius,
    double hardness,
    std::uint32_t origin_x,
    std::uint32_t origin_y,
    std::uint32_t width,
    std::uint32_t height,
    std::vector<float>& mask) noexcept;

}  // namespace negaflow::imaging::clone_stamp_detail
