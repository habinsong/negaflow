#include "scanner_target_response.h"

#include "scanner_target_color.h"

#include <algorithm>
#include <cmath>
#include <cstddef>

namespace negaflow::imaging::scanner_target_detail {

[[nodiscard]] double relative_tone(
    const double value,
    const std::array<double, 9U>& xs,
    const std::array<double, 9U>& ys) noexcept {
    // The macOS cube authoring path fixes the two physical endpoints before it
    // interpolates the measured knots: (0, 0), knots, (1, 1).  Holding the
    // first/last knot flat here compresses SP-3000 (0.94...) and HS (0.995...)
    // highlights before the final output boundary.  Keep the same endpoint
    // interpolation rather than treating a measured knot as a clipping point.
    if (value <= xs.front()) {
        return clamp(value * ys.front() / std::max(xs.front(), 1.0e-9), 0.0, 1.0);
    }
    if (value >= xs.back()) {
        const double remaining = std::max(1.0 - xs.back(), 1.0e-9);
        return clamp(
            ys.back() + ((1.0 - ys.back()) * (value - xs.back()) / remaining),
            0.0,
            1.0);
    }
    for (std::size_t i = 1U; i < xs.size(); ++i) {
        if (value <= xs[i]) {
            const double f = (value - xs[i - 1U]) / std::max(xs[i] - xs[i - 1U], 1.0e-9);
            const double lo_delta = ys[i - 1U] - xs[i - 1U];
            const double hi_delta = ys[i] - xs[i];
            return clamp(value + lo_delta + ((hi_delta - lo_delta) * f), 0.0, 1.0);
        }
    }
    return ys.back();
}

[[nodiscard]] double chroma_band_gain(
    const double value,
    const TargetProfile& profile,
    const double keep) noexcept {
    const auto& bands = profile.chroma_bands;
    std::size_t hi = 0U;
    while (hi + 1U < bands.size() && value > bands[hi].luma) ++hi;
    double gain = bands[hi].gain;
    if (hi > 0U && value < bands[hi].luma) {
        const auto& lo_band = bands[hi - 1U];
        const auto& hi_band = bands[hi];
        const double f = (value - lo_band.luma) /
            std::max(hi_band.luma - lo_band.luma, 1.0e-6);
        gain = std::exp(std::log(lo_band.gain) +
            ((std::log(hi_band.gain) - std::log(lo_band.gain)) * f));
    }
    return std::pow(gain, keep);
}

[[nodiscard]] std::array<double, 2U> neutral_drift(
    const double value,
    const TargetProfile& profile,
    const double scale) noexcept {
    const auto count = profile.neutral_count;
    if (count == 0U) return {};
    if (value <= profile.neutral_bins[0U].luma) {
        return {profile.neutral_bins[0U].a * scale, profile.neutral_bins[0U].b * scale};
    }
    if (value >= profile.neutral_bins[count - 1U].luma) {
        return {profile.neutral_bins[count - 1U].a * scale,
                profile.neutral_bins[count - 1U].b * scale};
    }
    for (std::size_t i = 1U; i < count; ++i) {
        if (value <= profile.neutral_bins[i].luma) {
            const auto& lo = profile.neutral_bins[i - 1U];
            const auto& hi = profile.neutral_bins[i];
            const double f = (value - lo.luma) / std::max(hi.luma - lo.luma, 1.0e-6);
            return {(lo.a + ((hi.a - lo.a) * f)) * scale,
                    (lo.b + ((hi.b - lo.b) * f)) * scale};
        }
    }
    return {};
}

[[nodiscard]] std::array<double, 2U> hue_response(
    double hue,
    const TargetProfile& profile,
    const double scale,
    const double keep) noexcept {
    hue = std::fmod(hue + 360.0, 360.0);
    if (hue < 0.0) hue += 360.0;
    const std::size_t count = profile.hue_count;
    const HueAnchor* previous = &profile.hue_anchors[count - 1U];
    double previous_hue = previous->hue - 360.0;
    for (std::size_t i = 0U; i < count; ++i) {
        const auto& anchor = profile.hue_anchors[i];
        if (hue <= anchor.hue) {
            const double f = (hue - previous_hue) /
                std::max(anchor.hue - previous_hue, 1.0e-6);
            const double log_gain = std::log(previous->gain) +
                ((std::log(anchor.gain) - std::log(previous->gain)) * f);
            const double rotation = previous->rotation +
                ((anchor.rotation - previous->rotation) * f);
            return {std::exp(log_gain * scale * keep), rotation * scale};
        }
        previous = &anchor;
        previous_hue = anchor.hue;
    }
    const auto& first = profile.hue_anchors[0U];
    const double f = (hue - previous_hue) /
        std::max(first.hue + 360.0 - previous_hue, 1.0e-6);
    const double log_gain = std::log(previous->gain) +
        ((std::log(first.gain) - std::log(previous->gain)) * f);
    return {std::exp(log_gain * scale * keep),
            (previous->rotation + ((first.rotation - previous->rotation) * f)) * scale};
}

[[nodiscard]] Rgb transformed_srgb(
    const Rgb input,
    const TargetProfile& profile,
    const std::array<double, 9U>& tone,
    const double scale,
    const double chroma_keep,
    const bool monochrome,
    const bool reciprocal) noexcept {
    const double input_luma = luma(input);
    Lab lab = srgb_to_lab(input);
    const double mapped = relative_tone(input_luma, profile.tone_xs, tone);
    const double delta = mapped - input_luma;
    const double mapped_luma = clamp(input_luma + (reciprocal ? -delta : delta), 0.0, 1.0);
    const double neutral_l = srgb_to_lab({input_luma, input_luma, input_luma}).lightness;
    const double mapped_l = srgb_to_lab({mapped_luma, mapped_luma, mapped_luma}).lightness;
    lab.lightness += mapped_l - neutral_l;

    if (!monochrome) {
        const double chroma = std::hypot(lab.a, lab.b);
        const double color_taper = smoothstep(0.02, 0.10, input_luma) *
            (1.0 - smoothstep(0.90, 0.98, input_luma));
        if (chroma > 1.0e-6) {
            const double hue = std::atan2(lab.b, lab.a) * 180.0 / 3.14159265358979323846;
            auto response = hue_response(hue, profile, scale, chroma_keep);
            double band = std::pow(chroma_band_gain(input_luma, profile, chroma_keep), scale);
            if (reciprocal) {
                response[0] = 1.0 / std::max(response[0], 1.0e-9);
                response[1] = -response[1];
                band = 1.0 / std::max(band, 1.0e-9);
            }
            const double gain = std::exp(std::log(std::max(response[0] * band, 1.0e-9)) * color_taper);
            const double angle = std::atan2(lab.b, lab.a) +
                (response[1] * color_taper * 3.14159265358979323846 / 180.0);
            lab.a = chroma * gain * std::cos(angle);
            lab.b = chroma * gain * std::sin(angle);
        }

        auto drift = neutral_drift(input_luma, profile, scale);
        if (reciprocal) { drift[0] = -drift[0]; drift[1] = -drift[1]; }
        const double taper = smoothstep(0.03, 0.10, input_luma) *
            (1.0 - smoothstep(0.90, 0.97, input_luma));
        const double neutral_gate = 1.0 - smoothstep(8.0, 28.0, chroma);
        const double warm_gate = smoothstep(0.22, 0.52, input_luma);
        drift[0] = clamp(drift[0], -4.0, 4.0);
        drift[1] = clamp(drift[1], -4.0, 4.0);
        if (drift[0] > 0.0) drift[0] *= warm_gate;
        if (drift[1] > 0.0) drift[1] *= warm_gate;
        lab.a += drift[0] * taper * neutral_gate;
        lab.b += drift[1] * taper * neutral_gate;
    }
    return lab_to_extended_srgb(lab);
}

[[nodiscard]] double gamut_scale(
    const Rgb input,
    const Rgb candidate,
    const Rgb reciprocal) noexcept {
    double scale = 1.0;
    for (const Rgb output : {candidate, reciprocal}) {
        for (const auto channel : std::array<std::array<double, 2U>, 3U>{{
                 {input.red, output.red}, {input.green, output.green}, {input.blue, output.blue}}}) {
            const double delta = channel[1] - channel[0];
            if (delta > 0.0) scale = std::min(scale, (1.0 - channel[0]) / delta);
            else if (delta < 0.0) scale = std::min(scale, -channel[0] / delta);
        }
    }
    return clamp(scale, 0.0, 1.0);
}

}  // namespace negaflow::imaging::scanner_target_detail
