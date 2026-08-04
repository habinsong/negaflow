#include "negaflow/imaging/point_curve.h"
#include "negaflow/imaging/tone_mapping.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "point_curve_fixture.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <iostream>
#include <limits>
#include <utility>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool nearly_equal(
    const float actual,
    const float expected,
    const float absolute_tolerance =
        negaflow::fixtures::point_curve_absolute_tolerance,
    const float relative_tolerance =
        negaflow::fixtures::point_curve_relative_tolerance) noexcept {
    const float difference = std::abs(actual - expected);
    const float scale = std::max(std::abs(actual), std::abs(expected));
    return difference <= absolute_tolerance + (relative_tolerance * scale);
}

void expect_pixel_near(
    const negaflow::core::Rgba32F actual,
    const negaflow::core::Rgba32F expected,
    const char* const message) {
    const bool matches = nearly_equal(actual.red, expected.red) &&
                         nearly_equal(actual.green, expected.green) &&
                         nearly_equal(actual.blue, expected.blue) &&
                         actual.alpha == expected.alpha;
    if (!matches) {
        std::cerr << "FAIL: " << message << " actual=[" << actual.red << ','
                  << actual.green << ',' << actual.blue << ',' << actual.alpha
                  << "] expected=[" << expected.red << ',' << expected.green << ','
                  << expected.blue << ',' << expected.alpha << "]\n";
        ++failures;
    }
}

void test_fixed_lut_and_pixel_fixture() {
    negaflow::imaging::PointCurveLuts luts{};
    expect(
        negaflow::imaging::build_point_curve_luts(
            negaflow::fixtures::point_curve_parameters,
            luts) == negaflow::core::KernelStatus::ok,
        "fixed point-curve LUT builds");
    for (const auto& sample : negaflow::fixtures::point_curve_lut_samples) {
        expect(
            nearly_equal(luts.red[sample.index], sample.red) &&
                nearly_equal(luts.green[sample.index], sample.green) &&
                nearly_equal(luts.blue[sample.index], sample.blue),
            "fixed encoded LUT sample matches independent calculation");
    }

    std::array<negaflow::core::Rgba32F,
               negaflow::fixtures::point_curve_input.size()> output{};
    const auto status = negaflow::imaging::apply_point_curves(
        {negaflow::fixtures::point_curve_input.data(),
         negaflow::fixtures::point_curve_input.size(),
         3U,
         2U,
         3U},
        {output.data(), output.size(), 3U, 2U, 3U},
        negaflow::fixtures::point_curve_parameters);
    expect(status == negaflow::core::KernelStatus::ok, "fixed point curve applies");
    for (std::size_t index = 0U; index < output.size(); ++index) {
        expect_pixel_near(
            output[index],
            negaflow::fixtures::point_curve_expected[index],
            "fixed linear-working pixel matches independent calculation");
    }

    auto in_place = negaflow::fixtures::point_curve_input;
    expect(
        negaflow::imaging::apply_point_curves(
            {in_place.data(), in_place.size(), 3U, 2U, 3U},
            {in_place.data(), in_place.size(), 3U, 2U, 3U},
            negaflow::fixtures::point_curve_parameters) ==
            negaflow::core::KernelStatus::ok,
        "in-place point curve applies");
    for (std::size_t index = 0U; index < output.size(); ++index) {
        expect_pixel_near(in_place[index], output[index], "in-place output matches separate output");
    }
}

void test_identity_is_bit_exact_and_preserves_padding() {
    const negaflow::core::Rgba32F padding{91.0F, 92.0F, 93.0F, 0.0F};
    std::array<negaflow::core::Rgba32F, 4> input{{
        {-0.25F, 0.5F, 1.5F, 0.25F},
        {0.2F, 0.4F, 0.8F, 1.0F},
        padding,
        padding,
    }};
    std::array<negaflow::core::Rgba32F, 4> output{{padding, padding, padding, padding}};
    const negaflow::imaging::PointCurves identity{};
    expect(!negaflow::imaging::has_point_curve_change(identity), "empty curves are identity");
    expect(
        negaflow::imaging::apply_point_curves(
            {input.data(), input.size(), 2U, 1U, 4U},
            {output.data(), output.size(), 2U, 1U, 4U},
            identity) == negaflow::core::KernelStatus::ok,
        "identity point curve succeeds");
    expect(
        output[0].red == input[0].red && output[0].green == input[0].green &&
            output[0].blue == input[0].blue && output[0].alpha == input[0].alpha &&
            output[1].red == input[1].red && output[1].blue == input[1].blue,
        "identity point curve preserves extended pixels bit exactly");
    expect(output[2].red == padding.red && output[3].blue == padding.blue,
           "identity point curve does not write stride padding");

    negaflow::imaging::PointCurves near_identity{};
    near_identity.rgb = negaflow::fixtures::make_point_curve(std::array{
        negaflow::imaging::CurvePoint{0.0, 0.00005},
        negaflow::imaging::CurvePoint{1.0, 0.99995},
    });
    expect(!negaflow::imaging::has_point_curve_change(near_identity),
           "macOS identity threshold remains a no-op");
}

