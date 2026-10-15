// 중립 스포이드: 찍은 점이 현상 결과에서 무채색이 되는 온도·틴트(2026-10-14). macOS
// `NeutralWhiteBalancePickerTests` 와 같은 계약입니다. 합성 화상만 씁니다.

#include "negaflow/imaging/color_model.h"
#include "negaflow/imaging/film_stock_base_resolver.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/neutral_white_balance_picker.h"
#include "negaflow/imaging/white_balance.h"
#include "negaflow/imaging/working_tone_adjuster.h"

#include <array>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <optional>
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

struct Cast final {
    double red_blue{0.0};
    double green{0.0};
};

[[nodiscard]] Cast cast_of(const std::array<double, 3>& c) {
    return {std::log2(c[0] / c[2]), std::log2(c[1] / std::sqrt(c[0] * c[2]))};
}

[[nodiscard]] negaflow::core::ConstImageView view_of(const WorkingImage& image) {
    return {image.pixels.data(), image.pixels.size(), image.width, image.height, image.stride_pixels};
}

// 역산은 정확합니다 — 범위 안의 캐스트는 게인을 곱하면 중립이 됩니다.
void test_solve_neutralises_the_reference_exactly() {
    const std::array<std::array<double, 3>, 5> references{{
        {0.30, 0.25, 0.18}, {0.12, 0.15, 0.22}, {0.40, 0.33, 0.41}, {0.20, 0.20, 0.20}, {0.05, 0.06, 0.04},
    }};
    for (const auto& reference : references) {
        const auto solved = negaflow::imaging::solve_neutral_white_balance(reference);
        expect(solved.has_value(), "a positive reference is solvable");
        if (!solved) {
            continue;
        }
        const auto gains = negaflow::imaging::white_balance_gains(
            static_cast<float>(solved->warmth), static_cast<float>(solved->tint));
        const Cast cast = cast_of({reference[0] * gains.red, reference[1] * gains.green,
                                   reference[2] * gains.blue});
        expect(std::abs(cast.red_blue) <= 0.003 && std::abs(cast.green) <= 0.003,
               "the solved gains neutralise " + std::to_string(reference[0]) + "," +
                   std::to_string(reference[1]) + "," + std::to_string(reference[2]));
    }
}

// 범위를 넘는 캐스트는 끝값에서 멈춥니다.
void test_solve_stops_at_the_slider_range() {
    const auto solved = negaflow::imaging::solve_neutral_white_balance({0.40, 0.20, 0.01});
    expect(solved.has_value() &&
               std::abs(solved->warmth + negaflow::imaging::maximum_white_balance_control) < 1.0e-9,
           "a cast beyond the range stops at the cool end");
}

[[nodiscard]] WorkingImage flat(const std::uint32_t width, const std::uint32_t height,
                                const std::array<float, 3>& colour) {
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.assign(static_cast<std::size_t>(width) * height,
                        {colour[0], colour[1], colour[2], 1.0F});
    return image;
}

// 거의 검은 점은 채널비가 잡음이라 거부합니다. 클리핑에 가까운 점도 거부합니다.
void test_sample_rejects_black_and_clipped_points() {
    const WorkingImage black = flat(64U, 64U, {0.001F, 0.002F, 0.001F});
    expect(!negaflow::imaging::sample_neutral_white_balance_reference(view_of(black), 0.5, 0.5),
           "a near-black point is refused");
    const WorkingImage bright = flat(64U, 64U, {0.95F, 0.95F, 0.95F});
    expect(!negaflow::imaging::sample_neutral_white_balance_reference(view_of(bright), 0.5, 0.5),
           "a near-clipped point is refused");
    const WorkingImage grey = flat(64U, 64U, {0.20F, 0.18F, 0.16F});
    const auto sampled = negaflow::imaging::sample_neutral_white_balance_reference(view_of(grey), 0.5, 0.5);
    expect(sampled.has_value() && std::abs((*sampled)[0] - 0.20) < 1.0e-6 &&
               std::abs((*sampled)[2] - 0.16) < 1.0e-6,
           "a mid grey point returns its own linear mean");
}

// 평균 창은 찍은 점 주위입니다(긴 변 × 0.004) — 옆 패치가 섞이지 않습니다. y 는 아래로 커집니다.
void test_sample_window_stays_around_the_point() {
    WorkingImage image = flat(1000U, 400U, {0.30F, 0.30F, 0.30F});
    for (std::uint32_t y = 0U; y < 200U; ++y) {        // 위쪽 절반만 붉게
        for (std::uint32_t x = 0U; x < 1000U; ++x) {
            image.pixels[static_cast<std::size_t>(y) * 1000U + x] = {0.40F, 0.20F, 0.10F, 1.0F};
        }
    }
    const auto top = negaflow::imaging::sample_neutral_white_balance_reference(view_of(image), 0.5, 0.25);
    const auto bottom = negaflow::imaging::sample_neutral_white_balance_reference(view_of(image), 0.5, 0.75);
    expect(top.has_value() && std::abs((*top)[0] - 0.40) < 1.0e-6, "y-down: the upper point reads the red half");
    expect(bottom.has_value() && std::abs((*bottom)[0] - 0.30) < 1.0e-6, "the lower point reads the grey half");
}

