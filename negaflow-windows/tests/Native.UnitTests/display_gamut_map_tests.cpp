#include "negaflow/imaging/display_gamut_map.h"

#include <cmath>
#include <cstdint>
#include <iostream>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool close(const float left, const float right) noexcept {
    return std::abs(left - right) <= 1.0e-6F;
}

[[nodiscard]] float luma(const negaflow::core::Rgba32F pixel) noexcept {
    return (pixel.red * 0.2126F) + (pixel.green * 0.7152F) + (pixel.blue * 0.0722F);
}

// Anything already displayable must survive untouched, otherwise an ordinary photo would
// shift the moment the preview boundary is crossed.
void test_in_gamut_is_identity() {
    for (const negaflow::core::Rgba32F pixel : {
             negaflow::core::Rgba32F{0.0F, 0.0F, 0.0F, 1.0F},
             negaflow::core::Rgba32F{1.0F, 1.0F, 1.0F, 1.0F},
             negaflow::core::Rgba32F{0.2F, 0.55F, 0.9F, 1.0F},
             negaflow::core::Rgba32F{0.75F, 0.1F, 0.33F, 0.5F},
         }) {
        const negaflow::core::Rgba32F folded =
            negaflow::imaging::tone_safe_unit_rgb(pixel);
        expect(
            close(folded.red, pixel.red) && close(folded.green, pixel.green) &&
                close(folded.blue, pixel.blue) && folded.alpha == pixel.alpha,
            "a pixel already inside [0,1] is returned unchanged");
    }
}

// The point of the fold: a per-channel clamp would drag the hue toward whichever channel
// clipped. Holding luma and scaling chroma keeps the direction of the colour.
void test_out_of_gamut_keeps_hue_and_luma() {
    // A saturated red well inside the displayable brightness range but past 1.0 in one
    // channel — the case a per-channel clamp handles worst.
    const negaflow::core::Rgba32F saturated{1.2F, 0.35F, 0.1F, 1.0F};
    const negaflow::core::Rgba32F folded =
        negaflow::imaging::tone_safe_unit_rgb(saturated);
    expect(
        folded.red <= 1.0F && folded.green <= 1.0F && folded.blue <= 1.0F &&
            folded.red >= 0.0F && folded.green >= 0.0F && folded.blue >= 0.0F,
        "an out-of-gamut pixel lands inside [0,1]");
    expect(
        close(luma(folded), luma(saturated)),
        "brightness is held while the colour gives way");
    expect(
        folded.red > folded.green && folded.green > folded.blue,
        "the channel ordering of the original colour is preserved");
    expect(
        close(folded.red, 1.0F),
        "the chroma is scaled exactly until the first channel reaches the boundary");
    // A hard clamp would have left green at 0.35. Scaling the chroma moves it, which is
    // the whole difference between the two approaches.
    expect(
        !close(folded.green, saturated.green),
        "the fold scales chroma rather than clipping the offending channel alone");
}

// A pixel brighter than the display can show has no chroma left to keep: luma alone
// already fills the range. Pinning this so the collapse is a decision, not a surprise.
void test_over_bright_collapses_to_white() {
    const negaflow::core::Rgba32F over{1.6F, 0.9F, 0.35F, 1.0F};
    const negaflow::core::Rgba32F folded =
        negaflow::imaging::tone_safe_unit_rgb(over);
    expect(
        close(folded.red, 1.0F) && close(folded.green, 1.0F) &&
            close(folded.blue, 1.0F),
        "a pixel whose luma already exceeds the range folds to white");
}

void test_negative_channels_are_folded() {
    const negaflow::core::Rgba32F deep{0.4F, -0.25F, 0.1F, 1.0F};
    const negaflow::core::Rgba32F folded =
        negaflow::imaging::tone_safe_unit_rgb(deep);
    expect(
        folded.red >= 0.0F && folded.green >= 0.0F && folded.blue >= 0.0F,
        "a negative channel is folded up rather than left negative");
    expect(
        folded.red >= folded.blue && folded.blue >= folded.green,
        "folding a negative channel keeps the channel ordering");
}

// The dither has to be small enough to be invisible and centred so it does not shift the
// average tone; a biased or oversized offset would show as a haze over the whole preview.
void test_dither_is_bounded_and_deterministic() {
    float lowest = 1.0F;
    float highest = -1.0F;
    double total = 0.0;
    std::uint32_t count = 0U;
    for (std::uint32_t y = 0U; y < 64U; ++y) {
        for (std::uint32_t x = 0U; x < 64U; ++x) {
            for (std::uint32_t channel = 0U; channel < 3U; ++channel) {
                const float offset =
                    negaflow::imaging::display_dither_offset(x, y, channel);
                lowest = std::min(lowest, offset);
                highest = std::max(highest, offset);
                total += offset;
                ++count;
            }
        }
    }
    const float limit = 0.5F / 255.0F;
    expect(
        lowest >= -limit && highest <= limit,
        "the dither never exceeds half an 8-bit step");
    expect(
        std::abs(total / count) < limit * 0.05,
        "the dither is centred, so the average tone is unchanged");
    expect(
        negaflow::imaging::display_dither_offset(17U, 42U, 1U) ==
            negaflow::imaging::display_dither_offset(17U, 42U, 1U),
        "the dither is a function of the coordinate, so a preview is reproducible");
    expect(
        negaflow::imaging::display_dither_offset(17U, 42U, 0U) !=
            negaflow::imaging::display_dither_offset(17U, 42U, 1U),
        "channels get independent offsets, as the macOS display path does");
}

}  // namespace

int main() {
    test_in_gamut_is_identity();
    test_out_of_gamut_keeps_hue_and_luma();
    test_over_bright_collapses_to_white();
    test_negative_channels_are_folded();
    test_dither_is_bounded_and_deterministic();

    if (failures != 0) {
        std::cerr << failures << " display gamut map test(s) failed\n";
        return 1;
    }
    std::cout << "display gamut map tests passed\n";
    return 0;
}
