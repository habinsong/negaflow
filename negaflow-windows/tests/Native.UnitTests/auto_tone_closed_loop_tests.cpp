// 자동 WB 의 휘도대별 중립축 증거와 자동 톤 폐루프의 시험입니다(2026-10-14). macOS
// `AutoAdjustClosedLoopTests` 와 같은 계약입니다. 합성 화상만 쓰고, 톤은 실제 CPU 톤 단계
// (`apply_working_tone_adjustments`)로 그려서 잽니다.

#include "negaflow/imaging/auto_adjust.h"
#include "negaflow/imaging/white_balance.h"
#include "negaflow/imaging/working_tone_adjuster.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

namespace {

using negaflow::imaging::WorkingImage;

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

[[nodiscard]] std::uint8_t to_byte(const double linear) {
    return static_cast<std::uint8_t>(
        std::lround(std::clamp(srgb_encode(std::clamp(linear, 0.0, 1.0)), 0.0, 1.0) * 255.0));
}

// 미리보기와 같은 BGRA8 로 내립니다.
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

[[nodiscard]] negaflow::imaging::AutoAdjustStats stats_of(const WorkingImage& image) {
    const std::vector<std::uint8_t> bytes = to_bgra(image);
    negaflow::imaging::AutoAdjustStats stats{};
    expect(negaflow::imaging::compute_auto_adjust_stats(
               bytes.data(), image.width, image.height,
               static_cast<std::size_t>(image.width) * 4U, stats),
           "statistics are computed");
    return stats;
}

[[nodiscard]] WorkingImage make_image(
    const std::uint32_t width,
    const std::uint32_t height,
    const auto& colour_at) {
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

// 컬러 마스터처럼 linear 0.01 ~ 0.70(확산 화이트) 사이를 로그로 나눈 중립 웨지입니다.
[[nodiscard]] WorkingImage neutral_wedge() {
    constexpr std::uint32_t steps = 21U;
    return make_image(420U, 60U, [](const std::uint32_t x, std::uint32_t) {
        const std::uint32_t step = std::min(steps - 1U, x * steps / 420U);
        const double value =
            0.01 * std::pow(0.70 / 0.01, static_cast<double>(step) / static_cast<double>(steps - 1U));
        return std::array<double, 3>{value, value, value};
    });
}

// 화면의 15% 를 차지한 따뜻한 조명 면이 자동 WB 를 끌고 가지 않습니다. 예전: 근중립 판정(채도
// <= 0.22)이 웜 면을 받아들여 진짜 중립을 R/B 0.90 으로 식혔습니다.
void test_white_balance_ignores_a_warm_lit_region() {
    constexpr std::uint32_t width = 420U;
    constexpr std::uint32_t height = 200U;
    const WorkingImage image = make_image(width, height, [](const std::uint32_t x, const std::uint32_t y) {
        if (y < 30U) {
            return std::array<double, 3>{0.80, 0.62, 0.50};   // 웜 조명 면(R/B 1.6)
        }
        const double tone = 0.01 * std::pow(0.70 / 0.01, static_cast<double>(x * 14U / width) / 13.0);
        return std::array<double, 3>{tone, tone, tone};
    });
    const negaflow::imaging::AutoAdjustStats stats = stats_of(image);
    expect(stats.neutral_axis.has_value(), "the neutral wedge gives neutral-axis evidence");
    const auto balance = negaflow::imaging::auto_white_balance(stats);
    const auto gains = negaflow::imaging::white_balance_gains(
        static_cast<float>(balance.warmth), static_cast<float>(balance.tint));
    expect(std::abs(gains.red / gains.blue - 1.0F) <= 0.02F,
           "the warm region cooled the neutral (warmth " + std::to_string(balance.warmth) + ")");
    expect(std::abs(gains.green / std::sqrt(gains.red * gains.blue) - 1.0F) <= 0.02F,
           "the warm region tinted the neutral (tint " + std::to_string(balance.tint) + ")");
}

[[nodiscard]] negaflow::imaging::WorkingToneAdjustParameters with(
    const negaflow::imaging::AutoToneResult& tone,
    const float curve_highlights) {
    negaflow::imaging::WorkingToneAdjustParameters parameters{};
    parameters.exposure_stops = static_cast<float>(tone.exposure);
    parameters.basic.contrast = static_cast<float>(tone.contrast);
    parameters.basic.density = static_cast<float>(tone.density);
    parameters.basic.highlights = static_cast<float>(tone.highlights);
    parameters.basic.shadows = static_cast<float>(tone.shadows);
    parameters.basic.whites = static_cast<float>(tone.whites);
    parameters.basic.blacks = static_cast<float>(tone.blacks);
    parameters.curve.highlights = curve_highlights;
    return parameters;
}

[[nodiscard]] WorkingImage develop(const negaflow::imaging::WorkingToneAdjustParameters& parameters) {
    auto adjusted = negaflow::imaging::apply_working_tone_adjustments(neutral_wedge(), parameters);
    expect(adjusted.status == negaflow::imaging::WorkingToneAdjustStatus::ok, "tone develop succeeds");
    return std::move(adjusted.image);
}

[[nodiscard]] int p995_bin(const negaflow::imaging::AutoAdjustStats& stats) {
    double accumulated = 0.0;
    for (std::size_t index = 0U; index < stats.luma_histogram.size(); ++index) {
        accumulated += stats.luma_histogram[index];
        if (accumulated >= 0.995) {
            return static_cast<int>(index);
        }
    }
    return 255;
}

// 자동 톤 폐루프: 사용자 커브(모형 밖)가 백점을 밀어도 다시 재서 목표(확산 화이트)로 되돌립니다.
void test_refinement_absorbs_a_user_curve() {
    const int target = static_cast<int>(std::lround(srgb_encode(0.90) * 255.0));
    const auto first = negaflow::imaging::auto_tone(stats_of(develop({})));
    const auto with_curve = stats_of(develop(with(first, 0.8F)));
    const auto refined = negaflow::imaging::refine_auto_tone(first, with_curve);
    const auto after = stats_of(develop(with(refined, 0.8F)));
    const int miss_before = std::abs(p995_bin(with_curve) - target);
    const int miss_after = std::abs(p995_bin(after) - target);
    expect(miss_after <= 4, "white point after refinement " + std::to_string(p995_bin(after)) +
                                " / target " + std::to_string(target));
    expect(miss_after <= miss_before, "refinement does not move the white point away");
    expect(refined.contrast == first.contrast && refined.density == first.density &&
               refined.highlights == first.highlights && refined.shadows == first.shadows &&
               refined.blacks == first.blacks && refined.vibrance == first.vibrance,
           "refinement only touches exposure and whites");
    if (std::getenv("NEGAFLOW_AUTO_TONE_TRACE") != nullptr) {
        std::cout << "first ev " << first.exposure << " whites " << first.whites << " | refined ev "
                  << refined.exposure << " whites " << refined.whites << " | p995 curve "
                  << p995_bin(with_curve) << " after " << p995_bin(after) << " target " << target << '\n';
    }
}

// 노출이 밝히지 않았으면 폐루프도 미드를 건드리지 않습니다("밝히는 방향만").
void test_refinement_keeps_exposure_when_it_did_not_brighten() {
    negaflow::imaging::AutoToneResult first{};
    first.exposure = 0.0;
    const WorkingImage dark = make_image(64U, 64U, [](std::uint32_t, std::uint32_t) {
        return std::array<double, 3>{0.02, 0.02, 0.02};
    });
    const auto refined = negaflow::imaging::refine_auto_tone(first, stats_of(dark));
    expect(refined.exposure == 0.0, "a zero exposure stays zero after refinement");
}

// 노출 뒤 백분위 예측은 엔진과 같은 숄더 연산자를 씁니다 — 흑백 네거티브(헤드룸 0.234 스톱)는
// 같은 노출에서 명부가 더 접히므로, 노출이 밝힌 장면에서 컬러와 다른 화이트를 냅니다.
void test_exposure_prediction_follows_the_film_shoulder() {
    const auto stats = stats_of(neutral_wedge());
    const auto colour = negaflow::imaging::auto_tone(stats);
    const auto mono = negaflow::imaging::auto_tone(
        stats, negaflow::core::exposure_headroom_stops(true));
    expect(colour.exposure > 0.0, "the dim wedge is brightened");
    expect(colour.exposure == mono.exposure, "the exposure target itself does not depend on the shoulder");
    expect(mono.whites > colour.whites,
           "a tighter shoulder predicts a lower white point and asks for more whites");
}

}  // namespace

int main() {
    test_white_balance_ignores_a_warm_lit_region();
    test_refinement_absorbs_a_user_curve();
    test_refinement_keeps_exposure_when_it_did_not_brighten();
    test_exposure_prediction_follows_the_film_shoulder();
    if (failures != 0) {
        std::cerr << failures << " auto tone closed-loop check(s) failed\n";
        return 1;
    }
    std::cout << "auto tone closed-loop tests passed\n";
    return 0;
}
