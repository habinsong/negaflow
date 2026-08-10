#include "negaflow/imaging/scanner_target_grade.h"

#include "negaflow/color/srgb_transfer.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <new>
#include <vector>

namespace negaflow::imaging {
namespace {

struct Rgb final { double red; double green; double blue; };
struct Lab final { double lightness; double a; double b; };
struct NeutralBin final { double luma; double a; double b; };
struct HueAnchor final { double hue; double gain; double rotation; };
struct ChromaBand final { double luma; double gain; };

struct TargetProfile final {
    std::array<double, 9U> tone_xs;
    std::array<double, 9U> tone_delta;
    std::array<NeutralBin, 10U> neutral_bins;
    std::size_t neutral_count;
    std::array<HueAnchor, 8U> hue_anchors;
    std::size_t hue_count;
    std::array<ChromaBand, 3U> chroma_bands;
};

constexpr std::array<double, 9U> design_tone_xs{{
    0.099852823, 0.247800528, 0.349190213, 0.537098730, 0.735356983,
    0.880825021, 0.954687172, 0.977691562, 0.995591277,
}};

constexpr TargetProfile noritsu_profile{
    design_tone_xs,
    {0.058, 0.070, 0.048, 0.022, 0.006, -0.008, -0.018, -0.018, -0.007},
    {{{0.16, 0.0, 0.0}, {0.34, 1.6, 1.2}, {0.52, 3.0, 2.0},
      {0.70, 2.4, 1.6}, {0.86, 0.9, 0.7}, {}}},
    5U,
    {{{20.0, 1.0, 0.0}, {55.0, 1.03, -4.0}, {95.0, 1.0, 0.0},
      {135.0, 1.05, -4.0}, {200.0, 1.0, 0.0}, {265.0, 0.94, 0.0},
      {330.0, 1.0, 0.0}}},
    7U,
    {{{0.165, 1.00}, {0.495, 0.98}, {0.83, 0.88}}},
};

constexpr TargetProfile sp3000_profile{
    {0.08, 0.16, 0.28, 0.40, 0.52, 0.64, 0.76, 0.86, 0.94},
    {0.020, 0.006, 0.014, 0.045, 0.094, 0.115, 0.112, 0.082, 0.015},
    {{{0.13, -3.2, 0.0}, {0.27, -3.2, 0.0}, {0.41, -3.0, 0.0},
      {0.55, -1.5, 0.0}, {0.69, 0.1, 0.0}, {0.83, 1.4, 0.0}}},
    6U,
    {{{20.0, 1.0, 0.0}, {55.0, 0.98, 2.85}, {95.0, 1.0, 0.0},
      {200.0, 1.0, 0.0}, {320.0, 1.0, 0.0}, {}, {}}},
    5U,
    {{{0.165, 1.00}, {0.495, 1.25}, {0.83, 1.60}}},
};

constexpr TargetProfile f135_profile{
    design_tone_xs,
    {-0.030, -0.020, 0.006, 0.030, 0.042, 0.022, 0.002, -0.005, -0.002},
    {{{0.16, 0.0, 0.0}, {0.36, 0.5, 1.8}, {0.55, 0.8, 3.2},
      {0.72, 0.8, 3.0}, {0.88, 0.5, 2.2}, {}}},
    5U,
    {{{20.0, 1.10, 0.0}, {55.0, 1.06, 2.2}, {95.0, 1.05, 0.0},
      {135.0, 1.0, -2.0}, {200.0, 1.0, 0.0}, {265.0, 1.04, 0.0},
      {330.0, 1.0, 0.0}}},
    7U,
    {{{0.165, 1.00}, {0.495, 1.22}, {0.83, 1.12}}},
};

constexpr TargetProfile hr_profile{
    design_tone_xs,
    {-0.036, -0.028, -0.008, -0.002, 0.024, 0.010, -0.004, -0.012, -0.005},
    {{{0.16, 0.0, -1.0}, {0.40, -0.3, -1.8}, {0.62, -0.4, -1.8},
      {0.88, -0.2, -1.0}, {}, {}}},
    4U,
    {{{20.0, 1.05, 0.0}, {55.0, 1.04, 1.0}, {95.0, 1.0, 0.0},
      {135.0, 1.06, -1.0}, {200.0, 1.0, 0.0}, {265.0, 1.18, 3.0},
      {330.0, 1.0, 0.0}}},
    7U,
    {{{0.165, 1.00}, {0.495, 1.12}, {0.83, 1.05}}},
};

// ScannerProfiles manifest v2 contains two negative-film groups with matched
// roll-label provenance and comparable image coverage on both devices:
// Kodak Ektar 100 and Kodak Portra 160. These fixed signatures are the bounded
// output of the reference pair compiler; no mutable profile path is consulted.
constexpr TargetProfile noritsu_relative_common{
    {0.040992690, 0.068636467, 0.110952885, 0.231135265, 0.461356130,
     0.602434501, 0.673245932, 0.702903753, 0.726243082},
    {0.005368627, 0.0, -0.008225069, -0.031864216, -0.043091667,
     -0.009348137, 0.0, 0.0, 0.0},
    {{{0.65, -0.241413048, 0.0}, {0.75, -0.357403587, 0.0},
      {0.85, -0.392416424, 0.0}, {0.95, -0.159487233, 0.0}}},
    4U,
    {{{1.510, 1.580079186, -1.316}, {49.452, 1.127292022, -0.966},
      {87.536, 1.011146397, 0.204}, {115.863, 1.142462720, 0.314},
      {239.010, 0.853430824, -2.152}, {269.820, 1.062593813, -2.104},
      {297.847, 1.043897910, -0.631}, {335.256, 1.820866727, 0.882}}},
    8U,
    {{{0.165, 1.0}, {0.495, 0.667542685}, {0.830, 1.0}}},
};

constexpr TargetProfile sp3000_relative_common{
    noritsu_relative_common.tone_xs,
    {-0.005368627, 0.0, 0.008225069, 0.031864216, 0.043091667,
     0.009348137, 0.0, 0.0, 0.0},
    {{{0.65, 1.097332035, 0.0}, {0.75, 1.624561757, 0.0},
      {0.85, 1.783711016, 0.0}, {0.95, 0.724941970, 0.0}}},
    4U,
    {{{1.510, 0.632879674, 1.316}, {49.452, 0.887081591, 0.966},
      {87.536, 0.988976476, -0.204}, {115.863, 0.875302084, -0.314},
      {239.010, 1.171741132, 2.152}, {269.820, 0.941093377, 2.104},
      {297.847, 0.957948082, 0.631}, {335.256, 0.549189013, -0.882}}},
    8U,
    {{{0.165, 1.0}, {0.495, 1.498031545}, {0.830, 1.0}}},
};

constexpr TargetProfile noritsu_relative_ektar{
    {0.032820015, 0.061002169, 0.095182748, 0.220279138, 0.461356130,
     0.629824394, 0.737468859, 0.787643686, 0.823172493},
    {0.009434314, 0.003363216, -0.012826804, -0.044263333, -0.048132353,
     -0.008871961, 0.017526078, 0.013607441, 0.012458039},
    {{{0.15, -0.025832260, 0.122499630}, {0.25, -0.134004118, 0.360909363},
      {0.35, -0.230518960, 0.742960643}, {0.45, -0.310061838, 0.899043842},
      {0.55, -0.385791237, 0.925915761}, {0.65, -0.480368435, 1.177401767},
      {0.75, -0.534426559, 1.030371153}, {0.85, -0.413308872, 0.421394049},
      {0.95, -0.087096769, -0.055315817}}},
    9U,
    noritsu_relative_common.hue_anchors,
    8U,
    {{{0.165, 0.937193868}, {0.495, 0.666062270}, {0.830, 0.625}}},
};

constexpr TargetProfile sp3000_relative_ektar{
    noritsu_relative_ektar.tone_xs,
    {-0.009434314, -0.003363216, 0.012826804, 0.044263333, 0.048132353,
     0.008871961, -0.017526078, -0.013607441, -0.012458039},
    {{{0.15, 0.117419361, -0.122499630}, {0.25, 0.609109629, -0.360909363},
      {0.35, 1.047813454, -0.742960643}, {0.45, 1.409371990, -0.899043842},
      {0.55, 1.753596532, -0.925915761}, {0.65, 2.183492887, -1.177401767},
      {0.75, 2.429211633, -1.030371153}, {0.85, 1.878676689, -0.421394049},
      {0.95, 0.395894406, 0.055315817}}},
    9U,
    sp3000_relative_common.hue_anchors,
    8U,
    {{{0.165, 1.067015091}, {0.495, 1.501361125}, {0.830, 1.6}}},
};

constexpr TargetProfile noritsu_relative_portra160{
    {0.047961434, 0.074892369, 0.123875675, 0.240031286, 0.461356130,
     0.579989935, 0.620618647, 0.633463870, 0.646814567},
    {0.001302941, -0.000889020, -0.003623333, -0.019465098, -0.038050980,
     -0.009824314, -0.004110784, -0.009550137, -0.007557647},
    {{{0.15, 0.367061111, -0.241870363}, {0.25, 0.954152466, -0.469524397},
      {0.35, 1.117312142, -0.579162891}, {0.45, 0.885820026, -0.634953174},
      {0.55, 0.347837260, -0.475171435}, {0.65, -0.002457660, -0.073732273},
      {0.75, -0.180380614, -0.022339788}, {0.85, -0.371523976, -0.639823780},
      {0.95, -0.231877697, 0.132226748}}},
    9U,
    noritsu_relative_common.hue_anchors,
    8U,
    {{{0.165, 1.074769449}, {0.495, 0.669026390}, {0.830, 1.213498786}}},
};

constexpr TargetProfile sp3000_relative_portra160{
    noritsu_relative_portra160.tone_xs,
    {-0.001302941, 0.000889020, 0.003623333, 0.019465098, 0.038050980,
     0.009824314, 0.004110784, 0.009550137, 0.007557647},
    {{{0.15, -0.367061111, 0.241870363}, {0.25, -0.954152466, 0.469524397},
      {0.35, -1.117312142, 0.579162891}, {0.45, -0.885820026, 0.634953174},
      {0.55, -0.347837260, 0.475171435}, {0.65, 0.011171182, 0.073732273},
      {0.75, 0.819911882, 0.022339788}, {0.85, 1.688745344, 0.639823780},
      {0.95, 1.053989534, -0.132226748}}},
    9U,
    sp3000_relative_common.hue_anchors,
    8U,
    {{{0.165, 0.930432104}, {0.495, 1.494709349}, {0.830, 0.824063453}}},
};

[[nodiscard]] const TargetProfile& profile_for(const ScannerTargetStyle target) noexcept {
    switch (target) {
    case ScannerTargetStyle::noritsu: return noritsu_profile;
    case ScannerTargetStyle::sp3000: return sp3000_profile;
    case ScannerTargetStyle::f135: return f135_profile;
    case ScannerTargetStyle::hr: return hr_profile;
    }
    return noritsu_profile;
}

[[nodiscard]] const TargetProfile* relative_profile_for(
    const ScannerTargetStyle target,
    const std::wstring_view profile_id) noexcept {
    if (target != ScannerTargetStyle::noritsu &&
        target != ScannerTargetStyle::sp3000) return nullptr;
    if (profile_id.empty()) {
        return target == ScannerTargetStyle::noritsu
            ? &noritsu_relative_common
            : &sp3000_relative_common;
    }
    if (target == ScannerTargetStyle::noritsu) {
        if (profile_id == L"noritsu__color-nega__kodak-ektar-100") {
            return &noritsu_relative_ektar;
        }
        if (profile_id == L"noritsu__color-nega__kodak-portra-160") {
            return &noritsu_relative_portra160;
        }
        return nullptr;
    }
    if (profile_id == L"sp-3000__color-nega__kodak-ektar-100") {
        return &sp3000_relative_ektar;
    }
    if (profile_id == L"sp-3000__color-nega__kodak-portra-160") {
        return &sp3000_relative_portra160;
    }
    return nullptr;
}

[[nodiscard]] double clamp(const double value, const double low, const double high) noexcept {
    return std::min(std::max(value, low), high);
}

[[nodiscard]] double smoothstep(
    const double low,
    const double high,
    const double value) noexcept {
    const double t = clamp((value - low) / std::max(high - low, 1.0e-9), 0.0, 1.0);
    return t * t * (3.0 - (2.0 * t));
}

[[nodiscard]] double srgb_encode(const double value) noexcept {
    return negaflow::color::linear_to_srgb_encoded(static_cast<float>(value));
}

[[nodiscard]] double srgb_decode(const double value) noexcept {
    return negaflow::color::srgb_encoded_to_linear(static_cast<float>(value));
}

[[nodiscard]] double lab_f(const double value) noexcept {
    constexpr double delta = 6.0 / 29.0;
    return value > delta * delta * delta
        ? std::cbrt(value)
        : value / (3.0 * delta * delta) + 4.0 / 29.0;
}

[[nodiscard]] double lab_f_inverse(const double value) noexcept {
    constexpr double delta = 6.0 / 29.0;
    return value > delta
        ? value * value * value
        : 3.0 * delta * delta * (value - 4.0 / 29.0);
}

[[nodiscard]] Lab srgb_to_lab(const Rgb value) noexcept {
    const double r = srgb_decode(value.red);
    const double g = srgb_decode(value.green);
    const double b = srgb_decode(value.blue);
    const double x = ((0.4124564 * r) + (0.3575761 * g) + (0.1804375 * b)) / 0.95047;
    const double y = (0.2126729 * r) + (0.7151522 * g) + (0.0721750 * b);
    const double z = ((0.0193339 * r) + (0.1191920 * g) + (0.9503041 * b)) / 1.08883;
    const double fx = lab_f(x);
    const double fy = lab_f(y);
    const double fz = lab_f(z);
    return {116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)};
}

[[nodiscard]] Rgb lab_to_extended_srgb(const Lab value) noexcept {
    const double fy = (value.lightness + 16.0) / 116.0;
    const double fx = fy + value.a / 500.0;
    const double fz = fy - value.b / 200.0;
    const double x = lab_f_inverse(fx) * 0.95047;
    const double y = lab_f_inverse(fy);
    const double z = lab_f_inverse(fz) * 1.08883;
    return {
        srgb_encode((3.2404542 * x) - (1.5371385 * y) - (0.4985314 * z)),
        srgb_encode((-0.9692660 * x) + (1.8760108 * y) + (0.0415560 * z)),
        srgb_encode((0.0556434 * x) - (0.2040259 * y) + (1.0572252 * z)),
    };
}

[[nodiscard]] double luma(const Rgb value) noexcept {
    return (0.2126 * value.red) + (0.7152 * value.green) + (0.0722 * value.blue);
}

[[nodiscard]] double percentile(std::vector<double>& values, const double fraction) {
    std::sort(values.begin(), values.end());
    const std::size_t index = static_cast<std::size_t>(
        clamp(static_cast<double>(values.size() - 1U) * fraction,
              0.0, static_cast<double>(values.size() - 1U)));
    return values[index];
}

struct InsetStats final { double median; double p05; double p95; };

[[nodiscard]] bool measure_inset(
    const negaflow::core::ImageView image,
    const double fraction,
    InsetStats& stats) {
    const std::uint32_t sample_width = std::min(160U, image.width);
    const std::uint32_t sample_height = std::max(
        1U, static_cast<std::uint32_t>(std::round(
            static_cast<double>(image.height) * sample_width / image.width)));
    const std::uint32_t inset_x = std::max(1U, static_cast<std::uint32_t>(sample_width * fraction));
    const std::uint32_t inset_y = std::max(1U, static_cast<std::uint32_t>(sample_height * fraction));
    std::vector<double> values;
    values.reserve(static_cast<std::size_t>(sample_width) * sample_height);
    for (std::uint32_t y = inset_y; y < std::max(inset_y + 1U, sample_height - inset_y); ++y) {
        const std::uint32_t source_y = std::min(
            image.height - 1U,
            static_cast<std::uint32_t>((static_cast<std::uint64_t>(y) * image.height) / sample_height));
        for (std::uint32_t x = inset_x; x < std::max(inset_x + 1U, sample_width - inset_x); ++x) {
            const std::uint32_t source_x = std::min(
                image.width - 1U,
                static_cast<std::uint32_t>((static_cast<std::uint64_t>(x) * image.width) / sample_width));
            const auto pixel = image.pixels[
                static_cast<std::size_t>(source_y) * image.stride_pixels + source_x];
            values.push_back(luma({
                srgb_encode(clamp(pixel.red, 0.0, 1.0)),
                srgb_encode(clamp(pixel.green, 0.0, 1.0)),
                srgb_encode(clamp(pixel.blue, 0.0, 1.0)),
            }));
        }
    }
    if (values.size() < 64U) return false;
    auto copy = values;
    stats.median = percentile(copy, 0.50);
    copy = values;
    stats.p05 = percentile(copy, 0.05);
    copy = std::move(values);
    stats.p95 = percentile(copy, 0.95);
    return true;
}

[[nodiscard]] double scene_anchor_weight(
    const negaflow::core::ImageView image,
    double& median) {
    if (image.width <= 8U || image.height <= 8U) {
        median = 0.5;
        return 0.0;
    }
    InsetStats outer{};
    if (!measure_inset(image, 0.06, outer)) {
        median = 0.5;
        return 0.0;
    }
    InsetStats chosen = outer;
    InsetStats inner{};
    if (measure_inset(image, 0.15, inner) &&
        outer.p95 - inner.p95 < 0.05 &&
        inner.p05 - outer.p05 > 0.30) {
        chosen = inner;
    }
    median = chosen.median;
    return 1.0 - smoothstep(0.45, 0.66, chosen.p95 - chosen.p05);
}

[[nodiscard]] double relative_tone(
    const double value,
    const std::array<double, 9U>& xs,
    const std::array<double, 9U>& ys) noexcept {
    if (value <= xs.front()) return ys.front();
    if (value >= xs.back()) return ys.back();
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

void apply_profile_grade(
    const negaflow::core::ImageView image,
    const TargetProfile& profile,
    const double strength,
    const double anchor_weight,
    const double scene_median,
    const bool monochrome) noexcept {
    const double chroma_keep = 1.0 - std::min(anchor_weight, 0.65);
    std::array<double, 9U> tone{};
    for (std::size_t i = 0U; i < tone.size(); ++i) {
        tone[i] = clamp(
            profile.tone_xs[i] + (profile.tone_delta[i] * strength),
            0.002,
            0.998);
    }
    const double clamped_median = clamp(
        scene_median, profile.tone_xs.front(), profile.tone_xs.back());
    const double mapped_median = relative_tone(
        clamped_median, profile.tone_xs, tone);
    const double offset = std::round(
        ((mapped_median - clamped_median) * anchor_weight) / 0.004) * 0.004;
    if (std::abs(offset) > 1.0e-9) {
        for (std::size_t i = 0U; i < tone.size(); ++i) {
            tone[i] = clamp(
                tone[i] - (offset * smoothstep(0.05, 0.25, profile.tone_xs[i])),
                0.002,
                0.998);
        }
    }

    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            auto& pixel = image.pixels[
                static_cast<std::size_t>(y) * image.stride_pixels + x];
            const Rgb encoded{
                srgb_encode(pixel.red),
                srgb_encode(pixel.green),
                srgb_encode(pixel.blue),
            };
            const double low = std::min({encoded.red, encoded.green, encoded.blue});
            const double high = std::max({encoded.red, encoded.green, encoded.blue});
            const double domain_weight = smoothstep(0.0, 0.02, low) *
                (1.0 - smoothstep(0.98, 1.0, high));
            if (domain_weight <= 0.0) continue;
            const Rgb candidate = transformed_srgb(
                encoded, profile, tone, strength, chroma_keep, monochrome, false);
            const Rgb reciprocal = transformed_srgb(
                encoded, profile, tone, strength, chroma_keep, monochrome, true);
            const double scale = gamut_scale(encoded, candidate, reciprocal);
            const Rgb graded{
                srgb_decode(encoded.red + ((candidate.red - encoded.red) * scale)),
                srgb_decode(encoded.green + ((candidate.green - encoded.green) * scale)),
                srgb_decode(encoded.blue + ((candidate.blue - encoded.blue) * scale)),
            };
            pixel.red = static_cast<float>(
                pixel.red + ((graded.red - pixel.red) * domain_weight));
            pixel.green = static_cast<float>(
                pixel.green + ((graded.green - pixel.green) * domain_weight));
            pixel.blue = static_cast<float>(
                pixel.blue + ((graded.blue - pixel.blue) * domain_weight));
        }
    }
}

