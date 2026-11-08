#include "negaflow/imaging/auto_adjust.h"
#include "negaflow/imaging/channel_headroom.h"
#include "negaflow/imaging/basic_tone_model.h"
#include "negaflow/core/pointwise.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
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

// 두 톤 그림: 위쪽 `top_rows` 줄은 `top`, 나머지는 `body`(회색).
[[nodiscard]] std::vector<std::uint8_t> two_tone_image(
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint8_t body,
    const std::uint8_t top,
    const std::uint32_t top_rows) {
    auto pixels = flat_image(width, height, body, body, body);
    for (std::uint32_t y = 0U; y < top_rows; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::size_t at = (static_cast<std::size_t>(y) * width + x) * 4U;
            pixels[at] = top; pixels[at + 1U] = top; pixels[at + 2U] = top;
        }
    }
    return pixels;
}

// 노출은 장면 키(Reinhard 자동 키, macOS `AutoAdjust.sceneKey`)로 양방향입니다. 어두운 장면은 올리고
// 밝은 장면은 내립니다. 예전에는 밝히는 쪽만 허용해 중립 현상본이 18% 보다 밝은 사진(macOS 사용자
// 카탈로그 398장 중 49%)에서 노출이 늘 0 이었습니다(2026-11-08).
void test_exposure_moves_both_ways_to_the_scene_key() {
    constexpr std::uint32_t width = 40U;
    constexpr std::uint32_t height = 40U;

    const auto dark = flat_image(width, height, 40U, 40U, 40U);
    const auto dark_tone = negaflow::imaging::auto_tone(stats_of(dark, width, height));
    expect(dark_tone.exposure > 0.0, "a dark frame is brightened");

    // 대부분 sRGB 200(선형 0.58), 위 4줄(10%)이 252 — 명부가 있는 밝은 장면입니다.
    const auto bright = two_tone_image(width, height, 200U, 252U, 4U);
    const auto bright_tone = negaflow::imaging::auto_tone(stats_of(bright, width, height));
    // 장면 키 r 0.08·s 8 에서 −0.50 스톱입니다(백점 회복 바닥은 −0.74).
    expect(bright_tone.exposure < -0.3, "a bright frame is pulled down toward its scene key");

    const auto clipped = flat_image(width, height, 255U, 255U, 255U);
    const auto clipped_tone =
        negaflow::imaging::auto_tone(stats_of(clipped, width, height));
    expect(
        clipped_tone.exposure < 0.0,
        "a genuinely clipped frame is pulled down");
}

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
            tone.contrast >= -0.15 && tone.contrast <= 0.55 &&
                tone.whites >= -1.0 && tone.whites <= 1.0 &&
                tone.blacks >= -1.0 && tone.blacks <= 0.15 &&
                tone.density >= -0.4 && tone.density <= 0.4,
            "every automatic value stays inside its documented range");
    }
}

