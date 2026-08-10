#pragma once

#include <array>
#include <cstdint>

namespace negaflow::imaging {

// Automatic develop settings, the classic way — histogram percentiles inverted through
// the transfer functions the tone stage actually uses, not a learned model.
//
// The caller renders a neutral develop (the target sliders at zero) to an 8-bit sRGB
// bitmap and hands the statistics here; the returned values are **assigned** to the
// sliders, not accumulated, so pressing auto twice gives the same answer as pressing it
// once.
//
// Every coefficient below is the inverse of one in `tone_mapping.cpp` and `color_model`.
// If those masks are recalibrated, these have to move with them or auto will aim at the
// wrong place.

inline constexpr std::size_t auto_adjust_histogram_bins = 256U;

struct AutoAdjustStats final {
    // sRGB gamma-domain means over the sampled grid.
    double average_red{0.0};
    double average_green{0.0};
    double average_blue{0.0};

    // Means over the near-neutral subset only, which is what a white balance estimate
    // should lean on when the scene provides one.
    double neutral_average_red{0.0};
    double neutral_average_green{0.0};
    double neutral_average_blue{0.0};
    double neutral_pixel_fraction{0.0};

    // The same neutral subset in linear light, because the colour gains being inverted
    // are linear multiplications.
    double neutral_linear_red{0.0};
    double neutral_linear_green{0.0};
    double neutral_linear_blue{0.0};

    // Minkowski p=6 linear mean (Shades-of-Gray). Weights bright pixels, which holds up
    // better than an arithmetic mean on scenes with one dominant colour.
    double minkowski_linear_red{0.0};
    double minkowski_linear_green{0.0};
    double minkowski_linear_blue{0.0};

    // Luma histogram in the sRGB gamma domain, normalised to sum to 1.
    std::array<double, auto_adjust_histogram_bins> luma_histogram{};
    double average_saturation{0.0};
};

struct AutoWhiteBalanceResult final {
    double warmth{0.0};
    double tint{0.0};
};

struct AutoToneResult final {
    double exposure{0.0};
    double contrast{0.0};
    double highlights{0.0};
    double shadows{0.0};
    double whites{0.0};
    double blacks{0.0};
    double density{0.0};
    double vibrance{0.0};
};

// Long side of the sampling grid. The statistics are percentile and mean based, so a
// small proxy is enough and keeps auto instant on a full scan.
inline constexpr std::uint32_t auto_adjust_sample_extent = 200U;

// Reads a BGRA8 bitmap — the same layout the preview produces — and reduces it to the
// statistics above. Returns false only for an empty or malformed buffer.
[[nodiscard]] bool compute_auto_adjust_stats(
    const std::uint8_t* pixels,
    std::uint32_t width,
    std::uint32_t height,
    std::size_t stride_bytes,
    AutoAdjustStats& stats) noexcept;

// Sends the near-neutral linear mean to grey by inverting ColorModel's warmth and tint
// gains. Deliberately partial: a full correction runs away into the opposite cast on
// scenes where the grey-world assumption fails, such as a sunset or a forest.
[[nodiscard]] AutoWhiteBalanceResult auto_white_balance(
    const AutoAdjustStats& stats) noexcept;

// Exposure, then whites/blacks, then highlights/shadows, then density, then contrast.
// Each step predicts where the previous one moved the percentiles, so the answers
// compose instead of fighting each other.
[[nodiscard]] AutoToneResult auto_tone(const AutoAdjustStats& stats) noexcept;

}  // namespace negaflow::imaging