void apply_noritsu_texture(
    const negaflow::core::ImageView image,
    std::vector<Rgb>& scratch) {
    constexpr std::array<double, 5U> weights{{0.037657, 0.239936, 0.444814, 0.239936, 0.037657}};
    const auto coordinate = [](const std::int64_t value, const std::uint32_t limit) {
        return static_cast<std::uint32_t>(std::clamp<std::int64_t>(value, 0, limit - 1U));
    };
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            Rgb sum{};
            for (std::int64_t k = -2; k <= 2; ++k) {
                const auto sample = image.pixels[static_cast<std::size_t>(y) * image.stride_pixels +
                    coordinate(static_cast<std::int64_t>(x) + k, image.width)];
                const double w = weights[static_cast<std::size_t>(k + 2)];
                sum.red += sample.red * w; sum.green += sample.green * w; sum.blue += sample.blue * w;
            }
            scratch[static_cast<std::size_t>(y) * image.width + x] = sum;
        }
    }
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            Rgb blur{};
            for (std::int64_t k = -2; k <= 2; ++k) {
                const Rgb sample = scratch[static_cast<std::size_t>(coordinate(
                    static_cast<std::int64_t>(y) + k, image.height)) * image.width + x];
                const double w = weights[static_cast<std::size_t>(k + 2)];
                blur.red += sample.red * w; blur.green += sample.green * w; blur.blue += sample.blue * w;
            }
            auto& pixel = image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x];
            const double low = std::min({pixel.red, pixel.green, pixel.blue});
            const double high = std::max({pixel.red, pixel.green, pixel.blue});
            const double original_luma = (0.2126 * pixel.red) + (0.7152 * pixel.green) + (0.0722 * pixel.blue);
            if (low < 0.0 || high > 1.0 || original_luma <= 1.0e-5) continue;
            const double blur_luma = clamp((0.2126 * blur.red) + (0.7152 * blur.green) +
                (0.0722 * blur.blue), 0.0, 1.0);
            const double y_original = srgb_encode(original_luma);
            const double y_blur = srgb_encode(blur_luma);
            const double floor_y = std::max(y_original * 0.45, std::min(y_original, 0.008));
            const double y_new = clamp(y_original + (0.6 * (y_original - y_blur)), floor_y, 1.0);
            double gain = srgb_decode(y_new) / original_luma;
            const double maximum = high * gain;
            if (maximum > 1.0) gain /= maximum;
            pixel.red = static_cast<float>(pixel.red * gain);
            pixel.green = static_cast<float>(pixel.green * gain);
            pixel.blue = static_cast<float>(pixel.blue * gain);
        }
    }
}

}  // namespace