// 실제 경로: 베이스를 틀리게 지정해 반전 뒤 캐스트가 남은 네거티브에 채도·노출·대비·커브까지 걸린
// 상태에서 회색 패치를 찍으면, 결과에서 그 패치가 중립이 됩니다. 값은 색 모델 직전(반전 결과)에서
// 재고, 온도·틴트는 색 모델이 맨 앞에서 곱합니다.
void test_picked_negative_patch_becomes_neutral_through_tone_and_curves() {
    const auto preset = negaflow::imaging::resolve_film_stock_base_preset(
        L"kodak-portra-400", L"neutral", negaflow::imaging::NegativeFilmType::color);
    const std::array<float, 3> base = preset->dmin;
    constexpr std::uint32_t patches = 21U;
    constexpr std::uint32_t patch_width = 40U;
    constexpr std::uint32_t width = patches * patch_width;
    constexpr std::uint32_t height = 120U;
    WorkingImage negative{};
    negative.width = width;
    negative.height = height;
    negative.stride_pixels = width;
    negative.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const double density = 0.10 + 1.60 * static_cast<double>(x / patch_width) / (patches - 1U);
            const auto t = static_cast<float>(std::pow(10.0, -density));
            negative.pixels[static_cast<std::size_t>(y) * width + x] = {base[0] * t, base[1] * t, base[2] * t, 1.0F};
        }
    }
    negaflow::imaging::ManualNegativeDevelopParameters inversion{};
    inversion.dmin = {base[0] * 1.0F, base[1] * 0.96F, base[2] * 0.88F};   // 틀린 베이스
    inversion.film_type = negaflow::imaging::NegativeFilmType::color;
    auto developed = negaflow::imaging::develop_manual_negative(std::move(negative), inversion);
    expect(developed.status == negaflow::imaging::ManualNegativeDevelopStatus::ok, "inversion succeeds");
    const WorkingImage reference = developed.image;

    constexpr std::uint32_t patch = 10U;
    const auto patch_mean = [&](const WorkingImage& image) {
        std::array<double, 3> sum{};
        double n = 0.0;
        for (std::uint32_t y = 40U; y < 80U; ++y) {
            for (std::uint32_t x = patch * patch_width + 10U; x < patch * patch_width + 30U; ++x) {
                const auto& p = image.pixels[static_cast<std::size_t>(y) * width + x];
                sum = {sum[0] + p.red, sum[1] + p.green, sum[2] + p.blue};
                n += 1.0;
            }
        }
        return std::array<double, 3>{sum[0] / n, sum[1] / n, sum[2] / n};
    };
    const auto display = [&](const float warmth, const float tint) {
        WorkingImage image = reference;
        negaflow::imaging::ColorModelParameters colour{};
        colour.warmth = warmth;
        colour.tint = tint;
        colour.saturation = 0.3F;
        const negaflow::core::ImageView pixels{image.pixels.data(), image.pixels.size(), image.width,
                                               image.height, image.stride_pixels};
        expect(negaflow::imaging::apply_color_model(view_of(image), pixels, colour) ==
                   negaflow::core::KernelStatus::ok,
               "colour model succeeds");
        negaflow::imaging::WorkingToneAdjustParameters tone{};
        tone.exposure_stops = 0.6F;
        tone.basic.contrast = 0.4F;
        tone.curve.lights = 0.5F;
        auto adjusted = negaflow::imaging::apply_working_tone_adjustments(std::move(image), tone);
        expect(adjusted.status == negaflow::imaging::WorkingToneAdjustStatus::ok, "tone succeeds");
        return patch_mean(adjusted.image);
    };

    const Cast before = cast_of(display(1.5F, -0.7F));
    expect(std::abs(before.red_blue) + std::abs(before.green) > 0.1, "the fixture carries a cast");

    const double unit_x = (patch * patch_width + patch_width / 2.0) / width;
    const auto sampled = negaflow::imaging::sample_neutral_white_balance_reference(view_of(reference), unit_x, 0.5);
    expect(sampled.has_value(), "the grey patch is sampled");
    if (!sampled) {
        return;
    }
    const auto solved = negaflow::imaging::solve_neutral_white_balance(*sampled);
    expect(solved.has_value(), "the grey patch is solvable");
    if (!solved) {
        return;
    }
    const Cast after = cast_of(display(static_cast<float>(solved->warmth), static_cast<float>(solved->tint)));
    expect(std::abs(after.red_blue) <= 0.01, "R/B after the pick " + std::to_string(after.red_blue));
    expect(std::abs(after.green) <= 0.01, "green after the pick " + std::to_string(after.green));
}

}  // namespace

int main() {
    test_solve_neutralises_the_reference_exactly();
    test_solve_stops_at_the_slider_range();
    test_sample_rejects_black_and_clipped_points();
    test_sample_window_stays_around_the_point();
    test_picked_negative_patch_becomes_neutral_through_tone_and_curves();
    if (failures != 0) {
        std::cerr << failures << " neutral white balance picker check(s) failed\n";
        return 1;
    }
    std::cout << "neutral white balance picker tests passed\n";
    return 0;
}
