#include "negaflow/imaging/scene_correction.h"
#include "negaflow/core/negative_inversion.h"

#include <array>
#include <cmath>
#include <cstddef>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {

void expect(const bool condition, const char* const message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

negaflow::core::ImageView view(
    std::vector<negaflow::core::Rgba32F>& pixels,
    const std::uint32_t width,
    const std::uint32_t height) {
    return {pixels.data(), pixels.size(), width, height, width};
}

void test_disabled_is_identity() {
    constexpr std::uint32_t width = 16U;
    constexpr std::uint32_t height = 16U;
    std::vector<negaflow::core::Rgba32F> pixels(
        width * height, {0.2F, 0.3F, 0.4F, 1.0F});
    const auto before = pixels;
    negaflow::imaging::SceneCorrectionInfo info{};
    expect(
        negaflow::imaging::apply_scene_correction(view(pixels, width, height), {}, info) ==
            negaflow::core::KernelStatus::ok,
        "disabled scene correction succeeds");
    for (std::size_t index = 0U; index < pixels.size(); ++index) {
        expect(
            pixels[index].red == before[index].red &&
                pixels[index].green == before[index].green &&
                pixels[index].blue == before[index].blue &&
                pixels[index].alpha == before[index].alpha,
            "disabled scene correction is exact identity");
    }
}

void test_negative_auto_correction_changes_cast_range() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 32U;
    std::vector<negaflow::core::Rgba32F> pixels(width * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float ramp = static_cast<float>(x) / static_cast<float>(width - 1U);
            pixels[static_cast<std::size_t>(y) * width + x] = {
                0.08F + (ramp * 0.52F),
                0.12F + (ramp * 0.58F),
                0.16F + (ramp * 0.62F),
                1.0F,
            };
        }
    }
    negaflow::imaging::SceneCorrectionInfo info{};
    const negaflow::imaging::SceneCorrectionParameters parameters{
        true, false, true};
    expect(
        negaflow::imaging::apply_scene_correction(
            view(pixels, width, height), parameters, info) ==
            negaflow::core::KernelStatus::ok,
        "negative auto correction succeeds");
    expect(info.auto_levels_applied, "Auto Levels applies to a narrow-range scan");
    expect(pixels.front().alpha == 1.0F, "scene correction preserves alpha");
    expect(pixels.back().red > 0.8F, "Auto Levels expands the visible range");

    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float ramp = static_cast<float>(x) / static_cast<float>(width - 1U);
            pixels[static_cast<std::size_t>(y) * width + x] = {
                0.12F + (ramp * 0.30F),
                0.28F + (ramp * 0.30F),
                0.44F + (ramp * 0.30F),
                1.0F,
            };
        }
    }
    const negaflow::imaging::SceneCorrectionParameters neutral_only{
        false, true, true};
    expect(
        negaflow::imaging::apply_scene_correction(
            view(pixels, width, height), neutral_only, info) ==
            negaflow::core::KernelStatus::ok,
        "Neutral Balance succeeds");
    expect(info.neutral_balance_applied, "Neutral Balance applies to a cast scan");
}

void test_linear_negative_levels_reach_output_targets() {
    constexpr std::uint32_t width = 96U, height = 64U;
    for (const bool monochrome : {false, true}) {
        for (const float exposure_scale : {1.0F, 0.02F}) {
            std::vector<negaflow::core::Rgba32F> pixels(width * height);
            for (std::uint32_t y = 0; y < height; ++y) {
                for (std::uint32_t x = 0; x < width; ++x) {
                    const float t = (x < 32U ? 0.05F : (x < 64U ? 0.18F : 1.1F)) * exposure_scale;
                    pixels[y * width + x] = {t, t, t, 1.0F};
                }
            }
            negaflow::imaging::SceneCorrectionParameters parameters{true, false, true};
            parameters.linear_negative_output = true;
            parameters.monochrome = monochrome;
            negaflow::imaging::SceneCorrectionInfo info{};
            expect(negaflow::imaging::apply_scene_correction(view(pixels, width, height), parameters, info) ==
                negaflow::core::KernelStatus::ok && info.auto_levels_applied, "linear levels apply");
            expect(negaflow::core::apply_negative_output_tone(view(pixels, width, height), 0, monochrome) ==
                negaflow::core::KernelStatus::ok, "linear levels pass through the output curve");
            expect(std::abs(pixels[height / 2U * width + 16U].red - 0.003F) < 1e-5F,
                "auto levels black target survives the output curve");
            expect(std::abs(pixels[height / 2U * width + 80U].red - 0.95F) < 1e-5F,
                "auto levels white target survives the output curve");
        }
    }
}

