#include "negaflow/imaging/color_mixer.h"
#include "negaflow/imaging/point_curve.h"
#include "negaflow/imaging/working_tone_adjuster.h"
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
        negaflow::fixtures::color_mixer_absolute_tolerance,
    const float relative_tolerance =
        negaflow::fixtures::color_mixer_relative_tolerance) noexcept {
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
               negaflow::fixtures::color_mixer_input.size()> output{};
    expect(
        negaflow::imaging::apply_color_mixer(
            {negaflow::fixtures::color_mixer_input.data(),
             negaflow::fixtures::color_mixer_input.size(),
             4U,
             3U,
             4U},
            {output.data(), output.size(), 4U, 3U, 4U},
            negaflow::fixtures::color_mixer_parameters) ==
            negaflow::core::KernelStatus::ok,
        "fixed color mixer applies");
    for (std::size_t index = 0U; index < output.size(); ++index) {
        expect_pixel_near(
            output[index],
            negaflow::fixtures::color_mixer_expected[index],
            "fixed color mixer pixel matches independent Float32 calculation");
    }

    auto in_place = negaflow::fixtures::color_mixer_input;
    expect(
        negaflow::imaging::apply_color_mixer(
            {in_place.data(), in_place.size(), 4U, 3U, 4U},
            {in_place.data(), in_place.size(), 4U, 3U, 4U},
            negaflow::fixtures::color_mixer_parameters) ==
            negaflow::core::KernelStatus::ok,
        "in-place color mixer applies");
    for (std::size_t index = 0U; index < output.size(); ++index) {
        expect_pixel_near(
            in_place[index],
            output[index],
            "in-place color mixer matches separate output");
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
    std::array<negaflow::core::Rgba32F, 4> output{{padding, padding, padding, padding}};
    negaflow::imaging::ColorMixerParameters identity{};
    const auto red_index = static_cast<std::size_t>(
        negaflow::imaging::ColorMixerBand::red);
    identity.hue[red_index] = 0.000099F;
    expect(!negaflow::imaging::has_color_mixer_change(identity),
           "values below the macOS identity threshold are a no-op");
    expect(
        negaflow::imaging::apply_color_mixer(
            {input.data(), input.size(), 2U, 1U, 4U},
            {output.data(), output.size(), 2U, 1U, 4U},
            identity) == negaflow::core::KernelStatus::ok,
        "identity color mixer succeeds");
    expect(output[0].red == input[0].red && output[0].green == input[0].green &&
               output[0].blue == input[0].blue && output[0].alpha == input[0].alpha &&
               output[1].red == input[1].red && output[1].blue == input[1].blue,
           "identity color mixer preserves extended pixels bit exactly");
    expect(output[2].red == padding.red && output[3].blue == padding.blue,
           "identity color mixer does not write stride padding");

    identity.hue[red_index] = 0.0001F;
    expect(negaflow::imaging::has_color_mixer_change(identity),
           "the exact macOS threshold activates the mixer");
}

void test_gray_gate_and_active_unit_domain() {
    negaflow::imaging::ColorMixerParameters active{};
    active.hue.fill(1.0F);
    active.saturation.fill(1.0F);
    active.luminance.fill(1.0F);
    std::array<negaflow::core::Rgba32F, 2> pixels{{
        {0.4F, 0.4F, 0.4F, 0.3F},
        {-1.0F, 0.5F, 2.0F, 0.7F},
    }};
    expect(
        negaflow::imaging::apply_color_mixer(
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            active) == negaflow::core::KernelStatus::ok,
        "active all-band mixer succeeds");
    expect(pixels[0].red == 0.4F && pixels[0].green == 0.4F &&
               pixels[0].blue == 0.4F && pixels[0].alpha == 0.3F,
           "achromatic gate protects neutral gray and alpha");
    expect(pixels[1].red >= 0.0F && pixels[1].red <= 1.0F &&
               pixels[1].green >= 0.0F && pixels[1].green <= 1.0F &&
               pixels[1].blue >= 0.0F && pixels[1].blue <= 1.0F &&
               pixels[1].alpha == 0.7F,
           "active mixer uses the bounded working RGB domain");

    negaflow::imaging::ColorMixerParameters red_saturation{};
    red_saturation.saturation[static_cast<std::size_t>(
        negaflow::imaging::ColorMixerBand::red)] = 1.0F;
    negaflow::core::Rgba32F red_patch{0.62F, 0.30F, 0.30F, 1.0F};
    const float input_chroma = red_patch.red - red_patch.green;
    expect(
        negaflow::imaging::apply_color_mixer(
            {&red_patch, 1U, 1U, 1U, 1U},
            {&red_patch, 1U, 1U, 1U, 1U},
            red_saturation) == negaflow::core::KernelStatus::ok &&
            (red_patch.red - std::min(red_patch.green, red_patch.blue)) >
                input_chroma + 0.01F,
        "red saturation control increases red-patch chroma");
}

void test_parameter_and_view_failures() {
    negaflow::imaging::ColorMixerParameters invalid{};
    invalid.hue[0U] = 1.01F;
    std::array<negaflow::core::Rgba32F, 2> pixels{{
        {0.2F, 0.3F, 0.4F, 1.0F},
        {0.5F, 0.6F, 0.7F, 1.0F},
    }};
    expect(!negaflow::imaging::valid_color_mixer_parameters(invalid) &&
               negaflow::imaging::apply_color_mixer(
                   {pixels.data(), pixels.size(), 2U, 1U, 2U},
                   {pixels.data(), pixels.size(), 2U, 1U, 2U},
                   invalid) == negaflow::core::KernelStatus::invalid_parameter,
           "values above the UI contract are rejected");
    invalid = {};
    invalid.saturation[2U] = std::numeric_limits<float>::quiet_NaN();
    expect(!negaflow::imaging::valid_color_mixer_parameters(invalid) &&
               negaflow::imaging::apply_color_mixer(
                   {pixels.data(), pixels.size(), 2U, 1U, 2U},
                   {pixels.data(), pixels.size(), 2U, 1U, 2U},
                   invalid) ==
                   negaflow::core::KernelStatus::non_finite_parameter,
           "non-finite controls are rejected");

    expect(
        negaflow::imaging::apply_color_mixer(
            {pixels.data(), pixels.size(), 2U, 1U, 1U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            negaflow::fixtures::color_mixer_parameters) ==
            negaflow::core::KernelStatus::invalid_stride,
        "invalid source stride is rejected");
    pixels[0].blue = std::numeric_limits<float>::infinity();
    expect(
        negaflow::imaging::apply_color_mixer(
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            negaflow::fixtures::color_mixer_parameters) ==
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
    expect(
        negaflow::imaging::apply_point_curves(
            {manual.pixels.data(), manual.pixels.size(), 3U, 2U, 3U},
            {manual.pixels.data(), manual.pixels.size(), 3U, 2U, 3U},
            negaflow::fixtures::point_curve_parameters) ==
                negaflow::core::KernelStatus::ok &&
            negaflow::imaging::apply_color_mixer(
                {manual.pixels.data(), manual.pixels.size(), 3U, 2U, 3U},
                {manual.pixels.data(), manual.pixels.size(), 3U, 2U, 3U},
                negaflow::fixtures::color_mixer_parameters) ==
                negaflow::core::KernelStatus::ok,
        "manual point-curve then color-mixer sequence succeeds");

    negaflow::imaging::WorkingToneAdjustParameters parameters{};
    parameters.point_curves = negaflow::fixtures::point_curve_parameters;
    parameters.color_mixer = negaflow::fixtures::color_mixer_parameters;
    const auto adjusted = negaflow::imaging::apply_working_tone_adjustments(
        std::move(source),
        parameters);
    expect(adjusted.status == negaflow::imaging::WorkingToneAdjustStatus::ok &&
               adjusted.info.point_curve_applied &&
               adjusted.info.color_mixer_applied,
           "working pipeline reports both post-pipeline stages");
    if (adjusted.image.pixels.size() == manual.pixels.size()) {
        for (std::size_t index = 0U; index < manual.pixels.size(); ++index) {
            expect_pixel_near(
                adjusted.image.pixels[index],
                manual.pixels[index],
                "color mixer runs after point curve in the working pipeline");
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
    parameters.color_mixer.luminance[0U] = -1.01F;
    const auto failed = negaflow::imaging::apply_working_tone_adjustments(
        std::move(rejected),
        parameters);
    expect(failed.status == negaflow::imaging::WorkingToneAdjustStatus::invalid_parameter &&
               failed.image.pixels.empty(),
           "invalid color mixer controls publish no adjusted pixels");
}

}  // namespace

int main() {
    test_fixed_fixture_and_in_place_parity();
    test_identity_threshold_and_padding();
    test_gray_gate_and_active_unit_domain();
    test_parameter_and_view_failures();
    test_pipeline_order_and_failure_publication();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"color_mixer\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
