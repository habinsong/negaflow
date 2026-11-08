// 자동 톤의 채널 한도 시험입니다(2026-11-08, macOS `ChannelHeadroomTests` 와 같은 계약). 휘도 목표가 채도 높은
// 색의 최대 채널을 1 위로 밀지 않습니다. 합성 화상만 쓰고, 톤은 실제 CPU 톤 단계
// (`apply_working_tone_adjustments` — 노출 숄더 → 기본 톤)로 그려서 잽니다.

#include "negaflow/core/pointwise.h"
#include "negaflow/imaging/auto_adjust.h"
#include "negaflow/imaging/channel_headroom.h"
#include "negaflow/imaging/working_tone_adjuster.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

namespace {

using negaflow::imaging::AutoAdjustStats;
using negaflow::imaging::AutoToneResult;
using negaflow::imaging::WorkingImage;
namespace headroom = negaflow::imaging::channel_headroom;

int failures = 0;

void expect(const bool condition, const std::string& message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] double srgb_encode(const double value) {
    return value <= 0.0031308 ? value * 12.92 : (1.055 * std::pow(value, 1.0 / 2.4)) - 0.055;
}

[[nodiscard]] double srgb_decode(const double value) {
    return value <= 0.04045 ? value / 12.92 : std::pow((value + 0.055) / 1.055, 2.4);
}

[[nodiscard]] std::uint8_t to_byte(const double linear) {
    return static_cast<std::uint8_t>(
        std::lround(std::clamp(srgb_encode(std::clamp(linear, 0.0, 1.0)), 0.0, 1.0) * 255.0));
}

[[nodiscard]] WorkingImage make_image(const std::uint32_t width, const std::uint32_t height, const auto& colour_at) {
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::array<double, 3> c = colour_at(x, y);
            image.pixels[static_cast<std::size_t>(y) * width + x] = {
                static_cast<float>(c[0]), static_cast<float>(c[1]), static_cast<float>(c[2]), 1.0F};
        }
    }
    return image;
}

[[nodiscard]] std::vector<std::uint8_t> to_bgra(const WorkingImage& image) {
    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(image.width) * image.height * 4U);
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const auto& pixel = image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x];
            const std::size_t at = (static_cast<std::size_t>(y) * image.width + x) * 4U;
            bytes[at] = to_byte(pixel.blue);
            bytes[at + 1U] = to_byte(pixel.green);
            bytes[at + 2U] = to_byte(pixel.red);
            bytes[at + 3U] = 0xFFU;
        }
    }
    return bytes;
}

[[nodiscard]] AutoAdjustStats stats_of(const WorkingImage& image) {
    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(image.width) * image.height * 4U);
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const auto& pixel = image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x];
            const std::size_t at = (static_cast<std::size_t>(y) * image.width + x) * 4U;
            bytes[at] = to_byte(pixel.blue);
            bytes[at + 1U] = to_byte(pixel.green);
            bytes[at + 2U] = to_byte(pixel.red);
            bytes[at + 3U] = 0xFFU;
        }
    }
    AutoAdjustStats stats{};
    expect(negaflow::imaging::compute_auto_adjust_stats(
               bytes.data(), image.width, image.height, static_cast<std::size_t>(image.width) * 4U, stats),
           "statistics are computed");
    return stats;
}

[[nodiscard]] WorkingImage develop(const WorkingImage& image, const AutoToneResult& tone) {
    negaflow::imaging::WorkingToneAdjustParameters parameters{};
    parameters.exposure_stops = static_cast<float>(tone.exposure);
    parameters.basic.contrast = static_cast<float>(tone.contrast);
    parameters.basic.density = static_cast<float>(tone.density);
    parameters.basic.highlights = static_cast<float>(tone.highlights);
    parameters.basic.shadows = static_cast<float>(tone.shadows);
    parameters.basic.whites = static_cast<float>(tone.whites);
    parameters.basic.blacks = static_cast<float>(tone.blacks);
    auto adjusted = negaflow::imaging::apply_working_tone_adjustments(image, parameters);
    expect(adjusted.status == negaflow::imaging::WorkingToneAdjustStatus::ok, "tone develop succeeds");
    return std::move(adjusted.image);
}