negaflow::core::KernelStatus apply_scanner_target_grade(
    const negaflow::core::ImageView image,
    const ScannerTargetStyle target,
    const bool monochrome,
    const bool positive,
    const std::wstring_view scanner_profile_id,
    ScannerTargetGradeInfo& info) noexcept {
    info = {};
    const auto input = negaflow::core::ConstImageView{
        image.pixels, image.pixel_capacity, image.width, image.height, image.stride_pixels};
    const auto view_status = negaflow::core::validate_image_view(image);
    if (view_status != negaflow::core::KernelStatus::ok) return view_status;
    const auto finite_status = negaflow::core::validate_finite_pixels(input);
    if (finite_status != negaflow::core::KernelStatus::ok) return finite_status;

    try {
        const TargetProfile& profile = profile_for(target);
        const double strength = positive ? 0.5 : 1.0;
        double scene_median = 0.5;
        const double anchor_weight = scene_anchor_weight(image, scene_median);
        info.scene_anchor_weight = static_cast<float>(anchor_weight);

        if (monochrome) {
            for (std::uint32_t y = 0U; y < image.height; ++y) {
                for (std::uint32_t x = 0U; x < image.width; ++x) {
                    auto& pixel = image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x];
                    const float gray = (0.2126F * pixel.red) + (0.7152F * pixel.green) +
                        (0.0722F * pixel.blue);
                    pixel.red = gray; pixel.green = gray; pixel.blue = gray;
                }
            }
        }

        apply_profile_grade(
            image, profile, strength, anchor_weight, scene_median, monochrome);
        if (!positive) {
            if (const TargetProfile* const relative =
                    relative_profile_for(target, scanner_profile_id)) {
                apply_profile_grade(
                    image, *relative, 1.0, anchor_weight, scene_median, monochrome);
                info.relative_signature_applied = true;
            }
        }

        if (target == ScannerTargetStyle::noritsu) {
            std::vector<Rgb> scratch(
                static_cast<std::size_t>(image.width) * image.height);
            apply_noritsu_texture(image, scratch);
            info.texture_applied = true;
        }
    } catch (const std::bad_alloc&) {
        return negaflow::core::KernelStatus::buffer_too_small;
    }

    const auto output_status = negaflow::core::validate_finite_pixels(input);
    if (output_status != negaflow::core::KernelStatus::ok) {
        return negaflow::core::KernelStatus::non_finite_output;
    }
    info.applied = true;
    return negaflow::core::KernelStatus::ok;
}

}  // namespace negaflow::imaging
