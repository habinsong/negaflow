#include "negaflow/core/build_info.h"
#include "negaflow/core/negative_inversion.h"
#include "negaflow/imaging/color_grading.h"
#include "negaflow/imaging/color_mixer.h"
#include "negaflow/imaging/point_curve.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "color_grading_fixture.h"
#include "color_mixer_fixture.h"
#include "point_curve_fixture.h"
#include "scalar_foundation_fixture.h"
#include "tone_mapping_fixture.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace {

struct PixelErrorMetrics final {
    double maximum_absolute_error{0.0};
    double maximum_relative_error{0.0};
    std::size_t finite_output_count{0U};
    std::size_t failure_count{0U};
};

template <std::size_t PixelCount>
[[nodiscard]] PixelErrorMetrics compare_pixels(
    const std::vector<negaflow::core::Rgba32F>& actual_pixels,
    const std::array<negaflow::core::Rgba32F, PixelCount>& expected_pixels,
    const float absolute_tolerance,
    const float relative_tolerance) noexcept {
    PixelErrorMetrics metrics{};
    if (actual_pixels.size() != expected_pixels.size()) {
        ++metrics.failure_count;
        return metrics;
    }

    for (std::size_t pixel_index = 0U;
         pixel_index < actual_pixels.size();
         ++pixel_index) {
        const auto& actual_pixel = actual_pixels[pixel_index];
        const auto& expected_pixel = expected_pixels[pixel_index];
        const std::array<float, 4> actual{
            actual_pixel.red,
            actual_pixel.green,
            actual_pixel.blue,
            actual_pixel.alpha,
        };
        const std::array<float, 4> expected{
            expected_pixel.red,
            expected_pixel.green,
            expected_pixel.blue,
            expected_pixel.alpha,
        };
        for (std::size_t channel = 0U; channel < actual.size(); ++channel) {
            if (!std::isfinite(actual[channel])) {
                ++metrics.failure_count;
                continue;
            }
            ++metrics.finite_output_count;
            const double actual_value = static_cast<double>(actual[channel]);
            const double expected_value = static_cast<double>(expected[channel]);
            const double absolute_error =
                std::abs(actual_value - expected_value);
            const double relative_scale =
                std::max(std::abs(actual_value), std::abs(expected_value));
            const double relative_error = relative_scale == 0.0
                ? 0.0
                : absolute_error / relative_scale;
            metrics.maximum_absolute_error = std::max(
                metrics.maximum_absolute_error,
                absolute_error);
            metrics.maximum_relative_error = std::max(
                metrics.maximum_relative_error,
                relative_error);
            const double allowed_error =
                static_cast<double>(absolute_tolerance) +
                (static_cast<double>(relative_tolerance) * relative_scale);
            if (absolute_error > allowed_error) {
                ++metrics.failure_count;
            }
        }
    }
    return metrics;
}

}  // namespace

