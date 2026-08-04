#include "negaflow/imaging/tone_curve_measurement.h"
#include "negaflow/imaging/tone_mapping.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "tone_mapping_fixture.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

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
        negaflow::fixtures::tone_mapping_absolute_tolerance,
    const float relative_tolerance =
        negaflow::fixtures::tone_mapping_relative_tolerance) noexcept {
    const float difference = std::abs(actual - expected);
    const float scale = std::max(std::abs(actual), std::abs(expected));
    return difference <= absolute_tolerance + (relative_tolerance * scale);
}

void expect_pixel_near(
    const negaflow::core::Rgba32F actual,
    const negaflow::core::Rgba32F expected,
    const char* const message) {
    expect(
        nearly_equal(actual.red, expected.red) &&
            nearly_equal(actual.green, expected.green) &&
            nearly_equal(actual.blue, expected.blue) && actual.alpha == expected.alpha,
        message);
}

[[nodiscard]] negaflow::imaging::WorkingImage make_fixture_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 3U;
    image.height = 2U;
    image.stride_pixels = 3U;
    image.pixels.assign(
        negaflow::fixtures::tone_mapping_input.begin(),
        negaflow::fixtures::tone_mapping_input.end());
    return image;
}

void test_fixed_scalar_pipeline_fixture() {
    const auto adjusted = negaflow::imaging::apply_working_tone_adjustments(
        make_fixture_image(),
        negaflow::fixtures::tone_mapping_parameters);
    expect(
        adjusted.status == negaflow::imaging::WorkingToneAdjustStatus::ok,
        "combined tone pipeline succeeds");
    expect(adjusted.info.exposure_applied, "combined fixture applies exposure");
    expect(adjusted.info.basic_tone_applied, "combined fixture applies basic tone");
    expect(adjusted.info.parametric_curve_applied, "combined fixture applies curve");
    expect(
        adjusted.info.measurement.info.sampling_mode ==
            negaflow::imaging::ToneCurveSamplingMode::fixed_fallback,
        "small fixture selects the macOS fixed curve bands");
    expect(
        adjusted.image.pixels.size() == negaflow::fixtures::tone_mapping_expected.size(),
        "combined fixture preserves pixel count");
    if (adjusted.image.pixels.size() == negaflow::fixtures::tone_mapping_expected.size()) {
        for (std::size_t index = 0U; index < adjusted.image.pixels.size(); ++index) {
            expect_pixel_near(
                adjusted.image.pixels[index],
                negaflow::fixtures::tone_mapping_expected[index],
                "combined Float32 fixture matches the macOS formula transcription");
        }
    }
}

void test_thresholds_noop_and_user_bounds() {
    negaflow::imaging::WorkingImage source{};
    source.width = 1U;
    source.height = 1U;
    source.stride_pixels = 1U;
    source.pixels = {{0.125F, 0.25F, 0.5F, 0.75F}};

    negaflow::imaging::WorkingToneAdjustParameters threshold{};
    threshold.exposure_stops = 1.0e-3F;
    threshold.basic.contrast = -1.0e-3F;
    threshold.curve.highlights = 1.0e-3F;
    const auto unchanged = negaflow::imaging::apply_working_tone_adjustments(
        source,
        threshold);
    expect(unchanged.status == negaflow::imaging::WorkingToneAdjustStatus::ok, "threshold no-op succeeds");
    expect(!unchanged.info.exposure_applied, "exposure threshold is a no-op");
    expect(!unchanged.info.basic_tone_applied, "basic threshold is a no-op");
    expect(!unchanged.info.parametric_curve_applied, "curve threshold is a no-op");
    expect(!unchanged.info.point_curve_applied, "empty point curves are a no-op");
    expect(!unchanged.info.color_mixer_applied, "empty color mixer is a no-op");
    expect_pixel_near(unchanged.image.pixels[0], source.pixels[0], "threshold no-op is bit exact");

    negaflow::imaging::WorkingToneAdjustParameters exposure{};
    exposure.exposure_stops = 2.0F;
    const auto exposed = negaflow::imaging::apply_working_tone_adjustments(source, exposure);
    expect(exposed.status == negaflow::imaging::WorkingToneAdjustStatus::ok, "bounded exposure succeeds");
    expect(exposed.info.exposure_applied, "bounded exposure is reported");
    expect_pixel_near(
        exposed.image.pixels[0],
        {0.5F, 1.0F, 2.0F, 0.75F},
        "exposure remains scene-linear and extended range");

    exposure.exposure_stops = 5.01F;
    const auto excessive = negaflow::imaging::apply_working_tone_adjustments(source, exposure);
    expect(
        excessive.status == negaflow::imaging::WorkingToneAdjustStatus::invalid_parameter &&
            excessive.image.pixels.empty(),
        "exposure outside the UI contract publishes no pixels");

    negaflow::imaging::WorkingToneAdjustParameters invalid_tone{};
    invalid_tone.curve.shadows = -1.01F;
    const auto invalid = negaflow::imaging::apply_working_tone_adjustments(source, invalid_tone);
    expect(
        invalid.status == negaflow::imaging::WorkingToneAdjustStatus::invalid_parameter &&
            invalid.image.pixels.empty(),
        "curve outside the UI contract publishes no pixels");
}