void test_linear_negative_base_does_not_dominate_neutral_evidence() {
    constexpr std::uint32_t width = 192U, height = 96U;
    std::vector<negaflow::core::Rgba32F> pixels(width * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const bool border = x < 24U || x >= width - 24U || y < 12U || y >= height - 12U;
            const float t = x < width / 3U ? 0.06F : (x < width * 2U / 3U ? 0.18F : 0.50F);
            pixels[static_cast<std::size_t>(y) * width + x] = border
                ? negaflow::core::Rgba32F{0.0F, 0.0F, 0.0F, 1.0F}
                : negaflow::core::Rgba32F{t * 0.65F, t, t * 1.45F, 1.0F};
        }
    }
    negaflow::imaging::SceneCorrectionParameters parameters{false, true, true};
    negaflow::imaging::SceneCorrectionInfo info{};
    expect(negaflow::imaging::apply_scene_correction(view(pixels, width, height), parameters, info) ==
               negaflow::core::KernelStatus::ok && info.neutral_balance_applied,
           "bare base does not become the neutral axis of a linear negative");
    const auto p = pixels[(height / 2U) * width + width / 2U];
    const double before = std::max(std::abs(std::log(0.65)), std::abs(std::log(1.45)));
    const double after = std::max(std::abs(std::log(p.red / p.green)), std::abs(std::log(p.blue / p.green)));
    expect(after < before * 0.55, "neutral correction reduces the cast despite a neutral film border");
}

void test_changed_gamma_and_base_inputs_do_not_reuse_previous_correction() {
    constexpr std::uint32_t width = 64U, height = 32U;
    negaflow::imaging::SceneCorrectionInfo reused_info{};
    for (const double gamma : {1.8, 2.4}) {
        for (const double scale : {0.75, 1.25}) {
            for (const bool levels : {false, true}) {
                for (const bool color : {false, true}) {
                    std::vector<negaflow::core::Rgba32F> first(width * height);
                    for (std::size_t i = 0; i < first.size(); ++i) {
                        const double t = static_cast<double>(i % width) / (width - 1U);
                        first[i] = {static_cast<float>(std::pow(0.12 + 0.5 * t, gamma) * scale),
                            static_cast<float>(std::pow(0.2 + 0.5 * t, gamma) * scale),
                            static_cast<float>(std::pow(0.28 + 0.5 * t, gamma) * scale), 1.0F};
                    }
                    auto fresh = first;
                    negaflow::imaging::SceneCorrectionInfo fresh_info{};
                    const negaflow::imaging::SceneCorrectionParameters parameters{levels, color, true};
                    expect(negaflow::imaging::apply_scene_correction(view(first, width, height), parameters, reused_info)
                        == negaflow::core::KernelStatus::ok, "changed input correction succeeds");
                    expect(negaflow::imaging::apply_scene_correction(view(fresh, width, height), parameters, fresh_info)
                        == negaflow::core::KernelStatus::ok, "fresh input correction succeeds");
                    expect(reused_info.auto_levels_applied == fresh_info.auto_levels_applied &&
                        reused_info.neutral_balance_applied == fresh_info.neutral_balance_applied,
                        "correction status must not leak across changed inputs");
                    for (std::size_t i = 0; i < first.size(); ++i) {
                        expect(first[i].red == fresh[i].red && first[i].green == fresh[i].green &&
                            first[i].blue == fresh[i].blue && first[i].alpha == 1.0F,
                            "changed gamma/base input must match fresh scene correction pixels");
                    }
                }
            }
        }
    }
}

