#include "negaflow/imaging/auto_adjust.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

// BGRA8, the layout the preview hands back.
[[nodiscard]] std::vector<std::uint8_t> flat_image(
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint8_t red,
    const std::uint8_t green,
    const std::uint8_t blue) {
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(width) * height * 4U, 0U);
    for (std::size_t index = 0U; index < pixels.size(); index += 4U) {
        pixels[index] = blue;
        pixels[index + 1U] = green;
        pixels[index + 2U] = red;
        pixels[index + 3U] = 0xFFU;
    }
    return pixels;
}

[[nodiscard]] negaflow::imaging::AutoAdjustStats stats_of(
    const std::vector<std::uint8_t>& pixels,
    const std::uint32_t width,
    const std::uint32_t height) {
    negaflow::imaging::AutoAdjustStats stats{};
    const bool ok = negaflow::imaging::compute_auto_adjust_stats(
        pixels.data(),
        width,
        height,
        static_cast<std::size_t>(width) * 4U,
        stats);
    if (!ok) {
        std::cerr << "FAIL: statistics could not be computed\n";
        ++failures;
    }
    return stats;
}

void test_statistics_describe_the_frame() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 48U;
    const auto pixels = flat_image(width, height, 128U, 128U, 128U);
    const auto stats = stats_of(pixels, width, height);

    expect(
        std::abs(stats.average_red - (128.0 / 255.0)) < 1.0e-9 &&
            std::abs(stats.average_green - (128.0 / 255.0)) < 1.0e-9,
        "a flat frame reports its own level as the mean");
    expect(
        std::abs(stats.average_saturation) < 1.0e-9,
        "a grey frame has no saturation");
    double total = 0.0;
    for (const double bin : stats.luma_histogram) {
        total += bin;
    }
    expect(std::abs(total - 1.0) < 1.0e-9, "the histogram is normalised");
    expect(
        std::abs(stats.neutral_pixel_fraction - 1.0) < 1.0e-9,
        "every pixel of a mid grey frame counts as near-neutral");
}

// The rule that separates this from a grey-world auto: a bright scene must not be hauled
// down to mid grey. Only real clipping pulls exposure negative.
void test_exposure_only_brightens_unless_clipping() {
    constexpr std::uint32_t width = 40U;
    constexpr std::uint32_t height = 40U;

    const auto dark = flat_image(width, height, 40U, 40U, 40U);
    const auto dark_tone = negaflow::imaging::auto_tone(stats_of(dark, width, height));
    expect(dark_tone.exposure > 0.0, "a dark frame is brightened");

    const auto bright = flat_image(width, height, 230U, 230U, 230U);
    const auto bright_tone = negaflow::imaging::auto_tone(stats_of(bright, width, height));
    expect(
        bright_tone.exposure >= 0.0,
        "a bright but unclipped frame is never darkened");

    // Pure white everywhere is unambiguous clipping, which is the one case that darkens.
    const auto clipped = flat_image(width, height, 255U, 255U, 255U);
    const auto clipped_tone =
        negaflow::imaging::auto_tone(stats_of(clipped, width, height));
    expect(
        clipped_tone.exposure < 0.0,
        "a genuinely clipped frame is pulled down");
    expect(
        clipped_tone.exposure >= -3.0,
        "exposure recovery stays inside the automatic limit");
}

// Highlights and shadows are recovery only. Letting either run both ways would fight the
// endpoint sliders.
void test_recovery_sliders_move_one_way_only() {
    constexpr std::uint32_t width = 32U;
    constexpr std::uint32_t height = 32U;
    for (const int level : {10, 60, 128, 200, 250}) {
        const auto pixels = flat_image(
            width,
            height,
            static_cast<std::uint8_t>(level),
            static_cast<std::uint8_t>(level),
            static_cast<std::uint8_t>(level));
        const auto tone = negaflow::imaging::auto_tone(stats_of(pixels, width, height));
        expect(tone.highlights <= 0.0, "highlights only ever recover");
        expect(tone.shadows >= 0.0, "shadows only ever lift");
        expect(tone.vibrance >= 0.0, "vibrance only ever increases");
        expect(
            tone.contrast >= -0.45 && tone.contrast <= 0.55 &&
                tone.whites >= -1.0 && tone.whites <= 1.0 &&
                tone.blacks >= -1.0 && tone.blacks <= 0.15 &&
                tone.density >= -0.4 && tone.density <= 0.4,
            "every automatic value stays inside its documented range");
    }
}

