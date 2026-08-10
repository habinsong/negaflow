#include "negaflow/imaging/auto_adjust.h"

#include <algorithm>
#include <cmath>

namespace negaflow::imaging {
namespace {

[[nodiscard]] double clamp_range(
    const double value,
    const double lower,
    const double upper) noexcept {
    return std::min(upper, std::max(lower, value));
}

[[nodiscard]] double smoothstep(
    const double lower,
    const double upper,
    const double value) noexcept {
    const double t = clamp_range((value - lower) / std::max(upper - lower, 1.0e-9), 0.0, 1.0);
    return t * t * (3.0 - (2.0 * t));
}

[[nodiscard]] double srgb_decode(const double value) noexcept {
    return value <= 0.04045 ? value / 12.92
                            : std::pow((value + 0.055) / 1.055, 2.4);
}

[[nodiscard]] double srgb_encode(const double value) noexcept {
    return value <= 0.0031308 ? value * 12.92
                              : (1.055 * std::pow(value, 1.0 / 2.4)) - 0.055;
}

// Both sides of the white-balance inversion. These are ColorModel's linear gains read
// backwards, so they must move together with that stage.
constexpr double warmth_red_gain = 0.18;
constexpr double warmth_green_gain = 0.03;
constexpr double tint_green_gain = 0.24;
constexpr double tint_opposite_gain = 0.12;

// Only 85% of the measured cast is removed. Neutralising fully overshoots into the
// opposite cast whenever the scene is legitimately dominated by one colour, and reads
// cold even when it does not.
constexpr double white_balance_strength = 0.85;
constexpr double white_balance_clamp = 0.60;
// Below roughly 1.5% channel-ratio error the frame is already neutral; moving it would
// be noise, not correction.
constexpr double white_balance_deadband = 0.015;
constexpr double neutral_subset_minimum_fraction = 0.03;

// Photometric mid grey, the same anchor the inversion redesign uses.
constexpr double mid_grey_linear = 0.18;
constexpr double diffuse_white_linear = 0.90;
// Black point target, following the ordinary 0.1-0.5% clipping practice.
constexpr double black_point_linear = 0.005;
// Pulling exposure down is for real clipping only. A handful of speculars is the
// highlight recovery slider's job, not a reason to darken the whole frame.
constexpr double clip_recovery_threshold = 0.05;
constexpr double auto_exposure_limit = 3.0;

}  // namespace

bool compute_auto_adjust_stats(
    const std::uint8_t* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::size_t stride_bytes,
    AutoAdjustStats& stats) noexcept {
    if (pixels == nullptr || width == 0U || height == 0U ||
        stride_bytes < static_cast<std::size_t>(width) * 4U) {
        return false;
    }

    // Sample on a bounded grid rather than the whole frame. Percentiles and means are
    // stable well below full resolution, and this keeps auto instant on a 17 MP scan.
    const std::uint32_t longest = std::max(width, height);
    const double scale = std::min(
        1.0,
        static_cast<double>(auto_adjust_sample_extent) / static_cast<double>(longest));
    const std::uint32_t sample_width =
        std::max(1U, static_cast<std::uint32_t>(static_cast<double>(width) * scale));
    const std::uint32_t sample_height =
        std::max(1U, static_cast<std::uint32_t>(static_cast<double>(height) * scale));

    std::array<double, 256> decode_table{};
    for (std::size_t index = 0U; index < decode_table.size(); ++index) {
        decode_table[index] = srgb_decode(static_cast<double>(index) / 255.0);
    }

    double sum_red = 0.0;
    double sum_green = 0.0;
    double sum_blue = 0.0;
    double sum_saturation = 0.0;
    double neutral_red = 0.0;
    double neutral_green = 0.0;
    double neutral_blue = 0.0;
    double neutral_linear_red = 0.0;
    double neutral_linear_green = 0.0;
    double neutral_linear_blue = 0.0;
    std::uint64_t neutral_count = 0U;
    double minkowski_red = 0.0;
    double minkowski_green = 0.0;
    double minkowski_blue = 0.0;

    stats.luma_histogram.fill(0.0);

    for (std::uint32_t y = 0U; y < sample_height; ++y) {
        const std::uint32_t source_y = static_cast<std::uint32_t>(
            (static_cast<std::uint64_t>(y) * height) / sample_height);
        const std::uint8_t* const row = pixels + (source_y * stride_bytes);
        for (std::uint32_t x = 0U; x < sample_width; ++x) {
            const std::uint32_t source_x = static_cast<std::uint32_t>(
                (static_cast<std::uint64_t>(x) * width) / sample_width);
            const std::uint8_t* const pixel = row + (static_cast<std::size_t>(source_x) * 4U);
            const std::uint8_t blue_byte = pixel[0];
            const std::uint8_t green_byte = pixel[1];
            const std::uint8_t red_byte = pixel[2];

            const double red = static_cast<double>(red_byte) / 255.0;
            const double green = static_cast<double>(green_byte) / 255.0;
            const double blue = static_cast<double>(blue_byte) / 255.0;
            // Decoded per pixel, not from the mean: the mean of a decode is not the
            // decode of a mean.
            const double linear_red = decode_table[red_byte];
            const double linear_green = decode_table[green_byte];
            const double linear_blue = decode_table[blue_byte];

            sum_red += red;
            sum_green += green;
            sum_blue += blue;

            const double luma = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue);
            const int bin = std::clamp(static_cast<int>(luma * 255.0), 0, 255);
            stats.luma_histogram[static_cast<std::size_t>(bin)] += 1.0;

            const double highest = std::max(red, std::max(green, blue));
            const double lowest = std::min(red, std::min(green, blue));
            const double saturation = highest > 1.0e-6 ? (highest - lowest) / highest : 0.0;
            sum_saturation += saturation;

            // Clipped and pure-black pixels carry no illuminant information.
            if (luma > 0.02 && luma < 0.99) {
                minkowski_red += std::pow(linear_red, 6.0);
                minkowski_green += std::pow(linear_green, 6.0);
                minkowski_blue += std::pow(linear_blue, 6.0);
            }
            // Near-neutral candidates only, so a saturated subject cannot masquerade as
            // the light source.
            if (saturation <= 0.22 && luma > 0.10 && luma < 0.90) {
                neutral_red += red;
                neutral_green += green;
                neutral_blue += blue;
                neutral_linear_red += linear_red;
                neutral_linear_green += linear_green;
                neutral_linear_blue += linear_blue;
                ++neutral_count;
            }
        }
    }