// 중립 현상본에서 1 에 닿지 않던 칸 중 조정 뒤에 닿은 칸의 비율(같은 칸끼리 비교).
[[nodiscard]] double induced(const AutoAdjustStats& before, const AutoAdjustStats& after) {
    expect(before.peak_samples.size() == after.peak_samples.size(), "the same sampling grid");
    const std::size_t n = std::min(before.peak_samples.size(), after.peak_samples.size());
    std::size_t count = 0U;
    for (std::size_t i = 0U; i < n; ++i) {
        if (before.peak_samples[i].peak < headroom::clip_level && after.peak_samples[i].peak >= headroom::clip_level) {
            ++count;
        }
    }
    return n == 0U ? 0.0 : static_cast<double>(count) / static_cast<double>(n);
}

[[nodiscard]] AutoAdjustStats luminance_only(AutoAdjustStats stats) {
    stats.peak_samples.clear();
    return stats;
}

const double color_headroom = static_cast<double>(negaflow::core::color_exposure_headroom_stops);

// 채도 높은 빨강(선형 0.40, 0.03, 0.03 — 휘도 0.11)이 화면 25% 인 장면. 휘도로는 명부 여유가 3 스톱이라 예전 노출은
// 키까지 밝혀 빨강 전체의 R 을 1 에 붙였습니다. 지키는 데 1 스톱 안이면 노출은 빨강이 닿기 직전에서 멈추고 모자란
// 중간톤은 농도가 채웁니다(macOS `testExposureStopsBeforeSaturatedMidtonesClip`).
void test_exposure_stops_before_saturated_midtones_clip() {
    const auto scene = [](const double darkest, const double brightest) {
        return make_image(400U, 200U, [darkest, brightest](const std::uint32_t x, const std::uint32_t y) {
            if (y < 50U) { return std::array<double, 3>{0.40, 0.03, 0.03}; }
            const double v = darkest + ((brightest - darkest) * static_cast<double>(x) / 400.0);
            return std::array<double, 3>{v, v, v};
        });
    };
    const WorkingImage image = scene(0.03, 0.16);
    const AutoAdjustStats neutral = stats_of(image);
    expect(!neutral.peak_samples.empty(), "peak samples are measured");
    const AutoToneResult luma = negaflow::imaging::auto_tone(luminance_only(neutral));
    expect(induced(neutral, stats_of(develop(image, luma))) > 0.10,
           "the scene exercises the case (a luminance-only proposal clips the red)");
    const AutoToneResult tone = negaflow::imaging::auto_tone(neutral);
    const double measured = induced(neutral, stats_of(develop(image, tone)));
    expect(measured <= headroom::allowance + 0.002,
           "exposure keeps the red below clipping (" + std::to_string(measured) + ", ev " + std::to_string(tone.exposure) + ")");
    expect(tone.exposure > 0.5, "exposure is not abandoned");
    expect(tone.exposure < luma.exposure, "exposure is lower than the luminance-only proposal");
    expect(tone.exposure > luma.exposure - negaflow::imaging::auto_tone_channel_exposure_budget,
           "protection fits within the exposure budget");
    expect(tone.density < 0.0, "density fills the midtones the exposure could not reach");

    // 더 어두운 장면이라 1 스톱보다 더 내려야 하면 1 스톱만 내주고 클리핑을 받아들입니다.
    const AutoAdjustStats dim = stats_of(scene(0.01, 0.10));
    const AutoToneResult dim_luma = negaflow::imaging::auto_tone(luminance_only(dim));
    expect(dim_luma.exposure - std::log2(headroom::safe_level / 0.40) > negaflow::imaging::auto_tone_channel_exposure_budget,
           "the dim scene needs more than the budget");
    const AutoToneResult dim_tone = negaflow::imaging::auto_tone(dim);
    expect(std::abs(dim_tone.exposure - (dim_luma.exposure - negaflow::imaging::auto_tone_channel_exposure_budget)) <= 0.01,
           "exposure stops at the budget (" + std::to_string(dim_tone.exposure) + " vs luma " + std::to_string(dim_luma.exposure) + ")");
    expect(std::abs(negaflow::imaging::auto_tone_channel_exposure_floor(dim) -
                    (dim_luma.exposure - negaflow::imaging::auto_tone_channel_exposure_budget)) <= 1e-9,
           "the closed-loop floor is the luminance exposure minus the budget");
    expect(negaflow::imaging::auto_tone_remaining_key_budget(dim, dim_tone.exposure) <= 1e-9,
           "the first pass used the whole key budget");
    expect(std::abs(negaflow::imaging::auto_tone_remaining_key_budget(dim, dim_luma.exposure) -
                    negaflow::imaging::auto_tone_channel_exposure_budget) <= 1e-9,
           "a first proposal at the luminance exposure leaves the whole budget");
}

