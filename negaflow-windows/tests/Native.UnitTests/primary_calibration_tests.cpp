#include "negaflow/imaging/color_grading.h"
#include "negaflow/imaging/color_mixer.h"
#include "negaflow/imaging/point_curve.h"
#include "negaflow/imaging/primary_calibration.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "color_grading_fixture.h"
#include "color_mixer_fixture.h"
#include "point_curve_fixture.h"
#include "primary_calibration_fixture.h"

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
        negaflow::fixtures::primary_calibration_absolute_tolerance,
    const float relative_tolerance =
        negaflow::fixtures::primary_calibration_relative_tolerance) noexcept {
    const float difference = std::abs(actual - expected);
    const float scale = std::max(std::abs(actual), std::abs(expected));
    return difference <= absolute_tolerance + (relative_tolerance * scale);
}

void expect_pixel_near(
    const negaflow::core::Rgba32F actual,
    const negaflow::core::Rgba32F expected,
    const char* const message) {
    if (!nearly_equal(actual.red, expected.red) ||
        !nearly_equal(actual.green, expected.green) ||
        !nearly_equal(actual.blue, expected.blue) ||
        actual.alpha != expected.alpha) {
        std::cerr << "FAIL: " << message << " actual=[" << actual.red << ','
                  << actual.green << ',' << actual.blue << ',' << actual.alpha
                  << "] expected=[" << expected.red << ',' << expected.green
                  << ',' << expected.blue << ',' << expected.alpha << "]\n";
        ++failures;
    }
}

[[nodiscard]] float chroma(const negaflow::core::Rgba32F pixel) noexcept {
    const float maximum = std::max(pixel.red, std::max(pixel.green, pixel.blue));
    const float minimum = std::min(pixel.red, std::min(pixel.green, pixel.blue));
    return maximum - minimum;
}

void test_fixed_fixture_and_in_place_parity() {
    std::array<negaflow::core::Rgba32F,
               negaflow::fixtures::primary_calibration_input.size()> output{};
    expect(
        negaflow::imaging::apply_primary_calibration(
            {negaflow::fixtures::primary_calibration_input.data(),
             negaflow::fixtures::primary_calibration_input.size(),
             4U,
             3U,
             4U},
            {output.data(), output.size(), 4U, 3U, 4U},
            negaflow::fixtures::primary_calibration_parameters) ==
            negaflow::core::KernelStatus::ok,
        "fixed primary calibration applies");
    for (std::size_t index = 0U; index < output.size(); ++index) {
        expect_pixel_near(
            output[index],
            negaflow::fixtures::primary_calibration_expected[index],
            "fixed primary calibration matches independent Float32 calculation");
    }

    auto in_place = negaflow::fixtures::primary_calibration_input;
    expect(
        negaflow::imaging::apply_primary_calibration(
            {in_place.data(), in_place.size(), 4U, 3U, 4U},
            {in_place.data(), in_place.size(), 4U, 3U, 4U},
            negaflow::fixtures::primary_calibration_parameters) ==
            negaflow::core::KernelStatus::ok,
        "in-place primary calibration applies");
    for (std::size_t index = 0U; index < output.size(); ++index) {
        expect_pixel_near(
            in_place[index],
            output[index],
            "in-place primary calibration matches separate output");
    }
}

void test_identity_threshold_and_padding() {
    const negaflow::core::Rgba32F padding{91.0F, 92.0F, 93.0F, 0.0F};
    std::array<negaflow::core::Rgba32F, 4> input{{
        {-0.25F, 0.5F, 1.5F, 0.25F},
        {0.2F, 0.4F, 0.8F, 1.0F},
        padding,
        padding,
    }};
    std::array<negaflow::core::Rgba32F, 4> output{{
        padding,
        padding,
        padding,
        padding,
    }};
    negaflow::imaging::PrimaryCalibrationParameters identity{};
    identity.red_hue = 0.000099F;
    identity.green_saturation = -0.000099F;
    expect(!negaflow::imaging::has_primary_calibration_change(identity),
           "controls below the macOS calibration threshold are a no-op");
    expect(
        negaflow::imaging::apply_primary_calibration(
            {input.data(), input.size(), 2U, 1U, 4U},
            {output.data(), output.size(), 2U, 1U, 4U},
            identity) == negaflow::core::KernelStatus::ok,
        "identity primary calibration succeeds");
    expect(output[0].red == input[0].red && output[0].green == input[0].green &&
               output[0].blue == input[0].blue && output[0].alpha == input[0].alpha &&
               output[1].red == input[1].red && output[1].blue == input[1].blue,
           "identity primary calibration preserves extended pixels bit exactly");
    expect(output[2].red == padding.red && output[3].blue == padding.blue,
           "identity primary calibration does not write stride padding");

    identity.red_hue = 0.0001F;
    expect(negaflow::imaging::has_primary_calibration_change(identity),
           "the exact macOS calibration threshold activates the stage");
}

