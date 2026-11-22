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

// sRGB 인코딩 값의 색상(도)입니다. 사용자 슬라이더 시험이 "눈에 보이는 색상환" 위치를 봅니다.
[[nodiscard]] float encoded_hue_degrees(const negaflow::core::Rgba32F pixel) noexcept {
    const auto encode = [](const float linear) {
        const float value = std::clamp(linear, 0.0F, 1.0F);
        return value <= 0.0031308F ? value * 12.92F
                                   : (1.055F * std::pow(value, 1.0F / 2.4F)) - 0.055F;
    };
    const float red = encode(pixel.red);
    const float green = encode(pixel.green);
    const float blue = encode(pixel.blue);
    const float maximum = std::max(red, std::max(green, blue));
    const float minimum = std::min(red, std::min(green, blue));
    const float difference = maximum - minimum;
    if (difference <= 1.0e-5F) {
        return 0.0F;
    }
    float hue = 0.0F;
    if (maximum == red) {
        hue = (green - blue) / difference;
        if (green < blue) {
            hue += 6.0F;
        }
    } else if (maximum == green) {
        hue = ((blue - red) / difference) + 2.0F;
    } else {
        hue = ((red - green) / difference) + 4.0F;
    }
    return hue * 60.0F;
}

// 사용자 슬라이더는 sRGB 인코딩 값에서 HSL 을 계산합니다. sRGB 주황(1, 0.5, 0)은 30° 에
// 있고, Orange 밴드 색상 +1 은 이웃 밴드와의 가중 평균만큼(약 16.6°) 밉니다. 선형 값에서
// 계산하던 앞 판은 같은 화소를 12.8° 로 읽어 빨강 쪽에 걸었습니다.
void test_perceptual_hue_wheel() {
    const negaflow::core::Rgba32F orange{1.0F, 0.21404114F, 0.0F, 1.0F};
    negaflow::imaging::ColorMixerParameters parameters{};
    parameters.hue[1] = 1.0F;  // Orange
    std::array<negaflow::core::Rgba32F, 1U> output{};
    expect(
        negaflow::imaging::apply_color_mixer(
            {&orange, 1U, 1U, 1U, 1U}, {output.data(), 1U, 1U, 1U, 1U}, parameters) ==
            negaflow::core::KernelStatus::ok,
        "perceptual mixer applies");
    const float hue = encoded_hue_degrees(output[0]);
    expect(hue > 44.0F && hue < 49.0F, "orange band moves sRGB orange from 30 to about 46.6 degrees");

    parameters.perceptual = false;
    expect(
        negaflow::imaging::apply_color_mixer(
            {&orange, 1U, 1U, 1U, 1U}, {output.data(), 1U, 1U, 1U, 1U}, parameters) ==
            negaflow::core::KernelStatus::ok,
        "linear preset mixer applies");
    expect(
        std::abs(encoded_hue_degrees(output[0]) - hue) > 2.0F,
        "the preset path keeps its designed linear behaviour");
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
    // 사용자 슬라이더 경로는 [0,1] 안에서 보정하고 밖으로 나간 몫(−1, +1)을 다시 더합니다 —
    // 광색역 음수와 1.0 넘는 하이라이트를 버리지 않습니다(macOS `colorMixerHSL`).
    expect(pixels[1].red <= 0.0F && pixels[1].red >= -1.0F &&
               pixels[1].green >= 0.0F && pixels[1].green <= 1.0F &&
               pixels[1].blue >= 1.0F && pixels[1].blue <= 2.0F &&
               pixels[1].alpha == 0.7F,
           "active slider mixer keeps the part outside the unit cube");

    // 프리셋 경로는 설계된 대로 [0,1] 안에서만 답합니다.
    negaflow::imaging::ColorMixerParameters preset = active;
    preset.perceptual = false;
    negaflow::core::Rgba32F extended{-1.0F, 0.5F, 2.0F, 0.7F};
    expect(
        negaflow::imaging::apply_color_mixer(
            {&extended, 1U, 1U, 1U, 1U}, {&extended, 1U, 1U, 1U, 1U}, preset) ==
                negaflow::core::KernelStatus::ok &&
            extended.red >= 0.0F && extended.red <= 1.0F &&
            extended.green >= 0.0F && extended.green <= 1.0F &&
            extended.blue >= 0.0F && extended.blue <= 1.0F &&
            extended.alpha == 0.7F,
        "preset mixer uses the bounded working RGB domain");

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
    test_perceptual_hue_wheel();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"color_mixer\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
