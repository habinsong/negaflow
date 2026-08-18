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

}  // namespace grain_mend_tests
