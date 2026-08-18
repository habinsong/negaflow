#include "texture_stage_test_support.h"

#include "negaflow/imaging/coreimage_gaussian.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace texture_stage_tests {

void test_identity_and_invalid_controls() {
    auto source = texture_patch();
    const auto original = source.pixels;
    const auto identity = negaflow::imaging::apply_texture_stage(source, {});
    expect(
        identity.status == negaflow::imaging::TextureStageStatus::ok &&
            !identity.info.applied && same_pixels(identity.image.pixels, original),
        "neutral texture controls are byte exact");

    negaflow::imaging::TextureStageParameters invalid{};
    invalid.clarity = std::numeric_limits<float>::quiet_NaN();
    const auto rejected = negaflow::imaging::apply_texture_stage(
        std::move(source),
        invalid);
    expect(
        rejected.status ==
                negaflow::imaging::TextureStageStatus::invalid_parameter &&
            rejected.image.pixels.empty(),
        "a non-finite texture control fails closed");
}

void test_grain_and_detail_controls() {
    const auto baseline = texture_patch();
    negaflow::imaging::TextureStageParameters grain{};
    grain.grain = 1.0F;
    const auto grain_result = negaflow::imaging::apply_texture_stage(
        baseline,
        grain);
    const auto grain_repeat = negaflow::imaging::apply_texture_stage(
        baseline,
        grain);
    expect(
        local_noise(grain_result.image) > local_noise(baseline) + 0.004F &&
            std::abs(mean_luma(grain_result.image) - mean_luma(baseline)) < 0.025F &&
            same_pixels(grain_result.image.pixels, grain_repeat.image.pixels),
        "grain adds deterministic zero-mean local texture");

    negaflow::imaging::TextureStageParameters sharp{};
    sharp.sharpness = 1.0F;
    const auto sharpened = negaflow::imaging::apply_texture_stage(
        baseline,
        sharp);
    negaflow::imaging::TextureStageParameters clarity_positive{};
    clarity_positive.clarity = 1.0F;
    const auto clarified = negaflow::imaging::apply_texture_stage(
        baseline,
        clarity_positive);
    negaflow::imaging::TextureStageParameters clarity_negative{};
    clarity_negative.clarity = -1.0F;
    const auto softened = negaflow::imaging::apply_texture_stage(
        baseline,
        clarity_negative);
    expect(mean_edge(sharpened.image) > mean_edge(baseline) + 0.015F,
           "sharpness increases edge contrast");
    expect(mean_edge(clarified.image) > mean_edge(baseline) + 0.006F,
           "positive clarity increases local contrast");
    expect(mean_edge(softened.image) < mean_edge(baseline) - 0.006F,
           "negative clarity softens local contrast");
}

void test_halation_and_vignette() {
    const auto bright = halation_patch();
    negaflow::imaging::TextureStageParameters halation{};
    halation.halation = 1.0F;
    const auto glow = negaflow::imaging::apply_texture_stage(bright, halation);
    expect(
        mean_chroma(glow.image) > mean_chroma(bright) + 0.001F &&
            mean_luma(glow.image) > mean_luma(bright) + 0.0005F,
        "halation adds a warm highlight glow");

    auto dark = texture_patch(16U, 16U);
    for (auto& pixel : dark.pixels) {
        pixel = {0.02F, 0.02F, 0.02F, 1.0F};
    }
    const auto dark_glow = negaflow::imaging::apply_texture_stage(dark, halation);
    expect(mean_luma(dark_glow.image) < 0.04F,
           "halation does not lift a dark frame");

    const auto baseline = texture_patch();
    negaflow::imaging::TextureStageParameters darken{};
    darken.vignette = 1.0F;
    const auto darkened = negaflow::imaging::apply_texture_stage(baseline, darken);
    negaflow::imaging::TextureStageParameters lift{};
    lift.vignette = -1.0F;
    const auto lifted = negaflow::imaging::apply_texture_stage(baseline, lift);
    const float baseline_corner = region_mean(baseline, 0U, 0U, 12U, 12U);
    const float baseline_center = region_mean(baseline, 26U, 18U, 12U, 12U);
    expect(
        region_mean(darkened.image, 0U, 0U, 12U, 12U) <
                baseline_corner - 0.015F &&
            std::abs(
                region_mean(darkened.image, 26U, 18U, 12U, 12U) -
                baseline_center) < 0.010F,
        "positive vignette darkens edges while preserving the center");
    expect(
        region_mean(lifted.image, 0U, 0U, 12U, 12U) >
                baseline_corner + 0.025F &&
            std::abs(
                region_mean(lifted.image, 26U, 18U, 12U, 12U) -
                baseline_center) < 0.010F,
        "negative vignette lifts edges while preserving the center");
}

void test_output_sharpening() {
    const auto baseline = texture_patch();
    const auto identity = negaflow::imaging::apply_output_sharpening(baseline, {});
    expect(
        identity.status == negaflow::imaging::TextureStageStatus::ok &&
            !identity.info.applied &&
            same_pixels(identity.image.pixels, baseline.pixels),
        "zero output sharpening preserves the developed pixels exactly");

    negaflow::imaging::OutputSharpeningParameters screen{};
    screen.strength = 0.80F;
    screen.medium = negaflow::imaging::OutputSharpeningMedium::screen;
    screen.dpi = 144;
    const auto sharpened = negaflow::imaging::apply_output_sharpening(
        baseline,
        screen);
    const auto repeat = negaflow::imaging::apply_output_sharpening(
        baseline,
        screen);
    expect(
        sharpened.status == negaflow::imaging::TextureStageStatus::ok &&
            sharpened.info.applied &&
            std::abs(mean_edge(sharpened.image) - mean_edge(baseline)) > 0.0001F &&
            same_pixels(sharpened.image.pixels, repeat.image.pixels),
        "screen output sharpening is deterministic and changes final edge contrast");

    auto high_dpi = screen;
    high_dpi.dpi = 288;
    const auto high_dpi_result = negaflow::imaging::apply_output_sharpening(
        baseline,
        high_dpi);
    auto matte = screen;
    matte.medium = negaflow::imaging::OutputSharpeningMedium::matte_paper;
    matte.dpi = 300;
    const auto matte_result = negaflow::imaging::apply_output_sharpening(
        baseline,
        matte);
    expect(
        high_dpi_result.info.radius > sharpened.info.radius &&
            std::abs(high_dpi_result.info.intensity - sharpened.info.intensity) <
                0.00001F &&
            matte_result.info.radius > sharpened.info.radius &&
            matte_result.info.intensity > sharpened.info.intensity,
        "DPI and medium select the macOS-compatible output-sharpening parameters");

    auto invalid = screen;
    invalid.strength = std::numeric_limits<float>::quiet_NaN();
    const auto rejected = negaflow::imaging::apply_output_sharpening(
        baseline,
        invalid);
    expect(
        rejected.status == negaflow::imaging::TextureStageStatus::invalid_parameter &&
            rejected.image.pixels.empty(),
        "invalid output sharpening controls fail closed");
}

}  // namespace texture_stage_tests