// ── 자동 색상 v2 (macOS AutoColorNeutralAxisTests 와 같은 픽스처) ─────────────────────

// 로그 간격 톤 14 개(0.005…0.70) — 휘도대가 여럿 생깁니다. 톤마다 16 화소 폭.
constexpr std::size_t wedge_tones = 14U;

[[nodiscard]] double wedge_tone(const std::size_t index) {
    return 0.005 * std::pow(0.70 / 0.005, static_cast<double>(index) / 13.0);
}

template <typename Channel>
[[nodiscard]] std::vector<negaflow::core::Rgba32F> wedge(Channel channel, const std::uint32_t height = 16U) {
    const std::uint32_t width = static_cast<std::uint32_t>(wedge_tones * 16U);
    std::vector<negaflow::core::Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const auto c = channel(wedge_tone(x / 16U), y);
            pixels[static_cast<std::size_t>(y) * width + x] = {
                static_cast<float>(c[0]), static_cast<float>(c[1]), static_cast<float>(c[2]), 1.0F};
        }
    }
    return pixels;
}

[[nodiscard]] negaflow::core::Rgba32F tone_center(
    const std::vector<negaflow::core::Rgba32F>& pixels, const std::size_t tone, const std::uint32_t row) {
    const std::uint32_t width = static_cast<std::uint32_t>(wedge_tones * 16U);
    return pixels[static_cast<std::size_t>(row) * width + tone * 16U + 8U];
}

void balance(std::vector<negaflow::core::Rgba32F>& pixels, const std::uint32_t height = 16U) {
    negaflow::imaging::SceneCorrectionInfo info{};
    const negaflow::imaging::SceneCorrectionParameters parameters{false, true, true};
    expect(negaflow::imaging::apply_scene_correction(
               view(pixels, static_cast<std::uint32_t>(wedge_tones * 16U), height), parameters, info) ==
               negaflow::core::KernelStatus::ok,
           "neutral balance succeeds");
}

[[nodiscard]] double red_blue(const negaflow::core::Rgba32F p) { return std::log2(p.red / p.blue); }
[[nodiscard]] double green_cast(const negaflow::core::Rgba32F p) {
    return std::log2(p.green / std::sqrt(static_cast<double>(p.red) * p.blue));
}

// 균일 캐스트(광원·WB 성분)는 모든 톤에서 걷혀야 합니다. 예전 감마 보정은 암부 과보정·명부 미보정.
void test_uniform_cast_is_removed_at_every_tone() {
    auto pixels = wedge([](const double t, std::uint32_t) {
        return std::array<double, 3>{0.80 * t, 1.0 * t, 1.20 * t};
    });
    balance(pixels);
    for (std::size_t tone = 0U; tone < wedge_tones; ++tone) {
        if (wedge_tone(tone) < 0.02) continue;
        const auto p = tone_center(pixels, tone, 8U);
        expect(std::abs(red_blue(p)) < 0.05, "uniform cast R/B removed");
        expect(std::abs(green_cast(p)) < 0.05, "uniform cast G removed");
    }
}

