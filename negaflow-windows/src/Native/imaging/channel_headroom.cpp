#include "negaflow/imaging/channel_headroom.h"

#include "negaflow/core/pointwise.h"
#include "negaflow/imaging/basic_tone_model.h"

#include <algorithm>
#include <array>
#include <cmath>

namespace negaflow::imaging::channel_headroom {
namespace {

[[nodiscard]] double srgb_decode(const double value) noexcept {
    return value <= 0.04045 ? value / 12.92 : std::pow((value + 0.055) / 1.055, 2.4);
}

[[nodiscard]] double srgb_encode(const double value) noexcept {
    return value <= 0.0031308 ? value * 12.92 : (1.055 * std::pow(value, 1.0 / 2.4)) - 0.055;
}

// `with_luma` 의 최대 채널: 어둡히면 채널비, 밝히면 같은 값을 더하고 1 에서 멈춥니다.
[[nodiscard]] double final_peak(const double peak, const double luma, const double toned) noexcept {
    return toned < luma && luma > 1.0e-6 ? peak * toned / luma : std::min(peak + toned - luma, 1.0);
}

// 올라서 여유를 둔 클리핑 기준을 넘었는가.
[[nodiscard]] bool pushed_past(const double before, const double after) noexcept {
    return after > before + 1.0e-6 && after + margin(after - before) >= clip_level;
}

[[nodiscard]] double shoulder_blend(const double stops, const double headroom_stops) noexcept {
    return stops > 0.0 && headroom_stops > 0.0 ? std::clamp(stops / headroom_stops, 0.0, 1.0) : 0.0;
}

struct PeakAfter final {
    double peak{0.0};
    double luma{0.0};
};

// 표본 하나의 노출·기본 톤 뒤 (최대 채널, 휘도). `with_luma` 는 휘도를 목표값에 둡니다.
[[nodiscard]] PeakAfter predicted(
    const AutoAdjustPeakSample& sample,
    const AutoToneResult& tone,
    const double gain,
    const double blend) noexcept {
    namespace model = negaflow::imaging::basic_tone_model;
    const double exposed = negaflow::core::exposed_luminance_at_gain(sample.luminance, gain, blend);
    const double peak = sample.luminance > 1.0e-9 ? sample.peak * exposed / sample.luminance : 0.0;
    const double luma = std::clamp(exposed, 0.0, 1.0);
    double t = model::contrast(srgb_encode(luma), tone.contrast);
    t = model::density(t, tone.density);
    t = model::highlight(t, tone.highlights);
    t = model::shadow(t, tone.shadows);
    t = model::whites(t, tone.whites);
    t = model::blacks(t, tone.blacks);
    const double toned = srgb_decode(std::clamp(t, 0.0, 1.0));
    return {final_peak(std::min(peak, 1.0), luma, toned), toned};
}

[[nodiscard]] double peak_after(
    const AutoAdjustPeakSample& sample,
    const AutoToneResult& tone,
    const double gain,
    const double blend) noexcept {
    return predicted(sample, tone, gain, blend).peak;
}

[[nodiscard]] const std::array<double, 256>& decode_table() noexcept {
    static const std::array<double, 256> table = [] {
        std::array<double, 256> values{};
        for (std::size_t i = 0U; i < values.size(); ++i) { values[i] = srgb_decode(static_cast<double>(i) / 255.0); }
        return values;
    }();
    return table;
}

}  // namespace

std::uint8_t luma_code(const std::uint8_t blue, const std::uint8_t green, const std::uint8_t red) noexcept {
    const auto& decode = decode_table();
    const double y = (0.2126 * decode[red]) + (0.7152 * decode[green]) + (0.0722 * decode[blue]);
    return static_cast<std::uint8_t>(std::clamp(std::lround(srgb_encode(y) * 255.0), 0L, 255L));
}

double margin(const double rise) noexcept {
    return std::min(maximum_margin, margin_floor + (margin_per_rise * std::max(rise, 0.0)));
}

double ceiling(const double before) noexcept {
    const double unbounded = (clip_level - margin_floor + (margin_per_rise * before)) / (1.0 + margin_per_rise);
    return unbounded - before >= (maximum_margin - margin_floor) / margin_per_rise ? safe_level : unbounded;
}

double measured_induced_clipping(
    const std::vector<AutoAdjustPeakSample>& neutral,
    const std::vector<AutoAdjustPeakSample>& measured) noexcept {
    if (neutral.empty() || neutral.size() != measured.size()) { return -1.0; }
    std::size_t count = 0U;
    for (std::size_t i = 0U; i < neutral.size(); ++i) {
        if (neutral[i].peak < clip_level && measured[i].peak >= clip_level && measured[i].luminance < diffuse_white) {
            ++count;
        }
    }
    return static_cast<double>(count) / static_cast<double>(neutral.size());
}

double measured_induced_clipping(const AutoAdjustStats& neutral, const AutoAdjustStats& measured) noexcept {
    if (!neutral.pixel_peaks.empty() && neutral.pixel_peaks.size() == measured.pixel_peaks.size()) {
        std::size_t count = 0U;
        if (measured.pixel_luma.size() == measured.pixel_peaks.size()) {
            for (std::size_t i = 0U; i < neutral.pixel_peaks.size(); ++i) {
                if (neutral.pixel_peaks[i] < 255U && measured.pixel_peaks[i] == 255U &&
                    measured.pixel_luma[i] <= diffuse_white_code) { ++count; }
            }
            return static_cast<double>(count) / static_cast<double>(neutral.pixel_peaks.size());
        }
    }
    return measured_induced_clipping(neutral.peak_samples, measured.peak_samples);
}

double corrected_induced_clipping(
    const std::vector<AutoAdjustPeakSample>& neutral,
    const std::vector<AutoAdjustPeakSample>& measured,
    const AutoToneResult& first,
    const AutoToneResult& candidate,
    const double exposure_headroom_stops) noexcept {
    if (neutral.empty() || neutral.size() != measured.size()) { return 0.0; }
    const double first_gain = std::exp2(first.exposure);
    const double first_blend = shoulder_blend(first.exposure, exposure_headroom_stops);
    const double candidate_gain = std::exp2(candidate.exposure);
    const double candidate_blend = shoulder_blend(candidate.exposure, exposure_headroom_stops);
    std::size_t count = 0U;
    for (std::size_t i = 0U; i < neutral.size(); ++i) {
        const AutoAdjustPeakSample& n = neutral[i];
        if (!(n.peak < clip_level)) { continue; }
        const PeakAfter at_first = predicted(n, first, first_gain, first_blend);
        const PeakAfter at_candidate = predicted(n, candidate, candidate_gain, candidate_blend);
        const double reach = at_first.peak - n.peak;
        const double share =
            std::abs(reach) > 1.0e-6 ? std::clamp((at_candidate.peak - n.peak) / reach, 0.0, 1.0) : 1.0;
        const double corrected = at_candidate.peak + ((measured[i].peak - at_first.peak) * share);
        const double luma = at_candidate.luma + ((measured[i].luminance - at_first.luma) * share);
        if (luma < diffuse_white && corrected + margin(std::abs(at_candidate.peak - at_first.peak)) >= clip_level) {
            ++count;
        }
    }
    return static_cast<double>(count) / static_cast<double>(neutral.size());
}

AutoAdjustPeakSample sample(const double red, const double green, const double blue) noexcept {
    const double r = std::max(red, 0.0), g = std::max(green, 0.0), b = std::max(blue, 0.0);
    return {(0.2126 * r) + (0.7152 * g) + (0.0722 * b), std::max({r, g, b})};
}

std::vector<AutoAdjustPeakSample> candidates(
    const std::vector<AutoAdjustPeakSample>& samples,
    const double max_stops,
    const double max_lift) {
    const double gain = std::exp2(max_stops);
    std::vector<AutoAdjustPeakSample> kept;
    for (const AutoAdjustPeakSample& s : samples) {
        if (!(s.peak < clip_level)) { continue; }
        const double luma = std::min(s.luminance * gain, 1.0);
        const double lifted = srgb_decode(std::min(srgb_encode(luma) + max_lift, 1.0));
        if (std::min(std::min(s.peak * gain, 1.0) + lifted - luma, 1.0) >= safe_level) { kept.push_back(s); }
    }
    return kept;
}

double predicted_peak(
    const AutoAdjustPeakSample& sample,
    const AutoToneResult& tone,
    const double exposure_headroom_stops) noexcept {
    return peak_after(sample, tone, std::exp2(tone.exposure), shoulder_blend(tone.exposure, exposure_headroom_stops));
}

double induced_clipping(
    const std::vector<AutoAdjustPeakSample>& samples,
    const std::size_t total,
    const AutoToneResult& tone,
    const double exposure_headroom_stops) noexcept {
    if (total == 0U) { return 0.0; }
    const double gain = std::exp2(tone.exposure);
    const double blend = shoulder_blend(tone.exposure, exposure_headroom_stops);
    std::size_t count = 0U;
    for (const AutoAdjustPeakSample& s : samples) {
        if (!(s.peak < clip_level)) { continue; }
        const PeakAfter after = predicted(s, tone, gain, blend);
        if (after.luma < diffuse_white && pushed_past(s.peak, after.peak)) { ++count; }
    }
    return static_cast<double>(count) / static_cast<double>(total);
}

double additional_clipping(
    const std::vector<AutoAdjustPeakSample>& samples,
    const std::size_t total,
    const double stops,
    const double whites) noexcept {
    namespace model = negaflow::imaging::basic_tone_model;
    if (total == 0U) { return 0.0; }
    const double gain = std::exp2(stops);
    std::size_t count = 0U;
    for (const AutoAdjustPeakSample& s : samples) {
        if (!(s.peak < clip_level)) { continue; }
        const double luma = std::min(s.luminance * gain, 1.0);
        const double toned = srgb_decode(std::clamp(model::whites(srgb_encode(luma), whites), 0.0, 1.0));
        if (toned < diffuse_white && pushed_past(s.peak, final_peak(std::min(s.peak * gain, 1.0), luma, toned))) {
            ++count;
        }
    }
    return static_cast<double>(count) / static_cast<double>(total);
}

}  // namespace negaflow::imaging::channel_headroom