void test_sorting_endpoint_extension_and_single_point_composition() {
    negaflow::imaging::PointCurves unsorted{};
    unsorted.rgb = negaflow::fixtures::make_point_curve(std::array{
        negaflow::imaging::CurvePoint{0.8, 0.9},
        negaflow::imaging::CurvePoint{0.2, 0.1},
    });
    negaflow::imaging::PointCurves sorted{};
    sorted.rgb = negaflow::fixtures::make_point_curve(std::array{
        negaflow::imaging::CurvePoint{0.2, 0.1},
        negaflow::imaging::CurvePoint{0.8, 0.9},
    });
    negaflow::imaging::PointCurveLuts unsorted_luts{};
    negaflow::imaging::PointCurveLuts sorted_luts{};
    expect(
        negaflow::imaging::build_point_curve_luts(unsorted, unsorted_luts) ==
                negaflow::core::KernelStatus::ok &&
            negaflow::imaging::build_point_curve_luts(sorted, sorted_luts) ==
                negaflow::core::KernelStatus::ok &&
            unsorted_luts.red == sorted_luts.red,
        "unordered persisted points are sorted deterministically");
    expect(nearly_equal(sorted_luts.red.front(), 6.0F / 63.0F) &&
               nearly_equal(sorted_luts.red.back(), 57.0F / 63.0F),
           "missing endpoints extend values before the macOS 64-sample composition");

    negaflow::imaging::PointCurves one_point_channel = sorted;
    one_point_channel.red = negaflow::fixtures::make_point_curve(std::array{
        negaflow::imaging::CurvePoint{0.4, 0.7},
    });
    negaflow::imaging::PointCurveLuts one_point_luts{};
    expect(
        negaflow::imaging::build_point_curve_luts(
            one_point_channel,
            one_point_luts) == negaflow::core::KernelStatus::ok,
        "single channel point builds when another curve activates the stage");
    expect(std::ranges::all_of(one_point_luts.red, [](const float value) {
               return nearly_equal(value, 0.7F);
           }),
           "single point follows the macOS constant-channel composition");
}