// 끝점이 중립이고 미드만 휜 캐스트는 미드를 고치되 화이트(0.70) 중립을 깨지 않습니다.
void test_midtone_bow_is_removed_without_breaking_white() {
    auto pixels = wedge([](const double t, std::uint32_t) {
        return std::array<double, 3>{0.70 * std::pow(t / 0.70, 1.12), t, t};
    });
    balance(pixels);
    const auto white = tone_center(pixels, wedge_tones - 1U, 8U);
    expect(std::abs(white.red / white.blue - 1.0) < 0.01, "white stays neutral");
    for (std::size_t tone = 0U; tone < wedge_tones; ++tone) {
        if (wedge_tone(tone) < 0.05) continue;
        expect(std::abs(red_blue(tone_center(pixels, tone, 8U))) < 0.03, "midtone bow removed");
    }
}

// 이미 중립인 장면은 건드리지 않습니다.
void test_neutral_scene_is_untouched() {
    auto pixels = wedge([](const double t, std::uint32_t) { return std::array<double, 3>{t, t, t}; });
    const auto before = pixels;
    balance(pixels);
    for (std::size_t index = 0U; index < pixels.size(); ++index) {
        expect(pixels[index].red == before[index].red && pixels[index].blue == before[index].blue,
               "neutral scene is identity");
    }
}

// 지배색(숲 초록 70%) 장면에서도 중립 패치는 중립으로 남고 초록은 회색으로 끌리지 않습니다.
void test_dominant_foliage_does_not_pull_the_neutral_axis() {
    constexpr std::uint32_t height = 40U;
    auto pixels = wedge([](const double t, const std::uint32_t y) {
        return y < 28U ? std::array<double, 3>{0.35 * t, 1.0 * t, 0.28 * t} : std::array<double, 3>{t, t, t};
    }, height);
    balance(pixels, height);
    for (std::size_t tone = 0U; tone < wedge_tones; ++tone) {
        if (wedge_tone(tone) < 0.02) continue;
        expect(std::abs(red_blue(tone_center(pixels, tone, 36U))) < 0.05, "neutral rows stay neutral");
        const auto foliage = tone_center(pixels, tone, 10U);
        expect(std::abs(std::log2(foliage.green / foliage.red) - std::log2(1.0 / 0.35)) < 0.1,
               "foliage keeps its colour");
    }
}

// ── 측정 영역 · 가장자리 인셋 · 위쪽 묶음 ───────────────────────────────────────────

// 따뜻한 홀더 가장자리(3 화소)가 있는 중립 램프. 가장자리가 화이트포인트가 되면 캐스트가 생깁니다.
[[nodiscard]] std::vector<negaflow::core::Rgba32F> framed_ramp(const std::uint32_t width, const std::uint32_t height) {
    std::vector<negaflow::core::Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const bool border = x < 3U || y < 3U || x >= width - 3U || y >= height - 3U;
            const float t = 0.08F + 0.50F * static_cast<float>(x) / static_cast<float>(width);
            pixels[static_cast<std::size_t>(y) * width + x] =
                border ? negaflow::core::Rgba32F{0.98F, 0.80F, 0.66F, 1.0F} : negaflow::core::Rgba32F{t, t, t, 1.0F};
        }
    }
    return pixels;
}

void test_auto_levels_ignores_frame_border_and_measures_inside_region() {
    constexpr std::uint32_t width = 300U, height = 200U;
    for (const bool with_region : {false, true}) {
        auto pixels = framed_ramp(width, height);
        negaflow::imaging::SceneCorrectionParameters parameters{true, false, true};
        if (with_region) {
            parameters.analysis_region = negaflow::imaging::make_analysis_region(0.05, 0.05, 0.9, 0.9);
        }
        negaflow::imaging::SceneCorrectionInfo info{};
        expect(negaflow::imaging::apply_scene_correction(view(pixels, width, height), parameters, info) ==
                   negaflow::core::KernelStatus::ok,
               "framed auto levels succeeds");
        const auto p = pixels[static_cast<std::size_t>(height / 2U) * width + width * 3U / 4U];
        expect(std::abs(p.red / p.blue - 1.0F) < 0.01F, "the warm holder border does not become the white point");
    }
}

