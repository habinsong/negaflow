#include "grain_mend_test_support.h"

#include "grain_mend_detector.h"
#include "grain_mend_resample.h"
#include "grain_mend_stitch.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace grain_mend_tests {

void test_dense_chromatic_grain_field_is_not_repaired() {
    auto source = make_uniform_image(128U, 128U);
    for (std::uint32_t row = 0U; row < 3U; ++row) {
        for (std::uint32_t column = 0U; column < 4U; ++column) {
            const std::uint32_t x = 46U + column * 10U;
            const std::uint32_t y = 48U + row * 10U;
            source.pixels[static_cast<std::size_t>(y) * source.width + x].blue =
                0.95F;
        }
    }
    const auto original = source.pixels;
    const auto result = negaflow::imaging::apply_grain_mend(
        std::move(source), {1.0});
    expect(
        result.status == negaflow::imaging::GrainMendStatus::ok &&
            !result.info.applied && result.info.candidate_pixels == 0U &&
            same_pixels(result.image.pixels, original),
        "a dense field of tiny chromatic responses is protected as grain");
}

void test_wide_highlight_and_dark_structure_are_protected() {
    auto wide_highlight = make_clean_image(96U, 48U);
    for (std::uint32_t y = 20U; y < 30U; ++y) {
        for (std::uint32_t x = 18U; x < 78U; ++x) {
            wide_highlight.pixels[static_cast<std::size_t>(y) * wide_highlight.width + x] =
                {0.92F, 0.92F, 0.92F, 1.0F};
        }
    }
    const auto highlight_original = wide_highlight.pixels;
    const auto highlight_result = negaflow::imaging::apply_grain_mend(
        std::move(wide_highlight), {1.0});
    if (highlight_result.info.applied) {
        std::cerr << "diagnostic wide-highlight candidates="
                  << highlight_result.info.candidate_pixels
                  << " repaired=" << highlight_result.info.repaired_pixels << '\n';
    }
    expect(
        highlight_result.status == negaflow::imaging::GrainMendStatus::ok &&
            !highlight_result.info.applied &&
            same_pixels(highlight_result.image.pixels, highlight_original),
        "a wide highlight structure is not mistaken for a scratch");

    auto dark_structure = make_clean_image(96U, 48U);
    for (std::uint32_t y = 12U; y < 36U; ++y) {
        for (std::uint32_t x = 18U; x < 78U; ++x) {
            dark_structure.pixels[static_cast<std::size_t>(y) * dark_structure.width + x] =
                {0.08F, 0.09F, 0.10F, 1.0F};
        }
    }
    const auto dark_original = dark_structure.pixels;
    const auto dark_result = negaflow::imaging::apply_grain_mend(
        std::move(dark_structure), {1.0});
    if (dark_result.info.applied) {
        std::cerr << "diagnostic dark-structure candidates="
                  << dark_result.info.candidate_pixels
                  << " repaired=" << dark_result.info.repaired_pixels << '\n';
    }
    expect(
        dark_result.status == negaflow::imaging::GrainMendStatus::ok &&
            !dark_result.info.applied &&
            same_pixels(dark_result.image.pixels, dark_original),
        "a broad dark structural edge is not mistaken for a defect");
}