    const double total =
        static_cast<double>(sample_width) * static_cast<double>(sample_height);
    const double neutral_denominator =
        static_cast<double>(std::max<std::uint64_t>(neutral_count, 1U));
    const bool has_neutral_samples =
        neutral_count >= std::max<std::uint64_t>(
            16U,
            static_cast<std::uint64_t>(total) / 100U);

    stats.average_red = sum_red / total;
    stats.average_green = sum_green / total;
    stats.average_blue = sum_blue / total;
    stats.average_saturation = sum_saturation / total;
    for (double& bin : stats.luma_histogram) {
        bin /= total;
    }

    stats.neutral_average_red =
        has_neutral_samples ? neutral_red / neutral_denominator : stats.average_red;
    stats.neutral_average_green =
        has_neutral_samples ? neutral_green / neutral_denominator : stats.average_green;
    stats.neutral_average_blue =
        has_neutral_samples ? neutral_blue / neutral_denominator : stats.average_blue;
    stats.neutral_pixel_fraction = static_cast<double>(neutral_count) / total;

    // Without a neutral subset the linear figures fall back to decoding the gamma means.
    // The subset is low-saturation by construction, so the approximation is small.
    stats.neutral_linear_red = has_neutral_samples
        ? neutral_linear_red / neutral_denominator
        : srgb_decode(stats.neutral_average_red);
    stats.neutral_linear_green = has_neutral_samples
        ? neutral_linear_green / neutral_denominator
        : srgb_decode(stats.neutral_average_green);
    stats.neutral_linear_blue = has_neutral_samples
        ? neutral_linear_blue / neutral_denominator
        : srgb_decode(stats.neutral_average_blue);