// 흑백 프린트형(깊은 검정이 넓고 대비가 큰) 분포: 슬라이더가 닿지 않는 검정을 끌어올리려 섀도를
// 최대로 밀거나 대비를 크게 깎으면 계조가 무너집니다(macOS
// `testAutoToneKeepsDeepBlacksAndContrastOfPrintLikeMonochrome` 과 같은 분포).
void test_print_like_monochrome_keeps_blacks_and_contrast() {
    constexpr std::uint32_t width = 100U;
    constexpr std::uint32_t height = 100U;
    std::vector<std::uint8_t> pixels(static_cast<std::size_t>(width) * height * 4U, 0xFFU);
    const auto code_at = [](const double fraction) -> std::uint8_t {
        if (fraction < 0.12) { return static_cast<std::uint8_t>(1.0 + fraction / 0.12 * 2.99); }
        if (fraction < 0.40) { return static_cast<std::uint8_t>(4.0 + (fraction - 0.12) / 0.28 * 56.99); }
        if (fraction < 0.50) { return static_cast<std::uint8_t>(61.0 + (fraction - 0.40) / 0.10 * 88.99); }
        return static_cast<std::uint8_t>(150.0 + (fraction - 0.50) / 0.50 * 86.99);
    };
    const std::size_t count = static_cast<std::size_t>(width) * height;
    for (std::size_t index = 0U; index < count; ++index) {
        const std::uint8_t code = code_at(static_cast<double>(index) / static_cast<double>(count));
        pixels[index * 4U] = code;
        pixels[index * 4U + 1U] = code;
        pixels[index * 4U + 2U] = code;
    }
    const auto tone = negaflow::imaging::auto_tone(
        stats_of(pixels, width, height), negaflow::core::exposure_headroom_stops(true));
    expect(tone.shadows <= 0.15, "deep blacks do not lift the shadows");
    expect(tone.contrast >= -0.15, "a contrasty print is not flattened");
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
    // 잔차 클램프는 ±1(예전 슬라이더 끝)입니다 — 2026-10-14 ±0.6 에서 넓혔습니다(macOS `wbClamp`).
    expect(
        balance.warmth >= -1.0 && balance.warmth <= 1.0 &&
            balance.tint >= -1.0 && balance.tint <= 1.0,
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

// 미드가 키보다 밝으면 노출이 내려서 맞추고, 농도는 쓰지 않습니다(농도는 노출이 명부 여유나 한도에
// 막혀 못 밝힌 만큼만 밝힙니다, macOS `testAutoToneDarkensBrightMidtonesWithExposureNotDensity`).
void test_bright_midtones_use_exposure_not_density() {
    constexpr std::uint32_t width = 32U;
    constexpr std::uint32_t height = 32U;
    // 대부분 sRGB 158(선형 0.34), 위 1줄(3%)이 243(선형 0.9).
    const auto bright = two_tone_image(width, height, 158U, 243U, 1U);
    const auto tone = negaflow::imaging::auto_tone(stats_of(bright, width, height));
    expect(tone.exposure < -0.2, "a bright midtone is pulled down by exposure (about -0.26 at r 0.08, s 8)");
    expect(tone.density == 0.0, "density is not used when exposure reaches the key");
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

void test_luminance_confidence_and_color_scope() {
    const auto gray=stats_of(flat_image(64,64,118,118,118),64,64);
    const auto red=stats_of(flat_image(64,64,237,0,0),64,64);
    // 휘도가 같으면 휘도 모형은 같은 노출을 냅니다(2026-11-08 macOS `testEqualLuminanceColorsReceiveTheSameExposure`).
    const auto gray_tone=negaflow::imaging::auto_tone(gray), red_tone=negaflow::imaging::auto_tone(red);
    auto red_luminance_only=red;
    red_luminance_only.peak_samples.clear();
    expect(std::abs(gray_tone.exposure-negaflow::imaging::auto_tone(red_luminance_only).exposure)<0.03,
           "equal luminance colors receive the same luminance-model exposure");
    // R 을 지키려면 1.6 스톱을 내려야 해서 채널 한도가 노출에서 거둘 수 있는 몫(1 스톱)만 내줍니다.
    expect(std::abs(red_tone.exposure-(gray_tone.exposure-negaflow::imaging::auto_tone_channel_exposure_budget))<0.03,
           "the saturated red gives up exactly the channel exposure budget");
    expect(gray_tone.vibrance==0 && red_tone.vibrance==0,"tone does not propose color edits");
    const auto warm=negaflow::imaging::auto_white_balance(stats_of(flat_image(64,64,180,120,75),64,64));
    expect(std::abs(warm.warmth)<0.4,"unsupported warm subject is not pushed to the WB limit");
    const auto clipped=stats_of(flat_image(64,64,255,120,100),64,64);
    const auto safe=stats_of(flat_image(64,64,245,120,100),64,64);
    const auto wb=negaflow::imaging::auto_white_balance(clipped);
    expect(clipped.clipped_fraction==1 && wb.warmth==0 && wb.tint==0,"single channel clipping is excluded from WB evidence");
    const auto tiny = negaflow::imaging::auto_white_balance(stats_of(flat_image(4,4,180,120,75),4,4));
    expect(tiny.warmth == 0 && tiny.tint == 0, "missing neutral evidence does not trigger full-strength fallback");
    expect(negaflow::imaging::auto_tone_score(clipped,false)>negaflow::imaging::auto_tone_score(safe,false),"render objective penalizes clipped channels");
}

}  // namespace

// 원근 보정의 빈 곳(흰색, 알파 0)은 통계에 들어가지 않습니다 — macOS 와 같은 기준입니다.
void test_uncovered_area_is_not_measured() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 48U;
    auto pixels = flat_image(width, height, 90U, 77U, 64U);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = width / 2U; x < width; ++x) {
            const std::size_t at = (static_cast<std::size_t>(y) * width + x) * 4U;
            pixels[at] = 255U; pixels[at + 1U] = 255U; pixels[at + 2U] = 255U; pixels[at + 3U] = 0U;
        }
    }
    const auto photo_only = stats_of(pixels, width, height);
    expect(std::abs(photo_only.average_red - (90.0 / 255.0)) < 1.0e-6 &&
               std::abs(photo_only.average_blue - (64.0 / 255.0)) < 1.0e-6,
           "the uncovered white half is left out of the means");
    expect(photo_only.clipped_fraction == 0.0, "the uncovered area is not counted as clipped highlights");
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = width / 2U; x < width; ++x) {
            pixels[(static_cast<std::size_t>(y) * width + x) * 4U + 3U] = 255U;
        }
    }
    const auto baked = stats_of(pixels, width, height);
    expect(baked.average_red > 0.6, "control: the same white baked opaque pulls the mean up");
}