void test_primary_controls_gray_gate_and_active_domain() {
    negaflow::imaging::PrimaryCalibrationParameters red_saturation{};
    red_saturation.red_saturation = 1.0F;
    const negaflow::core::Rgba32F source_red{0.62F, 0.30F, 0.30F, 0.3F};
    auto boosted_red = source_red;
    expect(
        negaflow::imaging::apply_primary_calibration(
            {&boosted_red, 1U, 1U, 1U, 1U},
            {&boosted_red, 1U, 1U, 1U, 1U},
            red_saturation) == negaflow::core::KernelStatus::ok &&
            chroma(boosted_red) > chroma(source_red) + 0.01F &&
            boosted_red.alpha == source_red.alpha,
        "red primary saturation boosts red-patch chroma");

    negaflow::imaging::PrimaryCalibrationParameters red_hue{};
    red_hue.red_hue = 1.0F;
    auto shifted_red = source_red;
    expect(
        negaflow::imaging::apply_primary_calibration(
            {&shifted_red, 1U, 1U, 1U, 1U},
            {&shifted_red, 1U, 1U, 1U, 1U},
            red_hue) == negaflow::core::KernelStatus::ok &&
            shifted_red.green > source_red.green + 0.1F,
        "positive red primary hue rotates a red patch toward yellow");

    negaflow::core::Rgba32F gray{0.5F, 0.5F, 0.5F, 0.6F};
    expect(
        negaflow::imaging::apply_primary_calibration(
            {&gray, 1U, 1U, 1U, 1U},
            {&gray, 1U, 1U, 1U, 1U},
            red_saturation) == negaflow::core::KernelStatus::ok &&
            gray.red == 0.5F && gray.green == 0.5F && gray.blue == 0.5F &&
            gray.alpha == 0.6F,
        "the saturation gate preserves neutral gray");

    negaflow::core::Rgba32F extended{-1.0F, 0.5F, 2.0F, 0.7F};
    expect(
        negaflow::imaging::apply_primary_calibration(
            {&extended, 1U, 1U, 1U, 1U},
            {&extended, 1U, 1U, 1U, 1U},
            red_hue) == negaflow::core::KernelStatus::ok &&
            extended.red >= 0.0F && extended.red <= 1.0F &&
            extended.green >= 0.0F && extended.green <= 1.0F &&
            extended.blue >= 0.0F && extended.blue <= 1.0F &&
            extended.alpha == 0.7F,
        "active primary calibration clamps the HSL working domain");
}

