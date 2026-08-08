#pragma once

#include "negaflow/core/pixel.h"

#include <array>
#include <cstddef>

namespace negaflow::imaging {

inline constexpr char point_curve_algorithm_version[] =
    "chromabase-point-curve-v1";
inline constexpr std::size_t point_curve_lut_size = 64U;
inline constexpr std::size_t point_curve_max_points = 64U;

struct CurvePoint final {
    double x{0.0};
    double y{0.0};
};

// Fixed capacity keeps render-time work bounded and allocation-free. point_count is
// validated before any element is read.
struct PointCurve final {
    std::array<CurvePoint, point_curve_max_points> points{};
    std::size_t point_count{0U};
};

struct PointCurves final {
    PointCurve rgb{};
    PointCurve red{};
    PointCurve green{};
    PointCurve blue{};
};

struct PointCurveLuts final {
    std::array<float, point_curve_lut_size> red{};
    std::array<float, point_curve_lut_size> green{};
    std::array<float, point_curve_lut_size> blue{};
};

[[nodiscard]] bool has_point_curve_change(const PointCurves& curves) noexcept;
[[nodiscard]] bool valid_point_curves(const PointCurves& curves) noexcept;

// Builds the same separable 64-sample RGB/channel composition used by the macOS
// PointCurveStage. Samples are sRGB-encoded values in [0, 1].
[[nodiscard]] negaflow::core::KernelStatus build_point_curve_luts(
    const PointCurves& curves,
    PointCurveLuts& output) noexcept;

// Input/output RGB is extended-linear sRGB. Active curves are evaluated in the
// bounded sRGB-encoded cube domain; alpha is preserved. Input and output may alias.
[[nodiscard]] negaflow::core::KernelStatus apply_point_curves(
    negaflow::core::ConstImageView input,
    negaflow::core::ImageView output,
    const PointCurves& curves) noexcept;

}  // namespace negaflow::imaging