void test_auto_levels_keeps_values_above_the_white_point() {
    constexpr std::uint32_t width = 64U, height = 32U;
    std::vector<negaflow::core::Rgba32F> pixels(width * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float t = 0.1F + 0.4F * static_cast<float>(x) / static_cast<float>(width - 1U);
            pixels[static_cast<std::size_t>(y) * width + x] = {t, t, t, 1.0F};
        }
    }
    pixels[static_cast<std::size_t>(16U) * width + 32U] = {0.9F, 0.9F, 0.9F, 1.0F};   // 스펙큘러 한 점
    negaflow::imaging::SceneCorrectionInfo info{};
    const negaflow::imaging::SceneCorrectionParameters parameters{true, false, true};
    expect(negaflow::imaging::apply_scene_correction(view(pixels, width, height), parameters, info) ==
               negaflow::core::KernelStatus::ok && info.auto_levels_applied,
           "auto levels applies");
    expect(pixels[static_cast<std::size_t>(16U) * width + 32U].red > 1.0F,
           "a specular above the white point keeps its headroom instead of clipping at 1");
}

void test_levels_preserve_neutrals_and_hue() {
    constexpr std::uint32_t width=256,height=128;
    std::vector<negaflow::core::Rgba32F> pixels(width*height);
    for(std::uint32_t y=0;y<height;++y){for(std::uint32_t x=0;x<width;++x){
        const float t=static_cast<float>(x)/255.0F;
        pixels[y*width+x]=(x>=110 && x<145)?negaflow::core::Rgba32F{.2F,.2F,.2F,1}:
            negaflow::core::Rgba32F{.05F+.35F*t,.05F+.65F*t,.05F+.90F*t,1};}}
    const auto before=pixels[64*width+180];
    negaflow::imaging::SceneCorrectionInfo info{};
    expect(negaflow::imaging::apply_scene_correction(view(pixels,width,height),{true,false,true},info)==negaflow::core::KernelStatus::ok,"luminance levels succeed");
    const auto neutral=pixels[64*width+128],after=pixels[64*width+180];
    expect(std::abs(neutral.red-neutral.green)<1e-5F && std::abs(neutral.green-neutral.blue)<1e-5F,"levels keep an existing neutral neutral");
    expect(std::abs(before.red/before.blue-after.red/after.blue)<1e-5F && std::abs(before.green/before.blue-after.green/after.blue)<1e-5F,"levels preserve chromatic ratios");
    std::uint32_t w=0,h=0;
    expect(negaflow::imaging::scene_sample_grid_extent(16,4096,256,w,h) && w==1 && h==256,"portrait sampling is bounded by the long edge");
    pixels.assign(width*height,{.4F,.2F,.1F,1});
    expect(negaflow::imaging::apply_scene_correction(view(pixels,width,height),{false,true,true},info)==negaflow::core::KernelStatus::ok,"weak color evidence remains usable");
    const auto p=pixels[64*width+128];
    expect(std::abs(std::log(p.red/p.blue)-std::log(4.0))<.12,"auto color preserves an unsupported subject color");
}

}  // namespace

int main() {
    try {
        test_disabled_is_identity();
        test_levels_preserve_neutrals_and_hue();
        test_linear_negative_levels_reach_output_targets();
        test_linear_negative_base_does_not_dominate_neutral_evidence();
        test_negative_auto_correction_changes_cast_range();
        test_changed_gamma_and_base_inputs_do_not_reuse_previous_correction();
        test_uniform_cast_is_removed_at_every_tone();
        test_midtone_bow_is_removed_without_breaking_white();
        test_neutral_scene_is_untouched();
        test_dominant_foliage_does_not_pull_the_neutral_axis();
        test_auto_levels_ignores_frame_border_and_measures_inside_region();
        test_auto_levels_keeps_values_above_the_white_point();
        std::cout << "Scene correction tests passed\n";
        return 0;
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        return 1;
    }
}