    // Divided by every sampled pixel, not by the gated count: the gate removes a pixel's
    // contribution without removing it from the population.
    stats.minkowski_linear_red = std::pow(minkowski_red / std::max(1.0, total), 1.0 / 6.0);
    stats.minkowski_linear_green = std::pow(minkowski_green / std::max(1.0, total), 1.0 / 6.0);
    stats.minkowski_linear_blue = std::pow(minkowski_blue / std::max(1.0, total), 1.0 / 6.0);
    return true;
}

AutoWhiteBalanceResult auto_white_balance(const AutoAdjustStats& stats) noexcept {
    const bool use_neutral =
        stats.neutral_pixel_fraction >= neutral_subset_minimum_fraction;
    const double red = use_neutral ? stats.neutral_linear_red : stats.minkowski_linear_red;
    const double green =
        use_neutral ? stats.neutral_linear_green : stats.minkowski_linear_green;
    const double blue = use_neutral ? stats.neutral_linear_blue : stats.minkowski_linear_blue;
    if (red <= 1.0e-5 || green <= 1.0e-5 || blue <= 1.0e-5) {
        return {};
    }

    // Warmth: R(1 + 0.18w) = B(1 - 0.18w). A frame that is already warm gets a negative
    // warmth, which cools it.
    const double warmth_denominator = warmth_red_gain * (red + blue);
    double warmth = warmth_denominator > 1.0e-6 ? (blue - red) / warmth_denominator : 0.0;
    if (std::abs(blue - red) / std::max(red + blue, 1.0e-6) * 2.0 < white_balance_deadband) {
        warmth = 0.0;
    }
    warmth = clamp_range(
        warmth * white_balance_strength,
        -white_balance_clamp,
        white_balance_clamp);

    // Tint is solved on the residual after warmth, including warmth's own effect on green.
    const double warmed_red = red * (1.0 + (warmth_red_gain * warmth));
    const double warmed_green = green * (1.0 + (warmth_green_gain * warmth));
    const double warmed_blue = blue * (1.0 - (warmth_red_gain * warmth));
    const double mean = (warmed_red + warmed_blue) / 2.0;
    const double tint_denominator =
        (tint_green_gain * warmed_green) + (tint_opposite_gain * mean);
    double tint = tint_denominator > 1.0e-6 ? (mean - warmed_green) / tint_denominator : 0.0;
    if (std::abs(mean - warmed_green) / std::max(mean + warmed_green, 1.0e-6) * 2.0 <
        white_balance_deadband) {
        tint = 0.0;
    }
    tint = clamp_range(
        tint * white_balance_strength,
        -white_balance_clamp,
        white_balance_clamp);

    return {warmth, tint};
}