void test_parameter_and_view_failures() {
    negaflow::imaging::PointCurves at_capacity{};
    at_capacity.rgb.point_count = negaflow::imaging::point_curve_max_points;
    for (std::size_t index = 0U;
         index < negaflow::imaging::point_curve_max_points;
         ++index) {
        const double value = static_cast<double>(index) /
                             static_cast<double>(
                                 negaflow::imaging::point_curve_max_points - 1U);
        at_capacity.rgb.points[index] = {value, value};
    }
    negaflow::imaging::PointCurveLuts luts{};
    expect(negaflow::imaging::valid_point_curves(at_capacity) &&
               negaflow::imaging::build_point_curve_luts(at_capacity, luts) ==
                   negaflow::core::KernelStatus::ok,
           "the fixed 64-point capacity is accepted");

    negaflow::imaging::PointCurves invalid{};
    invalid.rgb.point_count = negaflow::imaging::point_curve_max_points + 1U;
    expect(!negaflow::imaging::valid_point_curves(invalid) &&
               negaflow::imaging::build_point_curve_luts(invalid, luts) ==
                   negaflow::core::KernelStatus::invalid_parameter,
           "point count above the fixed capacity is rejected");

    invalid = {};
    invalid.rgb = negaflow::fixtures::make_point_curve(std::array{
        negaflow::imaging::CurvePoint{
            std::numeric_limits<double>::quiet_NaN(),
            0.0},
        negaflow::imaging::CurvePoint{1.0, 1.0},
    });
    expect(negaflow::imaging::build_point_curve_luts(invalid, luts) ==
               negaflow::core::KernelStatus::non_finite_parameter,
           "non-finite curve points are rejected");

    invalid = {};
    invalid.rgb = negaflow::fixtures::make_point_curve(std::array{
        negaflow::imaging::CurvePoint{0.0, 0.0},
        negaflow::imaging::CurvePoint{0.5, 1.01},
        negaflow::imaging::CurvePoint{1.0, 1.0},
    });
    expect(negaflow::imaging::build_point_curve_luts(invalid, luts) ==
               negaflow::core::KernelStatus::invalid_parameter,
           "points outside the unit editor contract are rejected");

    invalid = {};
    invalid.rgb = negaflow::fixtures::make_point_curve(std::array{
        negaflow::imaging::CurvePoint{0.5, 0.2},
        negaflow::imaging::CurvePoint{0.5, 0.8},
    });
    expect(negaflow::imaging::build_point_curve_luts(invalid, luts) ==
               negaflow::core::KernelStatus::invalid_parameter,
           "duplicate x coordinates are rejected");

    std::array<negaflow::core::Rgba32F, 2> pixels{{
        {0.2F, 0.3F, 0.4F, 1.0F},
        {0.5F, 0.6F, 0.7F, 1.0F},
    }};
    expect(
        negaflow::imaging::apply_point_curves(
            {pixels.data(), pixels.size(), 2U, 1U, 1U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            negaflow::fixtures::point_curve_parameters) ==
            negaflow::core::KernelStatus::invalid_stride,
        "invalid source stride is rejected");
    pixels[0].red = std::numeric_limits<float>::infinity();
    expect(
        negaflow::imaging::apply_point_curves(
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            negaflow::fixtures::point_curve_parameters) ==
            negaflow::core::KernelStatus::non_finite_input,
        "non-finite source pixels are rejected");
}

void test_pipeline_order_and_failure_publication() {
    negaflow::imaging::WorkingImage source{};
    source.width = 3U;
    source.height = 2U;
    source.stride_pixels = 3U;
    source.pixels.assign(
        negaflow::fixtures::point_curve_input.begin(),
        negaflow::fixtures::point_curve_input.end());

    negaflow::imaging::WorkingImage manual = source;
    negaflow::imaging::BasicToneParameters basic{};
    basic.contrast = 0.25F;
    expect(
        negaflow::imaging::apply_basic_tone(
            {manual.pixels.data(), manual.pixels.size(), 3U, 2U, 3U},
            {manual.pixels.data(), manual.pixels.size(), 3U, 2U, 3U},
            basic) == negaflow::core::KernelStatus::ok &&
            negaflow::imaging::apply_point_curves(
                {manual.pixels.data(), manual.pixels.size(), 3U, 2U, 3U},
                {manual.pixels.data(), manual.pixels.size(), 3U, 2U, 3U},
                negaflow::fixtures::point_curve_parameters) ==
                negaflow::core::KernelStatus::ok,
        "manual basic-tone then point-curve sequence succeeds");

    negaflow::imaging::WorkingToneAdjustParameters parameters{};
    parameters.basic = basic;
    parameters.point_curves = negaflow::fixtures::point_curve_parameters;
    const auto adjusted = negaflow::imaging::apply_working_tone_adjustments(
        std::move(source),
        parameters);
    expect(adjusted.status == negaflow::imaging::WorkingToneAdjustStatus::ok &&
               adjusted.info.basic_tone_applied &&
               adjusted.info.point_curve_applied &&
               !adjusted.info.parametric_curve_applied,
           "working pipeline reports the two applied stages");
    expect(adjusted.image.pixels.size() == manual.pixels.size(),
           "working pipeline preserves pixel count");
    if (adjusted.image.pixels.size() == manual.pixels.size()) {
        for (std::size_t index = 0U; index < manual.pixels.size(); ++index) {
            expect_pixel_near(
                adjusted.image.pixels[index],
                manual.pixels[index],
                "point curve runs after basic tone in the working pipeline");
        }
    }

    negaflow::imaging::WorkingImage rejected{};
    rejected.width = 1U;
    rejected.height = 1U;
    rejected.stride_pixels = 1U;
    rejected.pixels = {{0.2F, 0.3F, 0.4F, 1.0F}};
    parameters.point_curves.rgb.point_count =
        negaflow::imaging::point_curve_max_points + 1U;
    const auto failed = negaflow::imaging::apply_working_tone_adjustments(
        std::move(rejected),
        parameters);
    expect(failed.status == negaflow::imaging::WorkingToneAdjustStatus::invalid_parameter &&
               failed.image.pixels.empty(),
           "invalid point curves publish no adjusted pixels");
}

}  // namespace

int main() {
    test_fixed_lut_and_pixel_fixture();
    test_identity_is_bit_exact_and_preserves_padding();
    test_sorting_endpoint_extension_and_single_point_composition();
    test_parameter_and_view_failures();
    test_pipeline_order_and_failure_publication();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"point_curve\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