// 밝은 장면의 노란 면(선형 0.80, 0.70, 0.08 — 휘도 0.68, 화면 3%)은 휘도 백점입니다. 흰색이 휘도를 확산
// 화이트(0.90)로 올리면 R 이 1 을 넘었습니다. 이제 흰색은 노랑이 닿기 직전까지만 올립니다.
void test_whites_stop_at_the_channel_clip_point() {
    const WorkingImage image = make_image(400U, 200U, [](const std::uint32_t x, const std::uint32_t y) {
        if (y < 6U) { return std::array<double, 3>{0.80, 0.70, 0.08}; }
        const double v = 0.05 + (0.50 * static_cast<double>(x) / 400.0);
        return std::array<double, 3>{v, v, v};
    });
    const AutoAdjustStats neutral = stats_of(image);
    const AutoToneResult luma = negaflow::imaging::auto_tone(luminance_only(neutral));
    expect(luma.whites > 0.0, "the luminance-only proposal lifts whites");
    expect(induced(neutral, stats_of(develop(image, luma))) > 0.02, "the luminance-only proposal clips the yellow");
    const AutoToneResult tone = negaflow::imaging::auto_tone(neutral);
    const double measured = induced(neutral, stats_of(develop(image, tone)));
    expect(measured <= headroom::allowance + 0.002,
           "whites stop before the yellow clips (" + std::to_string(measured) + ", whites " + std::to_string(tone.whites) + ")");
    expect(tone.whites > 0.0, "whites is not abandoned");
    AutoToneResult more = tone;
    more.whites += 0.02;
    expect(headroom::induced_clipping(neutral.peak_samples, neutral.peak_samples.size(), more, color_headroom) >
               headroom::allowance,
           "whites is the largest value that fits");
}

// 예측은 실제 톤 단계와 맞습니다 — 노출·흰색·농도·대비·명부를 섞은 값에서 칸마다 최대 채널이 같습니다.
void test_prediction_matches_the_tone_pipeline() {
    const std::array<std::array<double, 3>, 4> colours{{
        {0.40, 0.03, 0.03}, {0.80, 0.70, 0.08}, {0.05, 0.30, 0.60}, {0.55, 0.50, 0.45},
    }};
    const WorkingImage image = make_image(480U, 240U, [&colours](const std::uint32_t x, const std::uint32_t y) {
        const double scale = 0.25 + (0.75 * static_cast<double>(x) / 480.0);
        const auto& c = colours[std::min<std::size_t>(colours.size() - 1U, y * colours.size() / 240U)];
        return std::array<double, 3>{c[0] * scale, c[1] * scale, c[2] * scale};
    });
    const AutoAdjustStats neutral = stats_of(image);
    const std::array<std::array<double, 5>, 5> cases{{
        {0.6, 0.0, 0.0, 0.0, 0.0}, {0.4, 0.6, 0.0, 0.0, 0.0}, {0.0, 0.8, -0.4, 0.3, 0.0},
        {1.0, 0.3, 0.0, 0.0, -0.6}, {-0.5, 0.5, 0.0, -0.15, 0.0},
    }};
    for (const auto& c : cases) {
        AutoToneResult tone{};
        tone.exposure = c[0]; tone.whites = c[1]; tone.density = c[2]; tone.contrast = c[3]; tone.highlights = c[4];
        const AutoAdjustStats after = stats_of(develop(image, tone));
        expect(after.peak_samples.size() == neutral.peak_samples.size(), "the same sampling grid");
        double worst = 0.0;
        for (std::size_t i = 0U; i < std::min(after.peak_samples.size(), neutral.peak_samples.size()); ++i) {
            const double predicted = headroom::predicted_peak(neutral.peak_samples[i], tone, color_headroom);
            worst = std::max(worst, std::abs(predicted - after.peak_samples[i].peak));
        }
        // 8 비트 표본의 명부 한 코드(선형 0.009)보다 작습니다 — safe_level 의 여유(0.015)가 덮습니다.
        expect(worst < 0.009, "per-cell peak prediction error " + std::to_string(worst) + " at ev " + std::to_string(c[0]));
    }
}