void test_large_frame_lanczos_detection_and_affine_mask() {
    constexpr std::uint32_t width = 3600U;
    constexpr std::uint32_t height = 129U;
    constexpr std::uint32_t scratch_x = 1800U;
    const auto clean = make_uniform_image(width, height);
    auto damaged = clean;
    for (std::uint32_t y = 4U; y < 124U; ++y) {
        damaged.pixels[static_cast<std::size_t>(y) * width + scratch_x] =
            {0.95F, 0.95F, 0.95F, 1.0F};
    }
    float before = 0.0F;
    for (std::uint32_t y = 4U; y < 124U; ++y) {
        const std::size_t index =
            static_cast<std::size_t>(y) * width + scratch_x;
        before += pixel_error(damaged.pixels[index], clean.pixels[index]);
    }

    const auto result = negaflow::imaging::apply_grain_mend(
        std::move(damaged), {1.0});
    float after = 0.0F;
    if (result.status == negaflow::imaging::GrainMendStatus::ok) {
        for (std::uint32_t y = 4U; y < 124U; ++y) {
            const std::size_t index =
                static_cast<std::size_t>(y) * width + scratch_x;
            after += pixel_error(result.image.pixels[index], clean.pixels[index]);
        }
    }
    if (!(result.status == negaflow::imaging::GrainMendStatus::ok &&
          result.info.applied && after < before * 0.45F)) {
        std::cerr << "diagnostic large-frame before=" << before
                  << " after=" << after
                  << " detection=" << result.info.detection_width << 'x'
                  << result.info.detection_height
                  << " candidates=" << result.info.candidate_pixels
                  << " repaired=" << result.info.repaired_pixels << '\n';
    }
    expect(
        result.status == negaflow::imaging::GrainMendStatus::ok &&
            result.info.detection_width == 1800U &&
            result.info.detection_height == 65U &&
            result.info.applied && after < before * 0.45F,
        "a 3600px frame uses bounded Lanczos detection and repairs its scratch");

    const std::vector<std::uint8_t> mask{0U, 1U, 0U, 0U};
    const float quarter =
        negaflow::imaging::grain_mend_detail::sample_transformed_mask(
            mask, 4U, 1U, 8U, 1U, 1U, 0U);
    const float three_quarters =
        negaflow::imaging::grain_mend_detail::sample_transformed_mask(
            mask, 4U, 1U, 8U, 1U, 2U, 0U);
    expect(
        std::abs(quarter - 0.25F) <= 1.0e-6F &&
            std::abs(three_quarters - 0.75F) <= 1.0e-6F,
        "an enlarged defect mask carries bilinear boundary blend weights");

    const std::vector<std::uint8_t> corner_mask{1U, 0U, 0U, 0U};
    const float transparent_edge =
        negaflow::imaging::grain_mend_detail::sample_transformed_mask(
            corner_mask, 2U, 2U, 4U, 4U, 0U, 0U);
    const float two_axis_falloff =
        negaflow::imaging::grain_mend_detail::sample_transformed_mask(
            corner_mask, 2U, 2U, 4U, 4U, 2U, 2U);
    expect(
        std::abs(transparent_edge - 0.5625F) <= 1.0e-6F &&
            std::abs(two_axis_falloff - 0.0625F) <= 1.0e-6F,
        "a 2D enlarged mask uses transparent-black affine boundaries");
}

void test_rounded_short_axis_keeps_the_uniform_lanczos_scale() {
    constexpr std::uint32_t width = 3600U;
    constexpr std::uint32_t height = 9U;
    constexpr std::array<float, height> pattern{
        0.10F, 0.16F, 0.29F, 0.44F, 0.21F, 0.73F, 0.35F, 0.57F, 0.88F,
    };
    auto source = make_uniform_image(width, height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            auto& pixel = source.pixels[static_cast<std::size_t>(y) * width + x];
            pixel.red = pattern[std::min<std::uint32_t>(x, height - 1U)];
            pixel.green = pattern[y];
        }
    }

    std::array<std::vector<float>, 3U> channels{};
    negaflow::imaging::grain_mend_detail::render_detection_rgb(
        source, 1800U, 5U, channels);
    bool same_phase = true;
    for (std::uint32_t output = 0U; output < 5U; ++output) {
        const float horizontal = channels[0][output];
        const float vertical = channels[1][
            static_cast<std::size_t>(output) * 1800U];
        same_phase = same_phase && std::abs(horizontal - vertical) <= 1.0e-6F;
    }
    expect(
        same_phase,
        "a rounded short axis retains the long-axis Lanczos scale and phase");
}

void test_strength_zero_is_bit_exact_and_partial_strength_blends() {
    auto source = make_clean_image();
    source.pixels[30U * source.width + 30U] = {0.98F, 0.98F, 0.98F, 0.75F};
    const auto original = source.pixels;
    const auto identity = negaflow::imaging::apply_grain_mend(source, {0.0});
    expect(
        identity.status == negaflow::imaging::GrainMendStatus::ok &&
            !identity.info.applied && same_pixels(identity.image.pixels, original),
        "strength zero is a byte-exact no-op");

    const auto half = negaflow::imaging::apply_grain_mend(source, {0.5});
    const auto full = negaflow::imaging::apply_grain_mend(std::move(source), {1.0});
    expect(
        half.status == negaflow::imaging::GrainMendStatus::ok &&
            full.status == negaflow::imaging::GrainMendStatus::ok &&
            half.image.pixels.size() == original.size() &&
            full.image.pixels.size() == original.size(),
        "partial and full GrainMend return complete images");
    if (half.status != negaflow::imaging::GrainMendStatus::ok ||
        full.status != negaflow::imaging::GrainMendStatus::ok ||
        half.image.pixels.size() != original.size() ||
        full.image.pixels.size() != original.size()) {
        return;
    }
    const std::size_t index = 30U * full.image.width + 30U;
    const float half_change =
        std::abs(original[index].red - half.image.pixels[index].red);
    const float full_change =
        std::abs(original[index].red - full.image.pixels[index].red);
    expect(
        half.info.applied && full.info.applied &&
            std::abs(half_change * 2.0F - full_change) < 1.0e-6F &&
            half.image.pixels[index].alpha == original[index].alpha,
        "strength blends the repair linearly and preserves alpha");
}

}  // namespace grain_mend_tests
