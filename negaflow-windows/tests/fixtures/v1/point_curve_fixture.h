#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/point_curve.h"

#include <array>
#include <cstddef>
#include <string_view>

namespace negaflow::fixtures {

inline constexpr std::string_view point_curve_fixture_id =
    "point-curve-scalar-v3";
inline constexpr float point_curve_absolute_tolerance = 1.0e-5F;
inline constexpr float point_curve_relative_tolerance = 1.0e-5F;

template <std::size_t PointCount>
[[nodiscard]] constexpr negaflow::imaging::PointCurve make_point_curve(
    const std::array<negaflow::imaging::CurvePoint, PointCount>& points) noexcept {
    static_assert(PointCount <= negaflow::imaging::point_curve_max_points);
    negaflow::imaging::PointCurve curve{};
    for (std::size_t index = 0U; index < PointCount; ++index) {
        curve.points[index] = points[index];
    }
    curve.point_count = PointCount;
    return curve;
}

// Repository-owned synthetic fixture calculated independently from the macOS
// CurveLUT/PointCurveStage formulas. This is not yet an actual Core Image render golden.
inline constexpr negaflow::imaging::PointCurves point_curve_parameters{
    make_point_curve(std::array{
        negaflow::imaging::CurvePoint{0.0, 0.0},
        negaflow::imaging::CurvePoint{0.25, 0.18},
        negaflow::imaging::CurvePoint{0.5, 0.72},
        negaflow::imaging::CurvePoint{0.75, 0.86},
        negaflow::imaging::CurvePoint{1.0, 1.0},
    }),
    make_point_curve(std::array{
        negaflow::imaging::CurvePoint{0.0, 0.02},
        negaflow::imaging::CurvePoint{0.5, 0.55},
        negaflow::imaging::CurvePoint{1.0, 0.98},
    }),
    {},
    make_point_curve(std::array{
        negaflow::imaging::CurvePoint{0.0, 0.0},
        negaflow::imaging::CurvePoint{0.4, 0.3},
        negaflow::imaging::CurvePoint{1.0, 1.0},
    }),
};

inline constexpr std::array<negaflow::core::Rgba32F, 6> point_curve_input{{
    {-0.1F, 0.18F, 1.1F, 0.25F},
    {0.0F, 0.0F, 0.0F, 1.0F},
    {0.0031308F, 0.21404114F, 1.0F, 0.5F},
    {0.18F, 0.18F, 0.18F, 1.0F},
    {0.4F, 0.2F, 0.1F, 1.0F},
    {1.2F, 0.9F, 0.6F, 0.75F},
}};

// 채널 커브 합성은 inner 출력 위치에서 outer 를 선형 보간합니다(macOS `PointCurveStage.compose`).
// 가장 가까운 칸으로 반올림하던 v1 값은 같은 포팅에 반올림 합성을 넣으면 1e-7 안쪽으로
// 재현됩니다 — 바뀐 것은 합성식뿐입니다.
// v3: 표가 잘라 낸 [0,1] 밖 몫을 다시 더합니다(첫 줄의 −0.1·1.1, 마지막 줄의 1.2). 범위 안 값은
// v2 그대로입니다.
inline constexpr std::array<negaflow::core::Rgba32F, 6> point_curve_expected{{
    {-0.0984520124F, 0.386407048F, 1.1F, 0.25F},
    {0.00154798757F, 0.0F, 0.0F, 1.0F},
    {0.00364688342F, 0.476284325F, 1.0F, 0.5F},
    {0.434666961F, 0.386407048F, 0.295495391F, 1.0F},
    {0.666152298F, 0.442762494F, 0.0674440563F, 1.0F},
    {1.155104649F, 0.943243206F, 0.718479037F, 0.75F},
}};

struct PointCurveLutFixtureSample final {
    std::size_t index;
    float red;
    float green;
    float blue;
};

inline constexpr std::array<PointCurveLutFixtureSample, 11>
    point_curve_lut_samples{{
        {0U, 0.02F, 0.0F, 0.0F},
        {1U, 0.0314269997F, 0.0107490188F, 0.00797642581F},
        {7U, 0.0845055804F, 0.0602469184F, 0.0435672589F},
        {15U, 0.197076619F, 0.163654029F, 0.114505179F},
        {16U, 0.221344486F, 0.185853854F, 0.129769146F},
        {31U, 0.736501217F, 0.708633959F, 0.644919515F},
        {32U, 0.75483954F, 0.730396926F, 0.671565831F},
        {47U, 0.860625029F, 0.857827365F, 0.828775406F},
        {48U, 0.867943108F, 0.866666734F, 0.839636505F},
        {62U, 0.972382843F, 0.9911111F, 0.989581883F},
        {63U, 0.98F, 1.0F, 1.0F},
    }};

}  // namespace negaflow::fixtures