// 미리 거른 표본으로 센 값은 전체 표본으로 센 값과 같습니다(자동 톤이 쓰는 노출·리프트 범위 안).
void test_candidate_pruning_keeps_the_count() {
    const std::array<std::array<double, 3>, 6> colours{{
        {0.9, 0.1, 0.05}, {0.7, 0.65, 0.1}, {0.1, 0.4, 0.8}, {0.5, 0.5, 0.5}, {0.95, 0.9, 0.85}, {0.2, 0.6, 0.2},
    }};
    const WorkingImage image = make_image(480U, 240U, [&colours](const std::uint32_t x, const std::uint32_t y) {
        const double t = static_cast<double>(x) / 480.0;
        const auto& c = colours[y * 6U / 240U];
        const double s = 0.05 + (0.95 * t);
        return std::array<double, 3>{c[0] * s, c[1] * s, c[2] * s};
    });
    const AutoAdjustStats stats = stats_of(image);
    const auto kept = headroom::candidates(stats.peak_samples, 1.5, headroom::maximum_auto_lift);
    expect(kept.size() < stats.peak_samples.size(), "pruning removes samples that cannot reach the limit");
    const std::array<std::array<double, 6>, 4> cases{{
        {1.5, 0.55, -0.4, 0.8, 1.0, 0.15}, {0.7, 0.2, -0.2, 0.3, 0.5, 0.0}, {0.0, -0.15, 0.0, 0.0, 1.0, -1.0},
        {-1.0, 0.55, -0.4, 0.8, 1.0, 0.15},
    }};
    for (const auto& c : cases) {
        AutoToneResult tone{};
        tone.exposure = c[0]; tone.contrast = c[1]; tone.density = c[2]; tone.shadows = c[3]; tone.whites = c[4];
        tone.blacks = c[5];
        const std::size_t total = stats.peak_samples.size();
        expect(headroom::induced_clipping(kept, total, tone, color_headroom) ==
                   headroom::induced_clipping(stats.peak_samples, total, tone, color_headroom),
               "pruned count equals the full count at ev " + std::to_string(c[0]));
    }
}

// 폐루프의 더 밝히는 몫: 중립 현상본이 없으면 잰 클리핑(원본에서 날아간 1%)을 모두 이미 쓴 몫으로 봐 새 클리핑을
// 하나도 만들지 않는 데까지(0.4% 의 R 0.90 화소가 정합니다) 줄입니다. 중립 현상본이 있으면 줄이지 않습니다.
void test_refinement_raises_only_within_the_channel_budget() {
    AutoAdjustStats stats{};
    stats.luma_histogram[30] = 0.686;
    stats.luma_histogram[100] = 0.30;
    stats.luma_histogram[150] = 0.004;
    stats.luma_histogram[255] = 0.01;
    stats.clipped_fraction = 0.01;
    const double dark = srgb_decode(30.0 / 255.0), red = srgb_decode(100.0 / 255.0), bright = srgb_decode(150.0 / 255.0);
    stats.peak_samples.assign(686U, {dark, dark});
    stats.peak_samples.insert(stats.peak_samples.end(), 300U, {red, 0.70});
    stats.peak_samples.insert(stats.peak_samples.end(), 4U, {bright, 0.90});
    stats.peak_samples.insert(stats.peak_samples.end(), 10U, {1.0, 1.0});
    const AutoToneResult first{};
    expect(negaflow::imaging::refine_auto_tone(first, luminance_only(stats)).exposure > 1.0,
           "the key asks for a large exposure raise");
    const AutoToneResult blind = negaflow::imaging::refine_auto_tone(first, stats);
    expect(std::abs(blind.exposure - std::log2(headroom::ceiling(0.90) / 0.90)) <= 0.01,
           "without the neutral render the raise stops before any new clip (" + std::to_string(blind.exposure) + ")");
    // 중립 현상본이 있으면 폐루프 한 번은 키 보정을 그대로 내고, 넘치는지는 셸이 그린 결과로 이분합니다.
    const AutoToneResult aware = negaflow::imaging::refine_auto_tone(first, stats, color_headroom, &stats);
    expect(std::abs(aware.exposure - negaflow::imaging::refine_auto_tone(first, luminance_only(stats)).exposure) <= 1e-9,
           "with the neutral render the key raise is left to the measured closed loop (" + std::to_string(aware.exposure) + ")");
}