// 자동 톤은 기본 톤 커널의 합성 순서(대비 → 농도 → 명부 → 암부 → 흰색 → 검정)대로 역산합니다. 흰색이
// 한도(±1)에 걸리지 않으면 대비·명부가 옮긴 뒤의 백점(p995)이 정확히 확산 화이트에 닿습니다(macOS
// `testAutoToneWhitesLandOnDiffuseWhiteThroughTheComposedKernel`).
void test_auto_tone_whites_land_on_diffuse_white_through_the_composed_kernel() {
    namespace model = negaflow::imaging::basic_tone_model;
    negaflow::imaging::AutoAdjustStats stats{};
    for (std::size_t i = 30U; i <= 190U; ++i) { stats.luma_histogram[i] = 1.0 / 161.0; }
    stats.average_red = stats.average_green = stats.average_blue = 0.3;
    const auto result = negaflow::imaging::auto_tone(stats);
    expect(std::abs(result.contrast) > 0.05, "the scene exercises the contrast step");
    expect(std::abs(result.whites) < 0.999, "whites stay inside their auto limit");
    double accumulated = 0.0;
    double p995 = 1.0;
    for (std::size_t i = 0U; i < stats.luma_histogram.size(); ++i) {
        accumulated += stats.luma_histogram[i];
        if (accumulated >= 0.995) { p995 = static_cast<double>(i) / 255.0; break; }
    }
    const auto decode = [](const double v) { return v <= 0.04045 ? v / 12.92 : std::pow((v + 0.055) / 1.055, 2.4); };
    const auto encode = [](const double v) {
        return v <= 0.0031308 ? v * 12.92 : (1.055 * std::pow(v, 1.0 / 2.4)) - 0.055;
    };
    double t = encode(std::min(negaflow::core::exposed_luminance(
        decode(p995), result.exposure,
        static_cast<double>(negaflow::core::color_exposure_headroom_stops)), 1.0));
    t = model::contrast(t, result.contrast);
    t = model::density(t, result.density);
    t = model::highlight(t, result.highlights);
    t = model::shadow(t, result.shadows);
    t = model::whites(t, result.whites);
    t = model::blacks(t, result.blacks);
    expect(std::abs(t - encode(0.90)) < 1.0e-9, "the white point lands exactly on diffuse white");
}

int main() {
    test_statistics_describe_the_frame();
    test_luminance_confidence_and_color_scope();
    test_exposure_moves_both_ways_to_the_scene_key();
    test_recovery_sliders_move_one_way_only();
    test_print_like_monochrome_keeps_blacks_and_contrast();
    test_white_balance_leaves_neutral_alone();
    test_white_balance_cools_a_warm_cast_partially();
    test_bright_midtones_use_exposure_not_density();
    test_results_are_deterministic();
    test_invalid_input_is_refused();
    test_uncovered_area_is_not_measured();
    test_auto_tone_whites_land_on_diffuse_white_through_the_composed_kernel();

    if (failures != 0) {
        std::cerr << failures << " auto adjust test(s) failed\n";
        return 1;
    }
    std::cout << "auto adjust tests passed\n";
    return 0;
}