int main() {
    constexpr float dmin = negaflow::fixtures::color_negative_dmin;
    constexpr float dmax = negaflow::fixtures::color_negative_dmax_normalized;
    const negaflow::core::NegativeInversionParameters parameters{
        {dmin, dmin, dmin},
        {dmax, dmax, dmax},
    };

    double maximum_absolute_error = 0.0;
    double maximum_relative_error = 0.0;
    std::size_t finite_output_count = 0U;
    std::size_t negative_failure_count = 0U;

    for (const negaflow::fixtures::NegativeInversionCase& fixture_case :
         negaflow::fixtures::color_negative_cases) {
        const float transmission = dmin * std::pow(10.0F, -fixture_case.density);
        const negaflow::core::Rgba32F source{
            transmission,
            transmission,
            transmission,
            1.0F,
        };
        negaflow::core::Rgba32F output{};
        const negaflow::core::KernelStatus kernel_status =
            negaflow::core::apply_negative_inversion(
                {&source, 1U, 1U, 1U, 1U},
                {&output, 1U, 1U, 1U, 1U},
                parameters,
                negaflow::core::color_negative_print_response());
        if (kernel_status != negaflow::core::KernelStatus::ok ||
            !std::isfinite(output.red)) {
            ++negative_failure_count;
            continue;
        }

        ++finite_output_count;
        const double actual = static_cast<double>(output.red);
        const double absolute_error = std::abs(actual - fixture_case.expected);
        const double relative_scale = std::max(std::abs(actual), std::abs(fixture_case.expected));
        const double relative_error =
            relative_scale == 0.0 ? 0.0 : absolute_error / relative_scale;
        maximum_absolute_error = std::max(maximum_absolute_error, absolute_error);
        maximum_relative_error = std::max(maximum_relative_error, relative_error);

        const double allowed_error =
            static_cast<double>(negaflow::fixtures::negative_inversion_absolute_tolerance) +
            (static_cast<double>(negaflow::fixtures::negative_inversion_relative_tolerance) *
             relative_scale);
        if (absolute_error > allowed_error) {
            ++negative_failure_count;
        }
    }

    negaflow::imaging::WorkingImage tone_image{};
    tone_image.width = 3U;
    tone_image.height = 2U;
    tone_image.stride_pixels = 3U;
    tone_image.pixels.assign(
        negaflow::fixtures::tone_mapping_input.begin(),
        negaflow::fixtures::tone_mapping_input.end());
    const auto adjusted = negaflow::imaging::apply_working_tone_adjustments(
        std::move(tone_image),
        negaflow::fixtures::tone_mapping_parameters);

    PixelErrorMetrics tone_metrics{};
    if (adjusted.status != negaflow::imaging::WorkingToneAdjustStatus::ok ||
        adjusted.info.color_mixer_applied ||
        adjusted.info.color_grading_applied) {
        ++tone_metrics.failure_count;
    } else {
        tone_metrics = compare_pixels(
            adjusted.image.pixels,
            negaflow::fixtures::tone_mapping_expected,
            negaflow::fixtures::tone_mapping_absolute_tolerance,
            negaflow::fixtures::tone_mapping_relative_tolerance);
    }

    negaflow::imaging::WorkingImage point_curve_image{};
    point_curve_image.width = 3U;
    point_curve_image.height = 2U;
    point_curve_image.stride_pixels = 3U;
    point_curve_image.pixels.assign(
        negaflow::fixtures::point_curve_input.begin(),
        negaflow::fixtures::point_curve_input.end());
    negaflow::imaging::WorkingToneAdjustParameters point_curve_parameters{};
    point_curve_parameters.point_curves =
        negaflow::fixtures::point_curve_parameters;
    const auto point_curve_adjusted =
        negaflow::imaging::apply_working_tone_adjustments(
            std::move(point_curve_image),
            point_curve_parameters);

    PixelErrorMetrics point_curve_metrics{};
    if (point_curve_adjusted.status !=
            negaflow::imaging::WorkingToneAdjustStatus::ok ||
        !point_curve_adjusted.info.point_curve_applied ||
        point_curve_adjusted.info.color_mixer_applied ||
        point_curve_adjusted.info.color_grading_applied) {
        ++point_curve_metrics.failure_count;
    } else {
        point_curve_metrics = compare_pixels(
            point_curve_adjusted.image.pixels,
            negaflow::fixtures::point_curve_expected,
            negaflow::fixtures::point_curve_absolute_tolerance,
            negaflow::fixtures::point_curve_relative_tolerance);
    }

    negaflow::imaging::WorkingImage color_mixer_image{};
    color_mixer_image.width = 4U;
    color_mixer_image.height = 3U;
    color_mixer_image.stride_pixels = 4U;
    color_mixer_image.pixels.assign(
        negaflow::fixtures::color_mixer_input.begin(),
        negaflow::fixtures::color_mixer_input.end());
    negaflow::imaging::WorkingToneAdjustParameters color_mixer_parameters{};
    color_mixer_parameters.color_mixer =
        negaflow::fixtures::color_mixer_parameters;
    const auto color_mixer_adjusted =
        negaflow::imaging::apply_working_tone_adjustments(
            std::move(color_mixer_image),
            color_mixer_parameters);

    PixelErrorMetrics color_mixer_metrics{};
    if (color_mixer_adjusted.status !=
            negaflow::imaging::WorkingToneAdjustStatus::ok ||
        !color_mixer_adjusted.info.color_mixer_applied ||
        color_mixer_adjusted.info.point_curve_applied ||
        color_mixer_adjusted.info.color_grading_applied) {
        ++color_mixer_metrics.failure_count;
    } else {
        color_mixer_metrics = compare_pixels(
            color_mixer_adjusted.image.pixels,
            negaflow::fixtures::color_mixer_expected,
            negaflow::fixtures::color_mixer_absolute_tolerance,
            negaflow::fixtures::color_mixer_relative_tolerance);
    }

    negaflow::imaging::WorkingImage color_grading_image{};
    color_grading_image.width = 4U;
    color_grading_image.height = 3U;
    color_grading_image.stride_pixels = 4U;
    color_grading_image.pixels.assign(
        negaflow::fixtures::color_grading_input.begin(),
        negaflow::fixtures::color_grading_input.end());
    negaflow::imaging::WorkingToneAdjustParameters color_grading_parameters{};
    color_grading_parameters.color_grading =
        negaflow::fixtures::color_grading_parameters;
    const auto color_grading_adjusted =
        negaflow::imaging::apply_working_tone_adjustments(
            std::move(color_grading_image),
            color_grading_parameters);

    PixelErrorMetrics color_grading_metrics{};
    if (color_grading_adjusted.status !=
            negaflow::imaging::WorkingToneAdjustStatus::ok ||
        !color_grading_adjusted.info.color_grading_applied ||
        color_grading_adjusted.info.point_curve_applied ||
        color_grading_adjusted.info.color_mixer_applied) {
        ++color_grading_metrics.failure_count;
    } else {
        color_grading_metrics = compare_pixels(
            color_grading_adjusted.image.pixels,
            negaflow::fixtures::color_grading_expected,
            negaflow::fixtures::color_grading_absolute_tolerance,
            negaflow::fixtures::color_grading_relative_tolerance);
    }

    const negaflow::core::BuildInfo build_info = negaflow::core::query_build_info();
    const std::size_t failure_count =
        negative_failure_count + tone_metrics.failure_count +
        point_curve_metrics.failure_count + color_mixer_metrics.failure_count +
        color_grading_metrics.failure_count;
    const bool passed = failure_count == 0U;
    std::cout << "{\"schema_version\":1,\"status\":\""
              << (passed ? "ok" : "failed") << "\",\"fixture_id\":\""
              << negaflow::fixtures::scalar_foundation_fixture_id
              << "\",\"algorithm_version\":\""
              << negaflow::core::negative_inversion_algorithm_version
              << "\",\"architecture\":\""
              << negaflow::core::architecture_name(build_info.architecture)
              << "\",\"source_dirty\":" << (build_info.source_dirty ? "true" : "false")
              << ",\"case_count\":" << negaflow::fixtures::color_negative_cases.size()
              << ",\"finite_output_count\":" << finite_output_count
              << ",\"negative_failure_count\":" << negative_failure_count
              << ",\"failure_count\":" << failure_count
              << ",\"max_absolute_error\":"
              << std::setprecision(std::numeric_limits<double>::max_digits10)
              << maximum_absolute_error << ",\"max_relative_error\":"
              << maximum_relative_error << ",\"tone_fixture_id\":\""
              << negaflow::fixtures::tone_mapping_fixture_id
              << "\",\"tone_algorithm_version\":\""
              << negaflow::imaging::tone_mapping_algorithm_version
              << "\",\"tone_value_count\":"
              << negaflow::fixtures::tone_mapping_expected.size() * 4U
              << ",\"tone_finite_output_count\":"
              << tone_metrics.finite_output_count
              << ",\"tone_failure_count\":" << tone_metrics.failure_count
              << ",\"tone_max_absolute_error\":"
              << tone_metrics.maximum_absolute_error
              << ",\"tone_max_relative_error\":"
              << tone_metrics.maximum_relative_error
              << ",\"point_curve_fixture_id\":\""
              << negaflow::fixtures::point_curve_fixture_id
              << "\",\"point_curve_algorithm_version\":\""
              << negaflow::imaging::point_curve_algorithm_version
              << "\",\"point_curve_value_count\":"
              << negaflow::fixtures::point_curve_expected.size() * 4U
              << ",\"point_curve_finite_output_count\":"
              << point_curve_metrics.finite_output_count
              << ",\"point_curve_failure_count\":"
              << point_curve_metrics.failure_count
              << ",\"point_curve_max_absolute_error\":"
              << point_curve_metrics.maximum_absolute_error
              << ",\"point_curve_max_relative_error\":"
              << point_curve_metrics.maximum_relative_error
              << ",\"color_mixer_fixture_id\":\""
              << negaflow::fixtures::color_mixer_fixture_id
              << "\",\"color_mixer_algorithm_version\":\""
              << negaflow::imaging::color_mixer_algorithm_version
              << "\",\"color_mixer_value_count\":"
              << negaflow::fixtures::color_mixer_expected.size() * 4U
              << ",\"color_mixer_finite_output_count\":"
              << color_mixer_metrics.finite_output_count
              << ",\"color_mixer_failure_count\":"
              << color_mixer_metrics.failure_count
              << ",\"color_mixer_max_absolute_error\":"
              << color_mixer_metrics.maximum_absolute_error
              << ",\"color_mixer_max_relative_error\":"
              << color_mixer_metrics.maximum_relative_error
              << ",\"color_grading_fixture_id\":\""
              << negaflow::fixtures::color_grading_fixture_id
              << "\",\"color_grading_algorithm_version\":\""
              << negaflow::imaging::color_grading_algorithm_version
              << "\",\"color_grading_value_count\":"
              << negaflow::fixtures::color_grading_expected.size() * 4U
              << ",\"color_grading_finite_output_count\":"
              << color_grading_metrics.finite_output_count
              << ",\"color_grading_failure_count\":"
              << color_grading_metrics.failure_count
              << ",\"color_grading_max_absolute_error\":"
              << color_grading_metrics.maximum_absolute_error
              << ",\"color_grading_max_relative_error\":"
              << color_grading_metrics.maximum_relative_error << "}\n";
    return passed ? 0 : 1;
}