[[nodiscard]] AutoAdjustStats stats_from_samples(const std::vector<negaflow::imaging::AutoAdjustPeakSample>& samples) {
    AutoAdjustStats stats{};
    for (const auto& sample : samples) {
        const auto bin = static_cast<std::size_t>(std::lround(srgb_encode(std::min(sample.luminance, 1.0)) * 255.0));
        stats.luma_histogram[std::min<std::size_t>(255U, bin)] += 1.0 / static_cast<double>(samples.size());
        if (sample.peak >= headroom::clip_level) { stats.clipped_fraction += 1.0 / static_cast<double>(samples.size()); }
    }
    stats.peak_samples = samples;
    return stats;
}

// 모형 밖 단계(스캐너 타깃 같은)가 확인 렌더에서 밝은 노랑을 1 에 붙이면, 폐루프는 그 칸의 잰 값으로 예측을
// 바로잡아 흰색부터 거둡니다(1 에 묶인 칸은 하한이라 덜 거둘 수 있고, 나머지는 셸의 이분이 맡습니다). 초과량은
// 칸마다 맞대어 셉니다.
void test_refinement_withdraws_what_the_rendered_target_clips() {
    std::vector<negaflow::imaging::AutoAdjustPeakSample> neutral_samples(900U, {0.20, 0.20});
    neutral_samples.insert(neutral_samples.end(), 100U, {0.60, 0.80});
    const AutoAdjustStats neutral = stats_from_samples(neutral_samples);
    const auto render = [&neutral_samples](const AutoToneResult& tone) {
        std::vector<negaflow::imaging::AutoAdjustPeakSample> samples;
        for (const auto& n : neutral_samples) {
            const double peak = headroom::predicted_peak(n, tone, color_headroom);
            samples.push_back({n.luminance, n.peak > 0.5 ? std::min(peak + (0.6 * (peak - n.peak)), 1.0) : peak});
        }
        return stats_from_samples(samples);
    };
    AutoToneResult first{};
    first.exposure = 0.3;
    first.whites = 0.4;
    const AutoAdjustStats measured = render(first);
    expect(negaflow::imaging::auto_tone_channel_excess(neutral, measured) > 0.05, "the target clips the yellow");
    const AutoToneResult refined = negaflow::imaging::refine_auto_tone(first, measured, color_headroom, &neutral);
    expect(refined.whites < first.whites, "whites are withdrawn first (" + std::to_string(refined.whites) + ")");
    expect(refined.exposure >= 0.0 && refined.exposure <= first.exposure, "exposure is only lowered toward zero");
    AutoToneResult floor = first;
    floor.whites = 0.0;
    floor.exposure = 0.0;
    expect(negaflow::imaging::auto_tone_channel_excess(neutral, render(floor)) == 0.0, "the floor fits");
    AutoAdjustStats other = measured;
    other.peak_samples.pop_back();
    expect(negaflow::imaging::auto_tone_channel_excess(neutral, other) < 0.0, "mismatched grids report no excess");
}

