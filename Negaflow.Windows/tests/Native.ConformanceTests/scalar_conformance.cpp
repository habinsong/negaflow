#include "negaflow/core/build_info.h"
#include "negaflow/core/negative_inversion.h"
#include "negaflow/imaging/point_curve.h"
#include "negaflow/imaging/working_tone_adjuster.h"
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

    double tone_maximum_absolute_error = 0.0;
    double tone_maximum_relative_error = 0.0;
    std::size_t tone_finite_output_count = 0U;
    std::size_t tone_failure_count = 0U;
    if (adjusted.status != negaflow::imaging::WorkingToneAdjustStatus::ok ||
        adjusted.image.pixels.size() !=
            negaflow::fixtures::tone_mapping_expected.size()) {
        ++tone_failure_count;
    } else {
        for (std::size_t pixel_index = 0U;
             pixel_index < adjusted.image.pixels.size();
             ++pixel_index) {
            const auto& actual_pixel = adjusted.image.pixels[pixel_index];
            const auto& expected_pixel =
                negaflow::fixtures::tone_mapping_expected[pixel_index];
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
                    ++tone_failure_count;
                    continue;
                }
                ++tone_finite_output_count;
                const double actual_value = static_cast<double>(actual[channel]);
                const double expected_value = static_cast<double>(expected[channel]);
                const double absolute_error =
                    std::abs(actual_value - expected_value);
                const double relative_scale =
                    std::max(std::abs(actual_value), std::abs(expected_value));
                const double relative_error = relative_scale == 0.0
                    ? 0.0
                    : absolute_error / relative_scale;
                tone_maximum_absolute_error =
                    std::max(tone_maximum_absolute_error, absolute_error);
                tone_maximum_relative_error =
                    std::max(tone_maximum_relative_error, relative_error);
                const double allowed_error =
                    static_cast<double>(
                        negaflow::fixtures::tone_mapping_absolute_tolerance) +
                    (static_cast<double>(
                         negaflow::fixtures::tone_mapping_relative_tolerance) *
                     relative_scale);
                if (absolute_error > allowed_error) {
                    ++tone_failure_count;
                }
            }
        }
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

    double point_curve_maximum_absolute_error = 0.0;
    double point_curve_maximum_relative_error = 0.0;
    std::size_t point_curve_finite_output_count = 0U;
    std::size_t point_curve_failure_count = 0U;
    if (point_curve_adjusted.status !=
            negaflow::imaging::WorkingToneAdjustStatus::ok ||
        !point_curve_adjusted.info.point_curve_applied ||
        point_curve_adjusted.image.pixels.size() !=
            negaflow::fixtures::point_curve_expected.size()) {
        ++point_curve_failure_count;
    } else {
        for (std::size_t pixel_index = 0U;
             pixel_index < point_curve_adjusted.image.pixels.size();
             ++pixel_index) {
            const auto& actual_pixel =
                point_curve_adjusted.image.pixels[pixel_index];
            const auto& expected_pixel =
                negaflow::fixtures::point_curve_expected[pixel_index];
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
                    ++point_curve_failure_count;
                    continue;
                }
                ++point_curve_finite_output_count;
                const double actual_value = static_cast<double>(actual[channel]);
                const double expected_value = static_cast<double>(expected[channel]);
                const double absolute_error =
                    std::abs(actual_value - expected_value);
                const double relative_scale =
                    std::max(std::abs(actual_value), std::abs(expected_value));
                const double relative_error = relative_scale == 0.0
                    ? 0.0
                    : absolute_error / relative_scale;
                point_curve_maximum_absolute_error = std::max(
                    point_curve_maximum_absolute_error,
                    absolute_error);
                point_curve_maximum_relative_error = std::max(
                    point_curve_maximum_relative_error,
                    relative_error);
                const double allowed_error =
                    static_cast<double>(
                        negaflow::fixtures::point_curve_absolute_tolerance) +
                    (static_cast<double>(
                         negaflow::fixtures::point_curve_relative_tolerance) *
                     relative_scale);
                if (absolute_error > allowed_error) {
                    ++point_curve_failure_count;
                }
            }
        }
    }

    const negaflow::core::BuildInfo build_info = negaflow::core::query_build_info();
    const std::size_t failure_count =
        negative_failure_count + tone_failure_count + point_curve_failure_count;
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
              << ",\"tone_finite_output_count\":" << tone_finite_output_count
              << ",\"tone_failure_count\":" << tone_failure_count
              << ",\"tone_max_absolute_error\":"
              << tone_maximum_absolute_error
              << ",\"tone_max_relative_error\":"
              << tone_maximum_relative_error
              << ",\"point_curve_fixture_id\":\""
              << negaflow::fixtures::point_curve_fixture_id
              << "\",\"point_curve_algorithm_version\":\""
              << negaflow::imaging::point_curve_algorithm_version
              << "\",\"point_curve_value_count\":"
              << negaflow::fixtures::point_curve_expected.size() * 4U
              << ",\"point_curve_finite_output_count\":"
              << point_curve_finite_output_count
              << ",\"point_curve_failure_count\":"
              << point_curve_failure_count
              << ",\"point_curve_max_absolute_error\":"
              << point_curve_maximum_absolute_error
              << ",\"point_curve_max_relative_error\":"
              << point_curve_maximum_relative_error << "}\n";
    return passed ? 0 : 1;
}
