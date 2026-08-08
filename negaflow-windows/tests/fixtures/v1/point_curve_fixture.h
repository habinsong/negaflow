#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/point_curve.h"

#include <array>
#include <cstddef>
#include <string_view>

namespace negaflow::fixtures {

inline constexpr std::string_view point_curve_fixture_id =
    "point-curve-scalar-v1";
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

inline constexpr std::array<negaflow::core::Rgba32F, 6> point_curve_expected{{
    {0.00154798757F, 0.383781493F, 1.0F, 0.25F},
    {0.00154798757F, 0.0F, 0.0F, 1.0F},
    {0.00360073522F, 0.480289012F, 1.0F, 0.5F},
    {0.432238609F, 0.383781493F, 0.292799532F, 1.0F},
    {0.662727177F, 0.44687444F, 0.0646803454F, 1.0F},
    {0.955104649F, 0.934331179F, 0.72345221F, 0.75F},
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
        {1U, 0.0368741862F, 0.0158730168F, 0.0117787439F},
        {7U, 0.08800545F, 0.06349207F, 0.0458527133F},
        {15U, 0.191693321F, 0.158730164F, 0.111132443F},
        {16U, 0.226396725F, 0.1904762F, 0.132959008F},
        {31U, 0.7412828F, 0.714285731F, 0.651819468F},
        {32U, 0.754640043F, 0.730158746F, 0.671273F},
        {47U, 0.8600583F, 0.857142866F, 0.8279343F},
        {48U, 0.8731996F, 0.8730159F, 0.847437859F},
        {62U, 0.966398F, 0.984127F, 0.9813963F},
        {63U, 0.98F, 1.0F, 1.0F},
    }};

}  // namespace negaflow::fixtures