// 폐루프의 실측은 화소 단위입니다: 한 화소 건너 채도 높은 질감(꽃잎·잎사귀 같은)은 칸 평균에서는 1 에 못 닿아도
// 화소는 255 에 닿습니다. 칸으로만 세면 이 클리핑이 묻힙니다. 같은 무늬가 무채색이면 휘도가 확산 화이트를 넘는
// 반사광이라 세지 않습니다(macOS `testMeasuredClippingCountsPixelsNotCellAverages`).
void test_measured_clipping_counts_pixels_not_cell_averages() {
    const auto checker = [](const std::array<double, 3> bright, const std::array<double, 3> dark) {
        return make_image(400U, 200U, [bright, dark](const std::uint32_t x, const std::uint32_t y) {
            return (x + y) % 2U == 0U ? bright : dark;
        });
    };
    const WorkingImage image = checker({0.985, 0.45, 0.05}, {0.45, 0.20, 0.02});
    const AutoAdjustStats neutral = stats_of(image);
    AutoToneResult brighter{};
    brighter.exposure = 0.15;
    const WorkingImage lifted = develop(image, brighter);
    const AutoAdjustStats measured = stats_of(lifted);
    expect(headroom::measured_induced_clipping(neutral.peak_samples, measured.peak_samples) == 0.0,
           "cell averages do not reach the clip level");
    expect(headroom::measured_induced_clipping(neutral, measured) > 0.4, "half of the pixels reach 255");
    expect(negaflow::imaging::auto_tone_channel_excess(neutral, measured) > 0.0, "the pixel clipping is an excess");
    const auto a = to_bgra(image);
    const auto b = to_bgra(lifted);
    const double direct = negaflow::imaging::induced_pixel_clipping(
        a.data(), static_cast<std::size_t>(image.width) * 4U, b.data(), static_cast<std::size_t>(lifted.width) * 4U,
        image.width, image.height);
    expect(std::abs(direct - headroom::measured_induced_clipping(neutral, measured)) < 1e-12,
           "the direct bitmap comparison equals the statistics comparison");
    AutoAdjustStats light{};
    expect(negaflow::imaging::compute_auto_adjust_luminance_stats(
               b.data(), lifted.width, lifted.height, static_cast<std::size_t>(lifted.width) * 4U, light) &&
               light.luma_histogram == measured.luma_histogram && light.clipped_fraction == measured.clipped_fraction &&
               negaflow::imaging::auto_tone_scene_key(light) == negaflow::imaging::auto_tone_scene_key(measured),
           "the luminance-only statistics match the full statistics");

    const WorkingImage specular = checker({0.97, 0.97, 0.97}, {0.55, 0.55, 0.55});
    AutoToneResult whites{};
    whites.whites = 0.6;
    const AutoAdjustStats specular_neutral = stats_of(specular);
    const AutoAdjustStats specular_measured = stats_of(develop(specular, whites));
    expect(std::count(specular_measured.pixel_peaks.begin(), specular_measured.pixel_peaks.end(), std::uint8_t{255}) >
               static_cast<std::ptrdiff_t>(specular_measured.pixel_peaks.size() / 3U),
           "the neutral texture does reach 255");
    expect(headroom::measured_induced_clipping(specular_neutral, specular_measured) == 0.0,
           "neutral highlights above diffuse white may clip");
}

// macOS `ChannelHeadroomTests.parityFixture` 와 같은 식으로 만든 고정 통계에서 같은 값을 냅니다(macOS
// `testChannelGuardParityFixture` 의 기대값). 채널 한도가 노출을 0.638 → 0.335 로 줄이고 나머지를 다시 푸는 경로입니다.
void test_channel_guard_matches_macos() {
    std::vector<negaflow::imaging::AutoAdjustPeakSample> samples;
    for (int k = 0; k < 600; ++k) {
        const double v = srgb_decode(static_cast<double>(20 + (k % 60)) / 255.0);
        samples.push_back({v, v});
    }
    samples.insert(samples.end(), 250U, {srgb_decode(95.0 / 255.0), 0.75});
    samples.insert(samples.end(), 140U, {srgb_decode(205.0 / 255.0), 0.90});
    samples.insert(samples.end(), 10U, {srgb_decode(230.0 / 255.0), 0.86});
    AutoAdjustStats stats{};
    for (const auto& sample : samples) {
        const auto bin = static_cast<std::size_t>(std::lround(srgb_encode(sample.luminance) * 255.0));
        stats.luma_histogram[std::min<std::size_t>(255U, bin)] += 1.0 / static_cast<double>(samples.size());
    }
    stats.peak_samples = samples;
    const AutoToneResult tone = negaflow::imaging::auto_tone(stats);
    const auto near = [](const double a, const double b) { return std::abs(a - b) <= 1e-6; };
    expect(near(tone.exposure, 0.335171208) && near(tone.contrast, -0.15) && near(tone.density, -0.4) &&
               near(tone.highlights, 0.0) && near(tone.shadows, 0.0) && near(tone.whites, -0.045220701) &&
               near(tone.blacks, -0.588419083),
           "the channel guard matches macOS (ev " + std::to_string(tone.exposure) + ", whites " +
               std::to_string(tone.whites) + ", blacks " + std::to_string(tone.blacks) + ")");
}

}  // namespace

int main() {
    test_channel_guard_matches_macos();
    test_measured_clipping_counts_pixels_not_cell_averages();
    test_exposure_stops_before_saturated_midtones_clip();
    test_whites_stop_at_the_channel_clip_point();
    test_prediction_matches_the_tone_pipeline();
    test_candidate_pruning_keeps_the_count();
    test_refinement_raises_only_within_the_channel_budget();
    test_refinement_withdraws_what_the_rendered_target_clips();
    if (failures != 0) {
        std::cerr << failures << " channel headroom test(s) failed\n";
        return 1;
    }
    std::cout << "channel headroom tests passed\n";
    return 0;
}
