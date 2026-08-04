#include "negaflow/imaging/color_grading.h"
#include "negaflow/imaging/color_mixer.h"
#include "negaflow/imaging/point_curve.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "color_grading_fixture.h"
#include "color_mixer_fixture.h"
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
        negaflow::fixtures::color_grading_absolute_tolerance,
    const float relative_tolerance =
        negaflow::fixtures::color_grading_relative_tolerance) noexcept {
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

void test_fixed_fixture_and_in_place_parity() {
    std::array<negaflow::core::Rgba32F,
               negaflow::fixtures::color_grading_input.size()> output{};
    expect(
        negaflow::imaging::apply_color_grading(
            {negaflow::fixtures::color_grading_input.data(),
             negaflow::fixtures::color_grading_input.size(),
             4U,
             3U,
             4U},
            {output.data(), output.size(), 4U, 3U, 4U},
            negaflow::fixtures::color_grading_parameters) ==
            negaflow::core::KernelStatus::ok,
        "fixed color grading applies");
    for (std::size_t index = 0U; index < output.size(); ++index) {
        expect_pixel_near(
            output[index],
            negaflow::fixtures::color_grading_expected[index],
            "fixed color grading pixel matches independent Float32 calculation");
    }

    auto in_place = negaflow::fixtures::color_grading_input;
    expect(
        negaflow::imaging::apply_color_grading(
            {in_place.data(), in_place.size(), 4U, 3U, 4U},
            {in_place.data(), in_place.size(), 4U, 3U, 4U},
            negaflow::fixtures::color_grading_parameters) ==
            negaflow::core::KernelStatus::ok,
        "in-place color grading applies");
    for (std::size_t index = 0U; index < output.size(); ++index) {
        expect_pixel_near(
            in_place[index],
            output[index],
            "in-place color grading matches separate output");
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
    negaflow::imaging::ColorGradingParameters identity{};
    identity.shadows.hue_degrees = 270.0F;
    identity.shadows.saturation = 0.0001F;
    identity.midtones.luminance = -0.0001F;
    identity.blending = 0.0F;
    identity.balance = 1.0F;
    expect(!negaflow::imaging::has_color_grading_change(identity),
           "the exact macOS grading threshold is a no-op");
    expect(
        negaflow::imaging::apply_color_grading(
            {input.data(), input.size(), 2U, 1U, 4U},
            {output.data(), output.size(), 2U, 1U, 4U},
            identity) == negaflow::core::KernelStatus::ok,
        "identity color grading succeeds");
    expect(output[0].red == input[0].red && output[0].green == input[0].green &&
               output[0].blue == input[0].blue && output[0].alpha == input[0].alpha &&
               output[1].red == input[1].red && output[1].blue == input[1].blue,
           "identity color grading preserves extended pixels bit exactly");
    expect(output[2].red == padding.red && output[3].blue == padding.blue,
           "identity color grading does not write stride padding");

    identity.shadows.saturation = 0.000101F;
    expect(negaflow::imaging::has_color_grading_change(identity),
           "a value above the macOS threshold activates grading");
}

void test_region_controls_and_active_unit_domain() {
    negaflow::imaging::ColorGradingParameters shadow_orange{};
    shadow_orange.shadows.hue_degrees = 30.0F;
    shadow_orange.shadows.saturation = 0.8F;
    negaflow::core::Rgba32F dark_gray{0.18F, 0.18F, 0.18F, 0.3F};
    expect(
        negaflow::imaging::apply_color_grading(
            {&dark_gray, 1U, 1U, 1U, 1U},
            {&dark_gray, 1U, 1U, 1U, 1U},
            shadow_orange) == negaflow::core::KernelStatus::ok &&
            std::max(dark_gray.red, std::max(dark_gray.green, dark_gray.blue)) -
                    std::min(dark_gray.red, std::min(dark_gray.green, dark_gray.blue)) >
                0.01F &&
            dark_gray.alpha == 0.3F,
        "orange shadow wheel adds chroma to dark neutral pixels");

    negaflow::core::Rgba32F extended{-1.0F, 0.5F, 2.0F, 0.7F};
    expect(
        negaflow::imaging::apply_color_grading(
            {&extended, 1U, 1U, 1U, 1U},
            {&extended, 1U, 1U, 1U, 1U},
            shadow_orange) == negaflow::core::KernelStatus::ok &&
            extended.red >= 0.0F && extended.red <= 1.0F &&
            extended.green >= 0.0F && extended.green <= 1.0F &&
            extended.blue >= 0.0F && extended.blue <= 1.0F &&
            extended.alpha == 0.7F,
        "active grading clamps the bounded working RGB output");

    negaflow::imaging::ColorGradingParameters red_zero{};
    red_zero.midtones.hue_degrees = 0.0F;
    red_zero.midtones.saturation = 0.6F;
    auto red_wrap = red_zero;
    red_wrap.midtones.hue_degrees = 360.0F;
    negaflow::core::Rgba32F zero_pixel{0.5F, 0.5F, 0.5F, 1.0F};
    auto wrap_pixel = zero_pixel;
    expect(
        negaflow::imaging::apply_color_grading(
            {&zero_pixel, 1U, 1U, 1U, 1U},
            {&zero_pixel, 1U, 1U, 1U, 1U},
            red_zero) == negaflow::core::KernelStatus::ok &&
            negaflow::imaging::apply_color_grading(
                {&wrap_pixel, 1U, 1U, 1U, 1U},
                {&wrap_pixel, 1U, 1U, 1U, 1U},
                red_wrap) == negaflow::core::KernelStatus::ok,
        "zero and 360 degree hue grades apply");
    expect_pixel_near(wrap_pixel, zero_pixel, "360 degree hue wraps to zero");

    negaflow::imaging::ColorGradingParameters low_pivot{};
    low_pivot.shadows.saturation = 1.0F;
    low_pivot.balance = -1.0F;
    auto high_pivot = low_pivot;
    high_pivot.balance = 1.0F;
    negaflow::core::Rgba32F low_pixel{0.5F, 0.5F, 0.5F, 1.0F};
    auto high_pixel = low_pixel;
    expect(
        negaflow::imaging::apply_color_grading(
            {&low_pixel, 1U, 1U, 1U, 1U},
            {&low_pixel, 1U, 1U, 1U, 1U},
            low_pivot) == negaflow::core::KernelStatus::ok &&
            negaflow::imaging::apply_color_grading(
                {&high_pixel, 1U, 1U, 1U, 1U},
                {&high_pixel, 1U, 1U, 1U, 1U},
                high_pivot) == negaflow::core::KernelStatus::ok &&
            (high_pixel.red - high_pixel.green) >
                (low_pixel.red - low_pixel.green) + 0.1F,
        "balance moves the shadow-to-highlight pivot");
}

void test_parameter_and_view_failures() {
    negaflow::imaging::ColorGradingParameters invalid{};
    invalid.highlights.hue_degrees = 360.1F;
    std::array<negaflow::core::Rgba32F, 2> pixels{{
        {0.2F, 0.3F, 0.4F, 1.0F},
        {0.5F, 0.6F, 0.7F, 1.0F},
    }};
    expect(!negaflow::imaging::valid_color_grading_parameters(invalid) &&
               negaflow::imaging::apply_color_grading(
                   {pixels.data(), pixels.size(), 2U, 1U, 2U},
                   {pixels.data(), pixels.size(), 2U, 1U, 2U},
                   invalid) == negaflow::core::KernelStatus::invalid_parameter,
           "hue values above the color-wheel contract are rejected");
    invalid = {};
    invalid.shadows.saturation = -0.01F;
    expect(!negaflow::imaging::valid_color_grading_parameters(invalid),
           "negative wheel saturation is rejected");
    invalid = {};
    invalid.blending = 1.01F;
    expect(!negaflow::imaging::valid_color_grading_parameters(invalid),
           "blending above one is rejected");
    invalid = {};
    invalid.balance = std::numeric_limits<float>::quiet_NaN();
    expect(!negaflow::imaging::valid_color_grading_parameters(invalid) &&
               negaflow::imaging::apply_color_grading(
                   {pixels.data(), pixels.size(), 2U, 1U, 2U},
                   {pixels.data(), pixels.size(), 2U, 1U, 2U},
                   invalid) ==
                   negaflow::core::KernelStatus::non_finite_parameter,
           "non-finite global controls are rejected");

    expect(
        negaflow::imaging::apply_color_grading(
            {pixels.data(), pixels.size(), 2U, 1U, 1U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            negaflow::fixtures::color_grading_parameters) ==
            negaflow::core::KernelStatus::invalid_stride,
        "invalid source stride is rejected");
    pixels[0].blue = std::numeric_limits<float>::infinity();
    expect(
        negaflow::imaging::apply_color_grading(
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            negaflow::fixtures::color_grading_parameters) ==
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
                negaflow::core::KernelStatus::ok,
        "manual point-curve mixer grading sequence succeeds");

    negaflow::imaging::WorkingToneAdjustParameters parameters{};
    parameters.point_curves = negaflow::fixtures::point_curve_parameters;
    parameters.color_mixer = negaflow::fixtures::color_mixer_parameters;
    parameters.color_grading = negaflow::fixtures::color_grading_parameters;
    const auto adjusted = negaflow::imaging::apply_working_tone_adjustments(
        std::move(source),
        parameters);
    expect(adjusted.status == negaflow::imaging::WorkingToneAdjustStatus::ok &&
               adjusted.info.point_curve_applied &&
               adjusted.info.color_mixer_applied &&
               adjusted.info.color_grading_applied,
           "working pipeline reports all three post-pipeline stages");
    if (adjusted.image.pixels.size() == manual.pixels.size()) {
        for (std::size_t index = 0U; index < manual.pixels.size(); ++index) {
            expect_pixel_near(
                adjusted.image.pixels[index],
                manual.pixels[index],
                "grading runs after point curve and mixer in the working pipeline");
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
    parameters.color_grading.midtones.luminance = -1.01F;
    const auto failed = negaflow::imaging::apply_working_tone_adjustments(
        std::move(rejected),
        parameters);
    expect(failed.status ==
                   negaflow::imaging::WorkingToneAdjustStatus::invalid_parameter &&
               failed.image.pixels.empty(),
           "invalid color grading controls publish no adjusted pixels");
}

}  // namespace

int main() {
    test_fixed_fixture_and_in_place_parity();
    test_identity_threshold_and_padding();
    test_region_controls_and_active_unit_domain();
    test_parameter_and_view_failures();
    test_pipeline_order_and_failure_publication();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"color_grading\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