AutoToneResult auto_tone(const AutoAdjustStats& stats) noexcept {
    AutoToneResult result{};

    const auto percentile = [&stats](const double fraction) noexcept {
        double accumulated = 0.0;
        for (std::size_t index = 0U; index < stats.luma_histogram.size(); ++index) {
            accumulated += stats.luma_histogram[index];
            if (accumulated >= fraction) {
                return static_cast<double>(index) / 255.0;
            }
        }
        return 1.0;
    };

    const double clip_high = stats.luma_histogram[255];
    const double clip_low = stats.luma_histogram[0];
    // Black and shadow points use percentiles thick enough to step over a scan's black
    // frame border. A thinner one treats the border as the shadow point and hauls the
    // real shadows up with it.
    const double black_srgb = percentile(0.02);
    const double shadow_srgb = percentile(0.08);
    const double mid_srgb = percentile(0.50);
    const double p975_srgb = percentile(0.975);
    const double p98_srgb = percentile(0.98);
    const double p995_srgb = percentile(0.995);
    const double p10_srgb = percentile(0.10);
    const double p90_srgb = percentile(0.90);

    // Exposure works in linear light because it is a physical 2^ev multiply; everything
    // after it is inverted in the gamma domain the tone masks are defined in.
    // It only ever brightens — pulling a snow scene down to grey is the classic
    // grey-world failure, and darkening is reserved for real clipping.
    double exposure = clamp_range(
        std::log2(mid_grey_linear / std::max(srgb_decode(mid_srgb), 1.0e-4)),
        0.0,
        auto_exposure_limit);
    const double headroom_cap =
        std::max(0.0, std::log2(0.95 / std::max(srgb_decode(p98_srgb), 1.0e-4)));
    exposure = std::min(exposure, headroom_cap);
    if (clip_high >= clip_recovery_threshold) {
        exposure = clamp_range(
            std::log2(0.92 / std::max(srgb_decode(p995_srgb), 1.0e-4)),
            -auto_exposure_limit,
            0.0);
    }
    result.exposure = exposure;

    const double gain = std::pow(2.0, exposure);
    const auto after_exposure = [gain](const double srgb) noexcept {
        return srgb_encode(std::min(srgb_decode(srgb) * gain, 1.0));
    };
    const double black_after = after_exposure(black_srgb);
    const double shadow_after = after_exposure(shadow_srgb);
    const double mid_after = after_exposure(mid_srgb);
    const double p975_after = after_exposure(p975_srgb);
    const double p995_after = after_exposure(p995_srgb);

    // Endpoint stretch, inverted through the whites and blacks masks. The mask floors
    // stop a target that lands where the mask is nearly zero from demanding an enormous
    // slider value.
    const double diffuse_white_srgb = srgb_encode(diffuse_white_linear);
    const double black_point_srgb = srgb_encode(black_point_linear);
    const double white_mask = std::max(smoothstep(0.68, 0.92, p995_after), 0.25);
    result.whites = clamp_range(
        (diffuse_white_srgb - p995_after) / (0.12 * white_mask),
        -1.0,
        1.0);
    if (clip_high > 0.001) {
        result.whites = std::min(result.whites, 0.0);
    }
    // Blacks mainly pulls lifted blacks back down. Lifting already-deep blacks up to the
    // target washes the image out, so that direction is capped hard while recovery is not.
    const double black_mask = std::max(
        smoothstep(0.0, 0.03, black_after) * (1.0 - smoothstep(0.14, 0.30, black_after)),
        0.25);
    result.blacks = clamp_range(
        (black_point_srgb - black_after) / (0.06 * black_mask),
        -1.0,
        0.15);

    // Highlights and shadows are recovery only, one direction each. The pure end bins
    // include a scan's black border and specular dots, so their contribution is capped.
    const double highlight_mask = std::max(smoothstep(0.55, 0.80, p975_after), 0.3);
    result.highlights = clamp_range(
        (-std::min(clip_high, 0.05) * 4.0) -
            (std::max(0.0, p975_after - 0.89) * 0.5 / (0.10 * highlight_mask)),
        -1.0,
        0.0);
    const double shadow_mask = std::max(
        smoothstep(0.02, 0.08, shadow_after) *
            (1.0 - smoothstep(0.32, 0.46, shadow_after)),
        0.3);
    result.shadows = clamp_range(
        (std::min(clip_low, 0.05) * 4.0) +
            (std::max(0.0, 0.10 - shadow_after) / (0.10 * shadow_mask)),
        0.0,
        0.8);

    // Density finishes the midtone that exposure could not reach once the highlight
    // headroom capped it, without touching the highlights.
    const double mid_residual = mid_after - srgb_encode(mid_grey_linear);
    if (std::abs(mid_residual) > 0.02) {
        const double mid_mask = std::max(
            smoothstep(0.18, 0.36, mid_after) * (1.0 - smoothstep(0.58, 0.76, mid_after)),
            0.3);
        result.density = clamp_range(mid_residual / (0.10 * mid_mask), -0.4, 0.4);
    }

    // Contrast targets a perceptual spread, measured after the exposure move.
    const double p10_after = after_exposure(p10_srgb);
    const double p90_after = after_exposure(p90_srgb);
    result.contrast = clamp_range(
        (0.52 - (p90_after - p10_after)) * 1.15,
        -0.45,
        0.55);

    // Vibrance only ever increases, which is what every other auto tool does too.
    result.vibrance = clamp_range((0.42 - stats.average_saturation) * 1.0, 0.0, 0.6);
    return result;
}

}  // namespace negaflow::imaging