void test_basic_tone_black_anchor_and_stride() {
    const negaflow::core::Rgba32F padding{91.0F, 92.0F, 93.0F, 0.0F};
    std::array<negaflow::core::Rgba32F, 4> input{{
        {0.0F, 0.0F, 0.0F, 1.0F},
        {0.0001F, 0.0001F, 0.0001F, 0.5F},
        padding,
        padding,
    }};
    std::array<negaflow::core::Rgba32F, 4> output{};
    output[2] = padding;
    output[3] = padding;
    negaflow::imaging::BasicToneParameters parameters{};
    parameters.contrast = -1.0F;
    const auto status = negaflow::imaging::apply_basic_tone(
        {input.data(), input.size(), 2U, 1U, 4U},
        {output.data(), output.size(), 2U, 1U, 4U},
        parameters);
    expect(status == negaflow::core::KernelStatus::ok, "negative contrast succeeds");
    expect(output[0].red == 0.0F && output[0].green == 0.0F && output[0].blue == 0.0F,
           "negative contrast anchors absolute black");
    expect(output[1].red < 0.001F, "negative contrast does not wash out near-black");
    expect(output[1].alpha == 0.5F, "basic tone preserves alpha");
    expect(output[2].red == padding.red && output[3].blue == padding.blue,
           "basic tone does not write stride padding");

    parameters.contrast = std::numeric_limits<float>::quiet_NaN();
    expect(
        negaflow::imaging::apply_basic_tone(
            {input.data(), input.size(), 2U, 1U, 4U},
            {output.data(), output.size(), 2U, 1U, 4U},
            parameters) == negaflow::core::KernelStatus::non_finite_parameter,
        "basic tone rejects non-finite parameters");
}