// A neutral frame must be left alone. An auto white balance that moves grey is worse
// than none at all.
void test_white_balance_leaves_neutral_alone() {
    constexpr std::uint32_t width = 32U;
    constexpr std::uint32_t height = 32U;
    const auto grey = flat_image(width, height, 140U, 140U, 140U);
    const auto balance =
        negaflow::imaging::auto_white_balance(stats_of(grey, width, height));
    expect(
        balance.warmth == 0.0 && balance.tint == 0.0,
        "a neutral frame gets no white balance correction");
}

// A warm cast has to be cooled, partially and within the clamp — never neutralised
// outright, which is what overshoots on scenes that are legitimately one colour.
void test_white_balance_cools_a_warm_cast_partially() {
    constexpr std::uint32_t width = 32U;
    constexpr std::uint32_t height = 32U;
    const auto warm = flat_image(width, height, 170U, 140U, 110U);
    const auto stats = stats_of(warm, width, height);
    const auto balance = negaflow::imaging::auto_white_balance(stats);

    expect(balance.warmth < 0.0, "a warm frame is cooled");
    expect(
        balance.warmth >= -0.60 && balance.warmth <= 0.60 &&
            balance.tint >= -0.60 && balance.tint <= 0.60,
        "the correction stays inside the residual clamp");

    // Applying the returned gains must move the frame toward neutral without crossing it,
    // which is what "partial" means in practice.
    const double red = stats.neutral_linear_red * (1.0 + (0.18 * balance.warmth));
    const double blue = stats.neutral_linear_blue * (1.0 - (0.18 * balance.warmth));
    const double before = stats.neutral_linear_red - stats.neutral_linear_blue;
    const double after = red - blue;
    expect(after > 0.0, "the correction does not overshoot into a cool cast");
    expect(after < before, "the correction reduces the measured cast");
}

// Pressing auto twice must give the same answer as pressing it once: the values are
// assigned, so a drifting result would be visible immediately.
void test_results_are_deterministic() {
    constexpr std::uint32_t width = 50U;
    constexpr std::uint32_t height = 30U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(width) * height * 4U, 0U);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::size_t index =
                ((static_cast<std::size_t>(y) * width) + x) * 4U;
            pixels[index] = static_cast<std::uint8_t>((x * 5U) % 256U);
            pixels[index + 1U] = static_cast<std::uint8_t>((y * 9U) % 256U);
            pixels[index + 2U] = static_cast<std::uint8_t>(((x + y) * 3U) % 256U);
            pixels[index + 3U] = 0xFFU;
        }
    }
    const auto first = negaflow::imaging::auto_tone(stats_of(pixels, width, height));
    const auto second = negaflow::imaging::auto_tone(stats_of(pixels, width, height));
    expect(
        first.exposure == second.exposure && first.contrast == second.contrast &&
            first.highlights == second.highlights && first.shadows == second.shadows &&
            first.whites == second.whites && first.blacks == second.blacks &&
            first.density == second.density && first.vibrance == second.vibrance,
        "the same frame produces the same automatic settings every time");
}

void test_invalid_input_is_refused() {
    negaflow::imaging::AutoAdjustStats stats{};
    expect(
        !negaflow::imaging::compute_auto_adjust_stats(nullptr, 4U, 4U, 16U, stats),
        "a null buffer is refused");
    const auto pixels = flat_image(4U, 4U, 10U, 10U, 10U);
    expect(
        !negaflow::imaging::compute_auto_adjust_stats(pixels.data(), 0U, 4U, 16U, stats),
        "a zero width is refused");
    expect(
        !negaflow::imaging::compute_auto_adjust_stats(pixels.data(), 4U, 4U, 8U, stats),
        "a stride shorter than one row is refused");
}

}  // namespace

int main() {
    test_statistics_describe_the_frame();
    test_exposure_only_brightens_unless_clipping();
    test_recovery_sliders_move_one_way_only();
    test_white_balance_leaves_neutral_alone();
    test_white_balance_cools_a_warm_cast_partially();
    test_results_are_deterministic();
    test_invalid_input_is_refused();

    if (failures != 0) {
        std::cerr << failures << " auto adjust test(s) failed\n";
        return 1;
    }
    std::cout << "auto adjust tests passed\n";
    return 0;
}