void test_parameter_and_view_failures() {
    negaflow::imaging::PrimaryCalibrationParameters invalid{};
    invalid.blue_hue = 1.01F;
    std::array<negaflow::core::Rgba32F, 2> pixels{{
        {0.2F, 0.3F, 0.4F, 1.0F},
        {0.5F, 0.6F, 0.7F, 1.0F},
    }};
    expect(!negaflow::imaging::valid_primary_calibration_parameters(invalid) &&
               negaflow::imaging::apply_primary_calibration(
                   {pixels.data(), pixels.size(), 2U, 1U, 2U},
                   {pixels.data(), pixels.size(), 2U, 1U, 2U},
                   invalid) == negaflow::core::KernelStatus::invalid_parameter,
           "primary calibration controls above one are rejected");
    invalid = {};
    invalid.green_saturation = std::numeric_limits<float>::quiet_NaN();
    expect(!negaflow::imaging::valid_primary_calibration_parameters(invalid) &&
               negaflow::imaging::apply_primary_calibration(
                   {pixels.data(), pixels.size(), 2U, 1U, 2U},
                   {pixels.data(), pixels.size(), 2U, 1U, 2U},
                   invalid) ==
                   negaflow::core::KernelStatus::non_finite_parameter,
           "non-finite primary calibration controls are rejected");

    expect(
        negaflow::imaging::apply_primary_calibration(
            {pixels.data(), pixels.size(), 2U, 1U, 1U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            negaflow::fixtures::primary_calibration_parameters) ==
            negaflow::core::KernelStatus::invalid_stride,
        "invalid source stride is rejected");
    pixels[0].blue = std::numeric_limits<float>::infinity();
    expect(
        negaflow::imaging::apply_primary_calibration(
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            negaflow::fixtures::primary_calibration_parameters) ==
            negaflow::core::KernelStatus::non_finite_input,
        "non-finite source pixels are rejected");
}

void test_pipeline_order_and_failure_publication() {
    negaflow::imaging::WorkingImage source{};
    source.width = 4U;
    source.height = 3U;
    source.stride_pixels = 4U;
    source.pixels.assign(
        negaflow::fixtures::color_grading_input.begin(),
        negaflow::fixtures::color_grading_input.end());

    negaflow::imaging::WorkingImage manual = source;
    expect(
        negaflow::imaging::apply_point_curves(
            {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
            {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
            negaflow::fixtures::point_curve_parameters) ==
                negaflow::core::KernelStatus::ok &&
            negaflow::imaging::apply_color_mixer(
                {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
                {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
                negaflow::fixtures::color_mixer_parameters) ==
                negaflow::core::KernelStatus::ok &&
            negaflow::imaging::apply_color_grading(
                {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
                {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
                negaflow::fixtures::color_grading_parameters) ==
                negaflow::core::KernelStatus::ok &&
            negaflow::imaging::apply_primary_calibration(
                {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
                {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
                negaflow::fixtures::primary_calibration_parameters) ==
                negaflow::core::KernelStatus::ok,
        "manual point-curve mixer grading calibration sequence succeeds");

    negaflow::imaging::WorkingToneAdjustParameters parameters{};
    parameters.point_curves = negaflow::fixtures::point_curve_parameters;
    parameters.color_mixer = negaflow::fixtures::color_mixer_parameters;
    parameters.color_grading = negaflow::fixtures::color_grading_parameters;
    parameters.primary_calibration =
        negaflow::fixtures::primary_calibration_parameters;
    const auto adjusted = negaflow::imaging::apply_working_tone_adjustments(
        std::move(source),
        parameters);
    expect(adjusted.status == negaflow::imaging::WorkingToneAdjustStatus::ok &&
               adjusted.info.point_curve_applied &&
               adjusted.info.color_mixer_applied &&
               adjusted.info.color_grading_applied &&
               adjusted.info.primary_calibration_applied,
           "working pipeline reports all four post-pipeline stages");
    if (adjusted.image.pixels.size() == manual.pixels.size()) {
        for (std::size_t index = 0U; index < manual.pixels.size(); ++index) {
            expect_pixel_near(
                adjusted.image.pixels[index],
                manual.pixels[index],
                "calibration runs after grading in the working pipeline");
        }
    } else {
        expect(false, "working pipeline preserves pixel count");
    }

    negaflow::imaging::WorkingImage rejected{};
    rejected.width = 1U;
    rejected.height = 1U;
    rejected.stride_pixels = 1U;
    rejected.pixels = {{0.2F, 0.3F, 0.4F, 1.0F}};
    parameters = {};
    parameters.primary_calibration.blue_saturation = -1.01F;
    const auto failed = negaflow::imaging::apply_working_tone_adjustments(
        std::move(rejected),
        parameters);
    expect(failed.status ==
                   negaflow::imaging::WorkingToneAdjustStatus::invalid_parameter &&
               failed.image.pixels.empty(),
           "invalid primary calibration controls publish no adjusted pixels");
}

}  // namespace

int main() {
    test_fixed_fixture_and_in_place_parity();
    test_identity_threshold_and_padding();
    test_primary_controls_gray_gate_and_active_domain();
    test_parameter_and_view_failures();
    test_pipeline_order_and_failure_publication();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"primary_calibration\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