void test_curve_measurement_contract() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 64U;
    std::vector<negaflow::core::Rgba32F> pixels(
        static_cast<std::size_t>(width) * height,
        {0.25F, 0.25F, 0.25F, 1.0F});
    for (std::uint32_t row = 0U; row < height; ++row) {
        for (std::uint32_t column = 0U; column < width; ++column) {
            if (row < 2U || row >= 62U || column < 2U || column >= 62U) {
                pixels[static_cast<std::size_t>(row) * width + column] =
                    {1.0F, 1.0F, 1.0F, 1.0F};
            }
        }
    }
    const negaflow::core::ConstImageView view{
        pixels.data(), pixels.size(), width, height, width};
    const auto measured = negaflow::imaging::measure_parametric_tone_curve_bands(view);
    expect(measured.status == negaflow::imaging::ToneCurveMeasurementStatus::ok,
           "portable curve measurement succeeds");
    expect(
        measured.info.sampling_mode ==
            negaflow::imaging::ToneCurveSamplingMode::portable_area_v1,
        "portable curve measurement reports its raster algorithm");
    expect(measured.info.target_width == width && measured.info.target_height == height,
           "measurement preserves a 64-pixel source raster");
    expect(measured.info.sampled_luma_count == 3'600U,
           "measurement excludes the four-percent border");
    expect(measured.info.peak_temporary_bytes == 3'600U * sizeof(double),
           "measurement reports bounded temporary storage");
    const auto bands = measured.info.bands;
    expect(nearly_equal(bands.shadow_low, 0.230F), "p10 shadow lower margin");
    expect(nearly_equal(bands.shadow_high, 0.275F), "p35 minimum spacing");
    expect(nearly_equal(bands.dark_low, 0.275F) && nearly_equal(bands.dark_high, 0.300F),
           "dark band derives from p35 and p65");
    expect(nearly_equal(bands.light_low, 0.300F) && nearly_equal(bands.light_high, 0.325F),
           "light band derives from p65 and p90");
    expect(nearly_equal(bands.highlight_low, 0.300F) &&
               nearly_equal(bands.highlight_high, 0.355F),
           "highlight band includes the upper margin");

    std::array<negaflow::core::Rgba32F, 64> small{};
    const auto fallback = negaflow::imaging::measure_parametric_tone_curve_bands(
        {small.data(), small.size(), 8U, 8U, 8U});
    expect(fallback.status == negaflow::imaging::ToneCurveMeasurementStatus::ok &&
               fallback.info.sampling_mode ==
                   negaflow::imaging::ToneCurveSamplingMode::fixed_fallback,
           "eight-pixel extent uses fixed macOS bands");

    const auto limited = negaflow::imaging::measure_parametric_tone_curve_bands(
        view,
        {100U});
    expect(limited.status == negaflow::imaging::ToneCurveMeasurementStatus::sample_limit_exceeded,
           "measurement honors the memory-work limit");

    const auto malformed = negaflow::imaging::measure_parametric_tone_curve_bands(
        {pixels.data(), pixels.size(), width, height, width - 1U});
    expect(malformed.status == negaflow::imaging::ToneCurveMeasurementStatus::invalid_input &&
               malformed.kernel_status == negaflow::core::KernelStatus::invalid_stride,
           "measurement reports malformed image layout");
}

void test_curve_black_anchor_and_measurement_failure() {
    std::array<negaflow::core::Rgba32F, 2> input{{
        {0.0F, 0.0F, 0.0F, 1.0F},
        {0.02F, 0.02F, 0.02F, 0.25F},
    }};
    std::array<negaflow::core::Rgba32F, 2> output{};
    negaflow::imaging::ParametricToneCurveParameters curve{};
    curve.shadows = 1.0F;
    const auto status = negaflow::imaging::apply_parametric_tone_curve(
        {input.data(), input.size(), 2U, 1U, 2U},
        {output.data(), output.size(), 2U, 1U, 2U},
        curve,
        negaflow::imaging::fallback_parametric_tone_curve_bands());
    expect(status == negaflow::core::KernelStatus::ok, "shadow curve succeeds");
    expect(output[0].red == 0.0F, "shadow curve anchors absolute black");
    expect(output[1].red > input[1].red, "shadow curve lifts visible shadows");
    expect(output[1].alpha == input[1].alpha, "parametric curve preserves alpha");

    negaflow::imaging::WorkingImage large{};
    large.width = 64U;
    large.height = 64U;
    large.stride_pixels = 64U;
    large.pixels.assign(64U * 64U, {0.25F, 0.25F, 0.25F, 1.0F});
    negaflow::imaging::WorkingToneAdjustParameters parameters{};
    parameters.curve.lights = 0.5F;
    const auto failed = negaflow::imaging::apply_working_tone_adjustments(
        std::move(large),
        parameters,
        {100U});
    expect(failed.status == negaflow::imaging::WorkingToneAdjustStatus::measurement_failed &&
               failed.info.measurement.status ==
                   negaflow::imaging::ToneCurveMeasurementStatus::sample_limit_exceeded &&
               failed.image.pixels.empty(),
           "failed curve measurement publishes no adjusted pixels");
}

}  // namespace

int main() {
    test_fixed_scalar_pipeline_fixture();
    test_thresholds_noop_and_user_bounds();
    test_basic_tone_black_anchor_and_stride();
    test_curve_measurement_contract();
    test_curve_black_anchor_and_measurement_failure();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"tone_pipeline\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
