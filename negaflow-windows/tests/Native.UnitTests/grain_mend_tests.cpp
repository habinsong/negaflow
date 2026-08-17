#include "negaflow/imaging/grain_mend.h"

#include "grain_mend_detector.h"
#include "grain_mend_resample.h"

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

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] negaflow::imaging::WorkingImage make_clean_image(
    const std::uint32_t width = 96U,
    const std::uint32_t height = 72U) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float value = 0.18F + 0.24F *
                static_cast<float>(x) / static_cast<float>(width - 1U);
            image.pixels[static_cast<std::size_t>(y) * width + x] =
                {value, value * 0.96F, value * 0.91F, 1.0F};
        }
    }
    return image;
}

[[nodiscard]] negaflow::imaging::WorkingImage make_uniform_image(
    const std::uint32_t width,
    const std::uint32_t height,
    const float value = 0.20F) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.assign(
        static_cast<std::size_t>(width) * height,
        negaflow::core::Rgba32F{value, value, value, 1.0F});
    return image;
}

[[nodiscard]] bool same_pixels(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept {
    return left.size() == right.size() &&
           std::memcmp(
               left.data(),
               right.data(),
               left.size() * sizeof(negaflow::core::Rgba32F)) == 0;
}

void add_chromatic_grain(
    negaflow::imaging::WorkingImage& image,
    const std::uint32_t seed,
    const std::uint32_t probability_per_thousand,
    const float amplitude) {
    std::uint32_t state = seed;
    for (auto& pixel : image.pixels) {
        float* const channels[] = {&pixel.red, &pixel.green, &pixel.blue};
        for (float* const channel : channels) {
            state = state * 1664525U + 1013904223U;
            if ((state >> 16U) % 1000U >= probability_per_thousand) {
                continue;
            }
            state = state * 1664525U + 1013904223U;
            *channel = std::clamp(
                *channel + ((state & 1U) == 0U ? -amplitude : amplitude),
                0.0F,
                1.0F);
        }
    }
}

void add_dark_micro_speck(
    negaflow::imaging::WorkingImage& image,
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t size,
    const float drop) {
    for (std::uint32_t row = y; row < y + size; ++row) {
        for (std::uint32_t column = x; column < x + size; ++column) {
            auto& pixel = image.pixels[static_cast<std::size_t>(row) * image.width + column];
            pixel.red -= drop;
            pixel.green -= drop;
            pixel.blue -= drop;
        }
    }
}

[[nodiscard]] float pixel_error(
    const negaflow::core::Rgba32F actual,
    const negaflow::core::Rgba32F expected) noexcept {
    return std::abs(actual.red - expected.red) +
           std::abs(actual.green - expected.green) +
           std::abs(actual.blue - expected.blue);
}

void test_dust_and_thin_scratch_are_repaired() {
    const auto clean = make_clean_image();
    auto damaged = clean;
    damaged.pixels[24U * damaged.width + 18U] = {0.95F, 0.95F, 0.95F, 1.0F};
    for (std::uint32_t y = 14U; y < 58U; ++y) {
        damaged.pixels[static_cast<std::size_t>(y) * damaged.width + 62U] =
            {0.02F, 0.02F, 0.02F, 1.0F};
    }

    float before = pixel_error(
        damaged.pixels[24U * damaged.width + 18U],
        clean.pixels[24U * clean.width + 18U]);
    for (std::uint32_t y = 14U; y < 58U; ++y) {
        before += pixel_error(
            damaged.pixels[static_cast<std::size_t>(y) * damaged.width + 62U],
            clean.pixels[static_cast<std::size_t>(y) * clean.width + 62U]);
    }

    const auto result = negaflow::imaging::apply_grain_mend(
        std::move(damaged), {1.0});
    const std::size_t expected_pixels =
        static_cast<std::size_t>(clean.width) * clean.height;
    expect(
        result.status == negaflow::imaging::GrainMendStatus::ok &&
            result.image.pixels.size() == expected_pixels,
        "RGB automatic GrainMend returns a complete image");
    if (result.status != negaflow::imaging::GrainMendStatus::ok ||
        result.image.pixels.size() != expected_pixels) {
        std::cerr << "diagnostic status="
                  << negaflow::imaging::grain_mend_status_name(result.status)
                  << " kernel="
                  << negaflow::core::kernel_status_name(result.info.kernel_status)
                  << " pixels=" << result.image.pixels.size() << '\n';
        return;
    }
    float after = pixel_error(
        result.image.pixels[24U * result.image.width + 18U],
        clean.pixels[24U * clean.width + 18U]);
    for (std::uint32_t y = 14U; y < 58U; ++y) {
        after += pixel_error(
            result.image.pixels[static_cast<std::size_t>(y) * result.image.width + 62U],
            clean.pixels[static_cast<std::size_t>(y) * clean.width + 62U]);
    }
    expect(
        result.status == negaflow::imaging::GrainMendStatus::ok &&
            result.info.applied && result.info.candidate_pixels != 0U &&
            result.info.repaired_pixels != 0U,
        "RGB automatic GrainMend reports accepted repairs");
    if (!(after < before * 0.25F)) {
        std::cerr << "diagnostic before=" << before << " after=" << after
                  << " candidates=" << result.info.candidate_pixels
                  << " repaired=" << result.info.repaired_pixels << '\n';
    }
    expect(after < before * 0.25F,
           "dust and a thin scratch are substantially closer to the clean frame");
}

void test_grain_only_field_is_not_wiped() {
    auto source = make_clean_image(128U, 96U);
    std::uint32_t state = 0x12345678U;
    for (auto& pixel : source.pixels) {
        state = state * 1664525U + 1013904223U;
        const float noise =
            (static_cast<float>((state >> 8U) & 0xffffU) / 65535.0F - 0.5F) *
            0.012F;
        pixel.red += noise;
        pixel.green += noise;
        pixel.blue += noise;
    }
    const auto original = source.pixels;
    const auto result = negaflow::imaging::apply_grain_mend(
        std::move(source), {1.0});
    expect(
        result.status == negaflow::imaging::GrainMendStatus::ok &&
            !result.info.applied && result.info.candidate_pixels == 0U,
        "a deterministic grain-only field produces no accepted component");
    expect(same_pixels(result.image.pixels, original),
           "a grain-only field remains byte exact when no defect is accepted");
}

void test_diagonal_scratch_is_repaired() {
    const auto clean = make_clean_image(96U, 96U);
    auto damaged = clean;
    float before = 0.0F;
    for (std::uint32_t position = 16U; position < 80U; ++position) {
        const std::size_t index =
            static_cast<std::size_t>(position) * damaged.width + position;
        damaged.pixels[index] = {0.02F, 0.02F, 0.02F, 1.0F};
        before += pixel_error(damaged.pixels[index], clean.pixels[index]);
    }

    const auto result = negaflow::imaging::apply_grain_mend(
        std::move(damaged), {1.0});
    float after = 0.0F;
    if (result.status == negaflow::imaging::GrainMendStatus::ok &&
        result.image.pixels.size() == clean.pixels.size()) {
        for (std::uint32_t position = 16U; position < 80U; ++position) {
            const std::size_t index =
                static_cast<std::size_t>(position) * result.image.width + position;
            after += pixel_error(result.image.pixels[index], clean.pixels[index]);
        }
    } else {
        after = before;
    }
    expect(
        result.status == negaflow::imaging::GrainMendStatus::ok &&
            result.info.applied && after < before * 0.25F,
        "a 45-degree thin scratch is detected and substantially repaired");
}

void test_chromatic_dust_is_detected_without_luminance_dilution() {
    const auto clean = make_uniform_image(96U, 72U);
    auto damaged = clean;
    constexpr std::uint32_t x = 43U;
    constexpr std::uint32_t y = 31U;
    const std::size_t index = static_cast<std::size_t>(y) * damaged.width + x;
    damaged.pixels[index].blue = 0.95F;
    const float before = pixel_error(damaged.pixels[index], clean.pixels[index]);

    const auto result = negaflow::imaging::apply_grain_mend(
        std::move(damaged), {1.0});
    const float after =
        result.status == negaflow::imaging::GrainMendStatus::ok &&
                result.image.pixels.size() == clean.pixels.size()
            ? pixel_error(result.image.pixels[index], clean.pixels[index])
            : before;
    expect(
        result.status == negaflow::imaging::GrainMendStatus::ok &&
            result.info.applied && after < before * 0.25F,
        "a blue-channel-only dust defect is detected and repaired");
}

[[nodiscard]] std::vector<std::size_t> draw_faint_scratch(
    negaflow::imaging::WorkingImage& image,
    const double angle_degrees) {
    constexpr double pi = 3.14159265358979323846;
    const double radians = angle_degrees * pi / 180.0;
    const double dx = std::cos(radians);
    const double dy = std::sin(radians);
    const double center_x = static_cast<double>(image.width - 1U) * 0.5;
    const double center_y = static_cast<double>(image.height - 1U) * 0.5;
    std::vector<std::size_t> pixels{};
    for (int t = -100; t <= 100; ++t) {
        const int x = static_cast<int>(std::lround(center_x + dx * t));
        const int y = static_cast<int>(std::lround(center_y + dy * t));
        if (x < 0 || y < 0 ||
            x >= static_cast<int>(image.width) ||
            y >= static_cast<int>(image.height)) {
            continue;
        }
        const std::size_t index =
            static_cast<std::size_t>(y) * image.width +
            static_cast<std::size_t>(x);
        if (std::find(pixels.begin(), pixels.end(), index) != pixels.end()) {
            continue;
        }
        pixels.push_back(index);
        image.pixels[index].red += 0.08F;
        image.pixels[index].green += 0.08F;
        image.pixels[index].blue += 0.08F;
    }
    return pixels;
}

void test_off_axis_scratches_are_repaired() {
    constexpr std::array<double, 2U> angles{18.0, 72.0};
    for (const double angle : angles) {
        const auto clean = make_uniform_image(240U, 240U);
        auto damaged = clean;
        const std::vector<std::size_t> defect =
            draw_faint_scratch(damaged, angle);
        float before = 0.0F;
        for (const std::size_t index : defect) {
            before += pixel_error(damaged.pixels[index], clean.pixels[index]);
        }
        const auto result = negaflow::imaging::apply_grain_mend(
            std::move(damaged), {1.0});
        float after = before;
        if (result.status == negaflow::imaging::GrainMendStatus::ok &&
            result.image.pixels.size() == clean.pixels.size()) {
            after = 0.0F;
            for (const std::size_t index : defect) {
                after += pixel_error(result.image.pixels[index], clean.pixels[index]);
            }
        }
        if (!(result.info.applied && after < before * 0.45F)) {
            std::cerr << "diagnostic off-axis angle=" << angle
                      << " before=" << before << " after=" << after
                      << " candidates=" << result.info.candidate_pixels << '\n';
        }
        expect(
            result.status == negaflow::imaging::GrainMendStatus::ok &&
                result.info.applied && after < before * 0.45F,
            "an 18- or 72-degree faint scratch is detected and repaired");
    }
}

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

void test_detection_sensitivity_controls_candidate_thresholds() {
    const auto dust_clean = make_uniform_image(96U, 72U);
    auto faint_dust = dust_clean;
    constexpr std::size_t dust_index = 31U * 96U + 43U;
    faint_dust.pixels[dust_index] = {0.27F, 0.27F, 0.27F, 1.0F};

    negaflow::imaging::GrainMendParameters conservative_dust{1.0};
    conservative_dust.dust_sensitivity = 0.0;
    conservative_dust.scratch_sensitivity = 0.0;
    const auto dust_low = negaflow::imaging::apply_grain_mend(
        faint_dust,
        conservative_dust);
    negaflow::imaging::GrainMendParameters sensitive_dust = conservative_dust;
    sensitive_dust.dust_sensitivity = 1.0;
    const auto dust_high = negaflow::imaging::apply_grain_mend(
        std::move(faint_dust),
        sensitive_dust);
    expect(
        dust_low.status == negaflow::imaging::GrainMendStatus::ok &&
            !dust_low.info.applied &&
            dust_high.status == negaflow::imaging::GrainMendStatus::ok &&
            dust_high.info.applied &&
            pixel_error(dust_high.image.pixels[dust_index],
                        dust_clean.pixels[dust_index]) < 1.0e-5F,
        "dust sensitivity changes the normalized automatic detection threshold");

    const auto scratch_clean = make_uniform_image(128U, 96U);
    auto faint_scratch = scratch_clean;
    for (std::uint32_t x = 20U; x < 108U; ++x) {
        faint_scratch.pixels[48U * faint_scratch.width + x] =
            {0.225F, 0.225F, 0.225F, 1.0F};
    }
    negaflow::imaging::GrainMendParameters conservative_scratch{1.0};
    conservative_scratch.dust_sensitivity = 0.0;
    conservative_scratch.scratch_sensitivity = 0.0;
    const auto scratch_low = negaflow::imaging::apply_grain_mend(
        faint_scratch,
        conservative_scratch);
    negaflow::imaging::GrainMendParameters sensitive_scratch =
        conservative_scratch;
    sensitive_scratch.scratch_sensitivity = 1.0;
    const auto scratch_high = negaflow::imaging::apply_grain_mend(
        std::move(faint_scratch),
        sensitive_scratch);
    expect(
        scratch_low.status == negaflow::imaging::GrainMendStatus::ok &&
            !scratch_low.info.applied &&
            scratch_high.status == negaflow::imaging::GrainMendStatus::ok &&
            scratch_high.info.applied,
        "scratch sensitivity changes the normalized automatic detection threshold");
}

void test_whole_frame_structure_filter_preserves_grid_lines() {
    const auto clean = make_uniform_image(256U, 256U);
    auto source = clean;
    constexpr std::array<std::uint32_t, 3U> centers{72U, 96U, 120U};
    for (const std::uint32_t center_y : centers) {
        for (const std::uint32_t center_x : centers) {
            for (std::uint32_t y = center_y - 7U; y <= center_y + 7U; ++y) {
                source.pixels[static_cast<std::size_t>(y) * source.width + center_x] =
                    {0.28F, 0.28F, 0.28F, 1.0F};
            }
        }
    }
    for (std::uint32_t y = 40U; y < 82U; ++y) {
        source.pixels[static_cast<std::size_t>(y) * source.width + 220U] =
            {0.28F, 0.28F, 0.28F, 1.0F};
    }

    negaflow::imaging::GrainMendParameters unfiltered{1.0};
    const auto without_filter = negaflow::imaging::apply_grain_mend(
        source,
        unfiltered);
    negaflow::imaging::GrainMendParameters filtered = unfiltered;
    filtered.reject_structure_lines = true;
    const auto with_filter = negaflow::imaging::apply_grain_mend(
        std::move(source),
        filtered);
    const std::size_t grid_index = 96U * clean.width + 96U;
    const std::size_t isolated_index = 60U * clean.width + 220U;
    expect(
        without_filter.status == negaflow::imaging::GrainMendStatus::ok &&
            with_filter.status == negaflow::imaging::GrainMendStatus::ok &&
            pixel_error(without_filter.image.pixels[grid_index],
                        clean.pixels[grid_index]) < 1.0e-5F &&
            pixel_error(with_filter.image.pixels[grid_index],
                        clean.pixels[grid_index]) > 0.20F &&
            pixel_error(with_filter.image.pixels[isolated_index],
                        clean.pixels[isolated_index]) < 1.0e-5F,
        "whole-frame structure protection rejects a repeated grid but keeps an isolated scratch");
}

void test_whole_frame_tiles_stitch_a_boundary_scratch() {
    const auto clean = make_uniform_image(1'600U, 96U);
    auto source = clean;
    for (std::uint32_t x = 750U; x < 850U; ++x) {
        source.pixels[48U * source.width + x] =
            {0.34F, 0.34F, 0.34F, 1.0F};
    }

    negaflow::imaging::GrainMendParameters parameters{1.0};
    parameters.dust_sensitivity = 0.0;
    parameters.scratch_sensitivity = 1.0;
    parameters.reject_structure_lines = true;
    const auto repaired = negaflow::imaging::apply_grain_mend(
        std::move(source),
        parameters);
    const std::size_t left = 48U * clean.width + 799U;
    const std::size_t right = left + 1U;
    expect(
        repaired.status == negaflow::imaging::GrainMendStatus::ok &&
            repaired.info.applied &&
            repaired.info.detection_width == clean.width &&
            repaired.info.detection_height == clean.height &&
            pixel_error(repaired.image.pixels[left], clean.pixels[left]) < 1.0e-5F &&
            pixel_error(repaired.image.pixels[right], clean.pixels[right]) < 1.0e-5F,
        "whole-frame tiles stitch one scratch across a non-overlapping core boundary");
}

void test_labeled_detection_adds_curved_thin_scratch_evidence() {
    const auto clean = make_uniform_image(256U, 256U);
    auto source = clean;
    int previous_x = 128;
    for (std::uint32_t y = 32U; y < 224U; ++y) {
        const int current_x = 128 + static_cast<int>(std::lround(
            12.0 * std::sin(static_cast<double>(y) * 0.12)));
        const int first = std::min(previous_x, current_x);
        const int last = std::max(previous_x, current_x);
        for (int x = first; x <= last; ++x) {
            source.pixels[static_cast<std::size_t>(y) * source.width +
                          static_cast<std::size_t>(x)] =
                {0.30F, 0.30F, 0.30F, 1.0F};
        }
        previous_x = current_x;
    }

    const auto detection =
        negaflow::imaging::grain_mend_detail::make_detection_image(source);
    const auto simple = negaflow::imaging::grain_mend_detail::find_candidates(
        detection, 0.0, 1.0, 0.75, false);
    const auto labeled = negaflow::imaging::grain_mend_detail::find_candidates(
        detection, 0.0, 1.0, 0.75, true);
    const auto scratch_count = [](const std::vector<std::uint8_t>& map,
                                  const std::uint8_t level) {
        return static_cast<std::size_t>(std::count_if(
            map.begin(), map.end(), [&](const std::uint8_t value) {
                return (value & level) != 0U;
            }));
    };
    const std::size_t simple_weak = scratch_count(simple.weak, 2U);
    const std::size_t labeled_weak = scratch_count(labeled.weak, 2U);
    const std::size_t labeled_strong = scratch_count(labeled.strong, 2U);
    expect(
        labeled_weak > simple_weak && labeled_strong != 0U,
        "labeled detection adds strong and weak evidence for a curved thin scratch");
}

void test_invalid_inputs_fail_closed() {
    const auto invalid_strength = negaflow::imaging::apply_grain_mend(
        make_clean_image(),
        {std::numeric_limits<double>::quiet_NaN()});
    expect(
        invalid_strength.status ==
                negaflow::imaging::GrainMendStatus::invalid_parameter &&
            invalid_strength.image.pixels.empty(),
        "a non-finite strength fails closed");

    negaflow::imaging::GrainMendParameters invalid_detection{1.0};
    invalid_detection.protect_detail = 1.01;
    const auto invalid_detection_result = negaflow::imaging::apply_grain_mend(
        make_clean_image(),
        invalid_detection);
    expect(
        invalid_detection_result.status ==
                negaflow::imaging::GrainMendStatus::invalid_parameter &&
            invalid_detection_result.image.pixels.empty(),
        "out-of-range detection controls fail closed");

    auto invalid_image = make_clean_image();
    invalid_image.pixels[0].green = std::numeric_limits<float>::infinity();
    const auto invalid_pixels = negaflow::imaging::apply_grain_mend(
        std::move(invalid_image), {1.0});
    expect(
        invalid_pixels.status == negaflow::imaging::GrainMendStatus::kernel_failed &&
            invalid_pixels.info.kernel_status ==
                negaflow::core::KernelStatus::non_finite_input &&
            invalid_pixels.image.pixels.empty(),
        "non-finite pixels fail closed without a partial image");
}

// A latch set before the call must stop detection and hand back nothing, and an untouched
// flag must not change the result at all. The second half is the one that matters: the
// cancel checks sit inside the hot loops, so they are cheap to get wrong.
void test_cancellation_stops_detection_and_keeps_results() {
    std::uint32_t latched = 1U;
    const auto cancelled = negaflow::imaging::apply_grain_mend(
        make_clean_image(),
        {1.0},
        negaflow::core::CancelFlag{&latched});
    expect(
        cancelled.status == negaflow::imaging::GrainMendStatus::cancelled &&
            cancelled.image.pixels.empty(),
        "a latched cancel flag stops GrainMend and discards pixels");

    std::uint32_t idle = 0U;
    const auto baseline = negaflow::imaging::apply_grain_mend(
        make_clean_image(),
        {1.0});
    const auto with_flag = negaflow::imaging::apply_grain_mend(
        make_clean_image(),
        {1.0},
        negaflow::core::CancelFlag{&idle});
    expect(
        baseline.status == negaflow::imaging::GrainMendStatus::ok &&
            with_flag.status == negaflow::imaging::GrainMendStatus::ok &&
            baseline.image.pixels.size() == with_flag.image.pixels.size(),
        "an unlatched flag leaves GrainMend running normally");

    bool identical = baseline.info.repaired_pixels == with_flag.info.repaired_pixels &&
                     baseline.info.candidate_pixels == with_flag.info.candidate_pixels;
    for (std::size_t index = 0U;
         identical && index < baseline.image.pixels.size();
         ++index) {
        identical =
            baseline.image.pixels[index].red == with_flag.image.pixels[index].red &&
            baseline.image.pixels[index].green == with_flag.image.pixels[index].green &&
            baseline.image.pixels[index].blue == with_flag.image.pixels[index].blue &&
            baseline.image.pixels[index].alpha == with_flag.image.pixels[index].alpha;
    }
    expect(identical, "passing a flag does not change a single repaired pixel");

    // The whole-frame tiled path has its own loop and its own poll point.
    negaflow::imaging::GrainMendParameters tiled{1.0};
    tiled.reject_structure_lines = true;
    const auto cancelled_tiles = negaflow::imaging::apply_grain_mend(
        make_clean_image(),
        tiled,
        negaflow::core::CancelFlag{&latched});
    expect(
        cancelled_tiles.status == negaflow::imaging::GrainMendStatus::cancelled &&
            cancelled_tiles.image.pixels.empty(),
        "the whole-frame tiled path honours the same flag");
}

// 검토 가능한 GrainMend 도구(자동·가이드)는 자동 수리와 **같은 판정**을 보여 주어야 합니다.
// 그래서 검출만 떼어 낸 함수가 수리 경로와 같은 화소 수를 고르는지 봅니다 — 두 벌로 갈라지면
// 사용자가 미리 본 것과 실제로 고쳐진 것이 달라집니다.
void test_detection_only_agrees_with_the_repair_path() {
    auto damaged = make_clean_image();
    damaged.pixels[24U * damaged.width + 18U] = {0.95F, 0.95F, 0.95F, 1.0F};
    for (std::uint32_t y = 14U; y < 58U; ++y) {
        damaged.pixels[static_cast<std::size_t>(y) * damaged.width + 62U] =
            {0.02F, 0.02F, 0.02F, 1.0F};
    }

    negaflow::imaging::GrainMendParameters parameters{1.0};
    // 자동 검토와 자동 복원은 같은 타일·라벨 경로를 쓴다(macOS detectComponents).
    parameters.reject_structure_lines = true;
    const auto detected =
        negaflow::imaging::detect_grain_mend(damaged, parameters);
    const auto repaired =
        negaflow::imaging::apply_grain_mend(damaged, parameters);

    expect(
        detected.status == negaflow::imaging::GrainMendStatus::ok,
        "detection only reports ok on a valid frame");
    expect(
        detected.width == repaired.info.detection_width &&
            detected.height == repaired.info.detection_height,
        "detection only reports the same capped analysis size as the repair");
    if (detected.accepted_pixels != repaired.info.candidate_pixels) {
        std::cerr << "diagnostic detect_vs_repair detect="
                  << detected.accepted_pixels << " repair="
                  << repaired.info.candidate_pixels
                  << " detect_w=" << detected.width
                  << " repair_w=" << repaired.info.detection_width
                  << " detect_components=" << detected.components.size()
                  << '\n';
    }
    expect(
        detected.accepted_pixels == repaired.info.candidate_pixels &&
            detected.accepted_pixels != 0U,
        "detection only accepts exactly the pixels the repair would touch");
    expect(
        detected.mask.size() ==
            static_cast<std::size_t>(detected.width) * detected.height,
        "the mask covers the analysis image one byte per pixel");

    std::size_t marked = 0U;
    for (const std::uint8_t value : detected.mask) {
        if (value != 0U) {
            ++marked;
        }
    }
    expect(marked == detected.accepted_pixels,
        "the reported count matches the marked pixels");

    // 세기는 검출에 영향을 주지 않아야 합니다 — 아직 아무것도 걸지 않은 프레임에서도
    // 자동 버튼이 무엇을 찾았는지 보여 줄 수 있어야 합니다.
    negaflow::imaging::GrainMendParameters idle = parameters;
    idle.strength = 0.0;
    const auto at_zero = negaflow::imaging::detect_grain_mend(damaged, idle);
    expect(
        at_zero.status == negaflow::imaging::GrainMendStatus::ok &&
            at_zero.accepted_pixels == detected.accepted_pixels,
        "strength does not change what detection finds");

    negaflow::imaging::WorkingImage empty{};
    expect(
        negaflow::imaging::detect_grain_mend(empty, parameters).status ==
            negaflow::imaging::GrainMendStatus::invalid_parameter,
        "detection only fails closed on an empty image");
}

// 가이드는 전체에서 찾은 뒤 숨기는 방식이 아니라 선택한 raw ROI만 잘라 분석해야 합니다.
// 이 계약은 주변 통계와 검출 이미지의 크기를 모두 바꾸므로, 반환 좌표도 함께 고정합니다.
void test_guided_detection_crops_to_the_selected_roi() {
    const auto source = make_clean_image();
    const negaflow::imaging::GrainMendRoi roi{0.25, 0.25, 0.5, 0.5};
    const auto detected = negaflow::imaging::detect_grain_mend(
        source, {1.0}, roi);

    expect(
        detected.status == negaflow::imaging::GrainMendStatus::ok &&
            detected.roi_x == 24U && detected.roi_y == 18U &&
            detected.roi_width == 48U && detected.roi_height == 36U,
        "guided detection reports the selected source rectangle");
    expect(
        detected.width == 48U && detected.height == 36U &&
            detected.mask.size() == 48U * 36U,
        "guided detection analyses only the selected rectangle");
}

// macOS의 추가 미세 입자 패스는 기존 결함 후보를 약화시키지 않고, 세 채널에 같이 어두운
// 2~7px 표면 이물만 선택적으로 더합니다. 토글을 끄면 이전 검출 마스크가 정확히 남아야 합니다.
void test_isolated_dark_blob_is_classified_dust_or_pinhole() {
    constexpr std::uint32_t width = 256U;
    constexpr std::uint32_t height = 256U;
    auto damaged = make_uniform_image(width, height, 0.20F);
    for (std::uint32_t y = 80U; y < 92U; ++y) {
        for (std::uint32_t x = 80U; x < 92U; ++x) {
            auto& pixel =
                damaged.pixels[static_cast<std::size_t>(y) * width + x];
            pixel.red = 0.02F;
            pixel.green = 0.02F;
            pixel.blue = 0.02F;
        }
    }

    negaflow::imaging::GrainMendParameters parameters{1.0};
    parameters.dust_sensitivity = 1.0;
    parameters.scratch_sensitivity = 1.0;
    parameters.protect_detail = 0.6;
    parameters.reject_structure_lines = true;
    parameters.detect_micro_specks = false;
    const auto detected = negaflow::imaging::detect_grain_mend(damaged, parameters);
    std::size_t dust_like = 0U;
    for (const auto& component : detected.components) {
        if (component.classification ==
                negaflow::imaging::grain_mend_detail::DefectClassification::dust ||
            component.classification ==
                negaflow::imaging::grain_mend_detail::DefectClassification::
                    pinhole) {
            ++dust_like;
        }
    }
    expect(detected.status == negaflow::imaging::GrainMendStatus::ok,
           "isolated dark blob detection completes");
    expect(dust_like > 0U,
           "detect_grain_mend classifies an isolated dark blob as dust or pinhole");
}

void test_micro_specks_become_classified_components() {
    constexpr std::uint32_t width = 256U;
    constexpr std::uint32_t height = 256U;
    auto damaged = make_uniform_image(width, height, 0.20F);
    std::vector<std::pair<std::uint32_t, std::uint32_t>> specks{};
    for (std::uint32_t x = 40U; x <= 200U; x += 80U) {
        for (std::uint32_t y = 40U; y <= 200U; y += 80U) {
            specks.push_back({x, y});
            add_dark_micro_speck(damaged, x, y, 3U, 0.065F);
        }
    }

    negaflow::imaging::GrainMendParameters off{1.0};
    off.dust_sensitivity = 0.6;
    off.scratch_sensitivity = 0.7;
    off.protect_detail = 0.6;
    off.detect_micro_specks = false;
    const auto legacy = negaflow::imaging::detect_grain_mend(damaged, off);
    negaflow::imaging::GrainMendParameters on = off;
    on.detect_micro_specks = true;
    const auto detected = negaflow::imaging::detect_grain_mend(damaged, on);

    std::size_t classified = 0U;
    for (const auto& component : detected.components) {
        if (component.classification ==
            negaflow::imaging::grain_mend_detail::DefectClassification::
                micro_speck) {
            ++classified;
        }
    }
    std::size_t planted_classified = 0U;
    for (const auto [x, y] : specks) {
        const std::size_t center =
            static_cast<std::size_t>(y + 1U) * width + x + 1U;
        for (const auto& component : detected.components) {
            if (component.classification !=
                negaflow::imaging::grain_mend_detail::DefectClassification::
                    micro_speck) {
                continue;
            }
            if (std::find(component.pixels.begin(), component.pixels.end(),
                          center) != component.pixels.end()) {
                ++planted_classified;
                break;
            }
        }
    }
    if (classified == 0U || planted_classified == 0U) {
        std::cerr << "diagnostic classify_specks classified=" << classified
                  << " planted=" << planted_classified << "/" << specks.size()
                  << " legacy=" << legacy.accepted_pixels
                  << " enabled=" << detected.accepted_pixels
                  << " components=" << detected.components.size() << '\n';
    }
    expect(legacy.status == negaflow::imaging::GrainMendStatus::ok &&
               detected.status == negaflow::imaging::GrainMendStatus::ok,
           "micro-speck classification probe completes");
    expect(classified > 0U && planted_classified > 0U,
           "detect_grain_mend promotes planted specks to MicroSpeck components");
}

void test_micro_speck_detection_is_optional_and_additive() {
    constexpr std::uint32_t width = 512U;
    constexpr std::uint32_t height = 512U;
    auto damaged = make_uniform_image(width, height, 0.20F);
    add_chromatic_grain(damaged, 7U, 50U, 0.015F);
    std::vector<std::pair<std::uint32_t, std::uint32_t>> specks{};
    for (std::uint32_t x = 40U; x <= 400U; x += 60U) {
        for (std::uint32_t y = 60U; y <= 420U; y += 90U) {
            specks.push_back({x, y});
            add_dark_micro_speck(damaged, x, y, 3U, 0.065F);
        }
    }

    negaflow::imaging::GrainMendParameters off{1.0};
    off.dust_sensitivity = 0.6;
    off.scratch_sensitivity = 0.7;
    off.protect_detail = 0.6;
    off.detect_micro_specks = false;
    const auto legacy = negaflow::imaging::detect_grain_mend(damaged, off);
    negaflow::imaging::GrainMendParameters on = off;
    on.detect_micro_specks = true;
    const auto detected = negaflow::imaging::detect_grain_mend(damaged, on);

    expect(
        legacy.status == negaflow::imaging::GrainMendStatus::ok &&
            detected.status == negaflow::imaging::GrainMendStatus::ok,
        "micro-speck detection completes for both toggle states");
    expect(
        detected.accepted_pixels >= legacy.accepted_pixels &&
            detected.mask.size() == legacy.mask.size(),
        "the enabled micro-speck pass only adds to the legacy proposal");
    bool preserves_legacy = true;
    for (std::size_t index = 0U; index < legacy.mask.size(); ++index) {
        preserves_legacy = preserves_legacy &&
            (legacy.mask[index] == 0U || detected.mask[index] != 0U);
    }
    expect(preserves_legacy,
        "the enabled micro-speck pass never removes a legacy candidate");

    std::size_t found = 0U;
    for (const auto [x, y] : specks) {
        const std::size_t center = static_cast<std::size_t>(y + 1U) * width + x + 1U;
        if (detected.mask[center] != 0U) {
            ++found;
        }
    }
    if (found < specks.size()) {
        std::cerr << "diagnostic micro_found=" << found << "/" << specks.size()
                  << " legacy=" << legacy.accepted_pixels
                  << " enabled=" << detected.accepted_pixels << '\n';
    }
    expect(found == specks.size(),
        "the optional micro-speck pass finds every neutral 3px speck on chromatic grain");

    std::size_t classified_micro_specks = 0U;
    std::size_t classified_when_off = 0U;
    for (const auto& component : detected.components) {
        if (component.classification ==
            negaflow::imaging::grain_mend_detail::DefectClassification::micro_speck) {
            ++classified_micro_specks;
        }
    }
    for (const auto& component : legacy.components) {
        if (component.classification ==
            negaflow::imaging::grain_mend_detail::DefectClassification::micro_speck) {
            ++classified_when_off;
        }
    }
    expect(classified_when_off == 0U,
        "disabling the micro-speck pass leaves no MicroSpeck components");
    std::size_t added_centers = 0U;
    std::size_t added_classified = 0U;
    for (const auto [x, y] : specks) {
        const std::size_t center =
            static_cast<std::size_t>(y + 1U) * width + x + 1U;
        if (legacy.mask[center] != 0U || detected.mask[center] == 0U) {
            continue;
        }
        ++added_centers;
        for (const auto& component : detected.components) {
            if (component.classification !=
                negaflow::imaging::grain_mend_detail::DefectClassification::
                    micro_speck) {
                continue;
            }
            if (std::find(component.pixels.begin(), component.pixels.end(),
                          center) != component.pixels.end()) {
                ++added_classified;
                break;
            }
        }
    }
    expect(
        added_centers == 0U || added_classified == added_centers,
        "specks added only by the micro-speck pass are classified MicroSpeck");
}

}  // namespace

int main() {
    test_dust_and_thin_scratch_are_repaired();
    test_grain_only_field_is_not_wiped();
    test_diagonal_scratch_is_repaired();
    test_chromatic_dust_is_detected_without_luminance_dilution();
    test_off_axis_scratches_are_repaired();
    test_dense_chromatic_grain_field_is_not_repaired();
    test_wide_highlight_and_dark_structure_are_protected();
    test_large_frame_lanczos_detection_and_affine_mask();
    test_rounded_short_axis_keeps_the_uniform_lanczos_scale();
    test_strength_zero_is_bit_exact_and_partial_strength_blends();
    test_detection_sensitivity_controls_candidate_thresholds();
    test_whole_frame_structure_filter_preserves_grid_lines();
    test_whole_frame_tiles_stitch_a_boundary_scratch();
    test_labeled_detection_adds_curved_thin_scratch_evidence();
    test_invalid_inputs_fail_closed();
    test_cancellation_stops_detection_and_keeps_results();
    test_detection_only_agrees_with_the_repair_path();
    test_guided_detection_crops_to_the_selected_roi();
    test_micro_speck_detection_is_optional_and_additive();
    test_micro_specks_become_classified_components();
    test_isolated_dark_blob_is_classified_dust_or_pinhole();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"grain_mend\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
