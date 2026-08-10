#include "negaflow/imaging/point_curve.h"

#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/pointwise.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

namespace negaflow::imaging {
namespace {

constexpr double endpoint_epsilon = 1.0e-6;
constexpr double minimum_point_spacing = 1.0e-9;
constexpr double linear_curve_epsilon = 1.0e-4;
constexpr std::size_t normalized_point_capacity = point_curve_max_points + 2U;

using NormalizedPoints = std::array<CurvePoint, normalized_point_capacity>;
using CurveLut = std::array<float, point_curve_lut_size>;

struct NormalizedCurve final {
    NormalizedPoints points{};
    std::size_t point_count{0U};
};

[[nodiscard]] negaflow::core::KernelStatus validate_curve(
    const PointCurve& curve) noexcept {
    if (curve.point_count > point_curve_max_points) {
        return negaflow::core::KernelStatus::invalid_parameter;
    }

    std::array<double, point_curve_max_points> sorted_x{};
    for (std::size_t index = 0U; index < curve.point_count; ++index) {
        const CurvePoint point = curve.points[index];
        if (!std::isfinite(point.x) || !std::isfinite(point.y)) {
            return negaflow::core::KernelStatus::non_finite_parameter;
        }
        if (point.x < 0.0 || point.x > 1.0 || point.y < 0.0 || point.y > 1.0) {
            return negaflow::core::KernelStatus::invalid_parameter;
        }
        sorted_x[index] = point.x;
    }

    std::sort(sorted_x.begin(), sorted_x.begin() + curve.point_count);
    for (std::size_t index = 1U; index < curve.point_count; ++index) {
        if (sorted_x[index] - sorted_x[index - 1U] < minimum_point_spacing) {
            return negaflow::core::KernelStatus::invalid_parameter;
        }
    }
    return negaflow::core::KernelStatus::ok;
}

[[nodiscard]] negaflow::core::KernelStatus validate_curves(
    const PointCurves& curves) noexcept {
    for (const PointCurve* const curve : {
             &curves.rgb,
             &curves.red,
             &curves.green,
             &curves.blue,
         }) {
        const negaflow::core::KernelStatus status = validate_curve(*curve);
        if (status != negaflow::core::KernelStatus::ok) {
            return status;
        }
    }
    return negaflow::core::KernelStatus::ok;
}

[[nodiscard]] bool curve_is_linear(const PointCurve& curve) noexcept {
    if (curve.point_count < 2U || curve.point_count > point_curve_max_points) {
        return true;
    }
    for (std::size_t index = 0U; index < curve.point_count; ++index) {
        if (std::abs(curve.points[index].y - curve.points[index].x) >=
            linear_curve_epsilon) {
            return false;
        }
    }
    return true;
}

[[nodiscard]] NormalizedCurve normalize_curve(const PointCurve& curve) noexcept {
    NormalizedCurve normalized{};
    if (curve.point_count == 0U) {
        normalized.points[0U] = {0.0, 0.0};
        normalized.points[1U] = {1.0, 1.0};
        normalized.point_count = 2U;
        return normalized;
    }

    std::copy_n(
        curve.points.begin(),
        curve.point_count,
        normalized.points.begin());
    std::sort(
        normalized.points.begin(),
        normalized.points.begin() + curve.point_count,
        [](const CurvePoint left, const CurvePoint right) noexcept {
            return left.x < right.x;
        });
    normalized.point_count = curve.point_count;

    if (normalized.points[0U].x > endpoint_epsilon) {
        std::move_backward(
            normalized.points.begin(),
            normalized.points.begin() + normalized.point_count,
            normalized.points.begin() + normalized.point_count + 1U);
        normalized.points[0U] = {0.0, normalized.points[1U].y};
        ++normalized.point_count;
    }
    if (normalized.points[normalized.point_count - 1U].x <
        1.0 - endpoint_epsilon) {
        normalized.points[normalized.point_count] = {
            1.0,
            normalized.points[normalized.point_count - 1U].y,
        };
        ++normalized.point_count;
    }
    return normalized;
}

[[nodiscard]] double evaluate_curve(
    const double x,
    const NormalizedCurve& curve,
    const std::array<double, normalized_point_capacity>& tangents) noexcept {
    if (x <= curve.points[0U].x) {
        return curve.points[0U].y;
    }
    if (x >= curve.points[curve.point_count - 1U].x) {
        return curve.points[curve.point_count - 1U].y;
    }

    std::size_t interval = 0U;
    while (interval + 1U < curve.point_count &&
           x > curve.points[interval + 1U].x) {
        ++interval;
    }
    const double width = std::max(
        curve.points[interval + 1U].x - curve.points[interval].x,
        minimum_point_spacing);
    const double t = (x - curve.points[interval].x) / width;
    const double t2 = t * t;
    const double t3 = t2 * t;
    const double h00 = (2.0 * t3) - (3.0 * t2) + 1.0;
    const double h10 = t3 - (2.0 * t2) + t;
    const double h01 = (-2.0 * t3) + (3.0 * t2);
    const double h11 = t3 - t2;
    return (h00 * curve.points[interval].y) +
           (h10 * width * tangents[interval]) +
           (h01 * curve.points[interval + 1U].y) +
           (h11 * width * tangents[interval + 1U]);
}

[[nodiscard]] CurveLut build_curve_lut(const PointCurve& source) noexcept {
    const NormalizedCurve curve = normalize_curve(source);
    std::array<double, normalized_point_capacity> deltas{};
    std::array<double, normalized_point_capacity> tangents{};

    for (std::size_t index = 0U; index + 1U < curve.point_count; ++index) {
        const double width = std::max(
            curve.points[index + 1U].x - curve.points[index].x,
            minimum_point_spacing);
        deltas[index] =
            (curve.points[index + 1U].y - curve.points[index].y) / width;
    }
    tangents[0U] = deltas[0U];
    tangents[curve.point_count - 1U] = deltas[curve.point_count - 2U];
    for (std::size_t index = 1U; index + 1U < curve.point_count; ++index) {
        tangents[index] = (deltas[index - 1U] + deltas[index]) * 0.5;
    }
    for (std::size_t index = 0U; index + 1U < curve.point_count; ++index) {
        if (std::abs(deltas[index]) < 1.0e-12) {
            tangents[index] = 0.0;
            tangents[index + 1U] = 0.0;
            continue;
        }
        const double a = tangents[index] / deltas[index];
        const double b = tangents[index + 1U] / deltas[index];
        const double squared_magnitude = (a * a) + (b * b);
        if (squared_magnitude > 9.0) {
            const double scale = 3.0 / std::sqrt(squared_magnitude);
            tangents[index] = scale * a * deltas[index];
            tangents[index + 1U] = scale * b * deltas[index];
        }
    }

    CurveLut lut{};
    for (std::size_t index = 0U; index < lut.size(); ++index) {
        const double x = static_cast<double>(index) /
                         static_cast<double>(lut.size() - 1U);
        lut[index] = static_cast<float>(std::clamp(
            evaluate_curve(x, curve, tangents),
            0.0,
            1.0));
    }
    return lut;
}

[[nodiscard]] CurveLut compose_luts(
    const CurveLut& inner,
    const CurveLut& outer) noexcept {
    CurveLut composed{};
    for (std::size_t index = 0U; index < composed.size(); ++index) {
        const float scaled = inner[index] *
                             static_cast<float>(outer.size() - 1U);
        const auto rounded = static_cast<std::size_t>(std::round(scaled));
        composed[index] = outer[std::min(rounded, outer.size() - 1U)];
    }
    return composed;
}

[[nodiscard]] float sample_lut(
    const CurveLut& lut,
    const float encoded) noexcept {
    const float bounded = std::clamp(encoded, 0.0F, 1.0F);
    const float position = bounded * static_cast<float>(lut.size() - 1U);
    const auto lower = static_cast<std::size_t>(position);
    const std::size_t upper = std::min(lower + 1U, lut.size() - 1U);
    const float fraction = position - static_cast<float>(lower);
    return lut[lower] + ((lut[upper] - lut[lower]) * fraction);
}

[[nodiscard]] float apply_lut_component(
    const float linear,
    const CurveLut& lut) noexcept {
    const float encoded = negaflow::color::linear_to_srgb_encoded(linear);
    const float mapped = sample_lut(lut, encoded);
    return negaflow::color::srgb_encoded_to_linear(mapped);
}

}  // namespace

bool has_point_curve_change(const PointCurves& curves) noexcept {
    return !curve_is_linear(curves.rgb) || !curve_is_linear(curves.red) ||
           !curve_is_linear(curves.green) || !curve_is_linear(curves.blue);
}

bool valid_point_curves(const PointCurves& curves) noexcept {
    return validate_curves(curves) == negaflow::core::KernelStatus::ok;
}

negaflow::core::KernelStatus build_point_curve_luts(
    const PointCurves& curves,
    PointCurveLuts& output) noexcept {
    const negaflow::core::KernelStatus validation_status = validate_curves(curves);
    if (validation_status != negaflow::core::KernelStatus::ok) {
        return validation_status;
    }

    const CurveLut rgb = build_curve_lut(curves.rgb);
    output.red = compose_luts(rgb, build_curve_lut(curves.red));
    output.green = compose_luts(rgb, build_curve_lut(curves.green));
    output.blue = compose_luts(rgb, build_curve_lut(curves.blue));
    return negaflow::core::KernelStatus::ok;
}

negaflow::core::KernelStatus apply_point_curves(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output,
    const PointCurves& curves) noexcept {
    const negaflow::core::KernelStatus validation_status = validate_curves(curves);
    if (validation_status != negaflow::core::KernelStatus::ok) {
        return validation_status;
    }
    const negaflow::core::KernelStatus compatibility_status =
        negaflow::core::validate_compatible_views(input, output);
    if (compatibility_status != negaflow::core::KernelStatus::ok) {
        return compatibility_status;
    }
    const negaflow::core::KernelStatus input_status =
        negaflow::core::validate_finite_pixels(input);
    if (input_status != negaflow::core::KernelStatus::ok) {
        return input_status;
    }

    if (!has_point_curve_change(curves)) {
        negaflow::core::copy_validated_rows(input, output);
        return negaflow::core::KernelStatus::ok;
    }

    PointCurveLuts luts{};
    const negaflow::core::KernelStatus lut_status =
        build_point_curve_luts(curves, luts);
    if (lut_status != negaflow::core::KernelStatus::ok) {
        return lut_status;
    }

    return negaflow::core::transform_validated_pointwise(
        input,
        output,
        [&luts](const negaflow::core::Rgba32F source) noexcept {
            return negaflow::core::Rgba32F{
                apply_lut_component(source.red, luts.red),
                apply_lut_component(source.green, luts.green),
                apply_lut_component(source.blue, luts.blue),
                source.alpha,
            };
        });
}

}  // namespace negaflow::imaging
