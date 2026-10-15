// 디지털 카메라 스캔(필름보다 넓게 찍힌 프레임)의 측정 영역·베이스 검출 계약입니다.
// macOS `CameraScanMeasurementTests` 와 같은 합성 픽스처·같은 허용치입니다. 실사진은 쓰지 않습니다.
//
// 2026-10-14 실측 결함: 홀더 가장자리 혼합 화소가 Dmax 를 틀어 R/B 0.72~0.98 캐스트, 크롭 안
// 재검출이 유채색 그림자를 베이스로 오인(암부 R/B 3.47), 비네팅된 웜 LED 를 베이스로 오인,
// 광원이 가려진 띠에서 이웃 프레임의 푸른 그림자를 베이스로 오인.

#include "negaflow/imaging/analysis_region.h"
#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/film_stock_base_resolver.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scene_correction.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <optional>
#include <string>
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

enum class Rebate { full, between_frames_only, hidden };

constexpr std::uint32_t frame_width = 1500U;
constexpr std::uint32_t frame_height = 1000U;
constexpr std::uint32_t image_x0 = 140U, image_x1 = 1360U;   // 사진 영역(y-down)
constexpr std::uint32_t image_y0 = 170U, image_y1 = 830U;
constexpr std::uint32_t patch_count = 21U;
constexpr std::uint32_t patch_width = (image_x1 - image_x0) / patch_count;

[[nodiscard]] std::array<double, 3> portra_base() {
    const auto preset = negaflow::imaging::resolve_film_stock_base_preset(
        L"kodak-portra-400", L"neutral", negaflow::imaging::NegativeFilmType::color);
    return {preset->dmin[0], preset->dmin[1], preset->dmin[2]};
}

struct CameraScanFrame final {
    Rebate rebate{Rebate::full};
    std::array<double, 3> light{0.95, 0.95, 0.95};
    double vignette{0.0};
    std::optional<std::array<double, 3>> coloured_shadow{};
    bool light_visible{true};
    std::optional<std::array<double, 3>> neighbour_shade{};

    [[nodiscard]] static double density(const std::uint32_t k) {
        return 0.15 + 1.40 * static_cast<double>(k) / static_cast<double>(patch_count - 1U);
    }

    [[nodiscard]] WorkingImage image() const {
        const std::array<double, 3> base = portra_base();
        WorkingImage image{};
        image.width = frame_width;
        image.height = frame_height;
        image.stride_pixels = frame_width;
        image.pixels.resize(static_cast<std::size_t>(frame_width) * frame_height);
        for (std::uint32_t y = 0U; y < frame_height; ++y) {
            for (std::uint32_t x = 0U; x < frame_width; ++x) {
                const double dx = (static_cast<double>(x) - frame_width / 2.0) / (frame_width / 2.0);
                const double dy = (static_cast<double>(y) - frame_height / 2.0) / (frame_height / 2.0);
                const double falloff = std::max(0.35, 1.0 - vignette * (dx * dx + dy * dy));
                const auto film = [&](const std::array<double, 3>& d) {
                    return std::array<double, 3>{
                        base[0] * std::pow(10.0, -d[0]) * light[0] / 0.95 * falloff,
                        base[1] * std::pow(10.0, -d[1]) * light[1] / 0.95 * falloff,
                        base[2] * std::pow(10.0, -d[2]) * light[2] / 0.95 * falloff};
                };
                const std::array<double, 3> holder{
                    0.004 * light[0] / 0.95 * falloff, 0.004 * light[1] / 0.95 * falloff,
                    0.004 * light[2] / 0.95 * falloff};
                std::array<double, 3> value{};
                const bool inside_rows = y >= image_y0 && y < image_y1;
                if (y < 50U || y >= 950U) {
                    value = light_visible
                        ? std::array<double, 3>{light[0] * falloff, light[1] * falloff, light[2] * falloff}
                        : holder;
                } else if (rebate == Rebate::full && (y < 100U || y >= 900U)) {
                    value = holder;
                } else if (!inside_rows) {
                    value = rebate == Rebate::full ? film({0.0, 0.0, 0.0}) : holder;
                } else if (x < 120U && neighbour_shade) {
                    value = film(*neighbour_shade);
                } else if (x < 120U || x >= 1380U) {
                    value = film({1.35, 1.20, 0.95});   // 이웃 프레임
                } else if (x < image_x0 || x >= image_x1) {
                    value = rebate == Rebate::hidden ? holder : film({0.0, 0.0, 0.0});
                } else if (coloured_shadow && y >= 620U && y < 760U) {
                    value = film(*coloured_shadow);
                } else {
                    const std::uint32_t k = std::min(patch_count - 1U, (x - image_x0) / patch_width);
                    const double d = density(k);
                    value = film({d, d, d});
                }
                image.pixels[static_cast<std::size_t>(y) * frame_width + x] = {
                    static_cast<float>(value[0]), static_cast<float>(value[1]),
                    static_cast<float>(value[2]), 1.0F};
            }
        }
        return image;
    }
};

[[nodiscard]] std::optional<negaflow::imaging::AnalysisRegion> crop_region() {
    negaflow::imaging::ImageTransformParameters transform{};
    transform.has_crop = true;
    transform.crop = {
        static_cast<double>(image_x0) / frame_width,
        static_cast<double>(frame_height - image_y1) / frame_height,
        static_cast<double>(image_x1 - image_x0) / frame_width,
        static_cast<double>(image_y1 - image_y0) / frame_height};
    return negaflow::imaging::analysis_region_from_transform(transform, frame_width, frame_height);
}

struct Developed final {
    std::array<float, 3> base{};
    std::vector<std::array<double, 3>> patches{};
};

// 앱의 자동 베이스 경로와 같습니다 — 베이스를 (크롭이면 띠에서) 풀고 그 베이스로 반전합니다.
[[nodiscard]] Developed develop(const CameraScanFrame& frame, const bool crop, const bool auto_levels = false) {
    const std::optional<negaflow::imaging::AnalysisRegion> region = crop ? crop_region() : std::nullopt;
    WorkingImage image = frame.image();
    const auto resolved = negaflow::imaging::resolve_auto_negative_base(
        image, negaflow::imaging::NegativeFilmType::color, region);
    negaflow::imaging::ManualNegativeDevelopParameters parameters{};
    parameters.dmin = resolved.dmin;
    parameters.film_type = negaflow::imaging::NegativeFilmType::color;
    parameters.analysis_region = region;
    auto developed = negaflow::imaging::develop_manual_negative(std::move(image), parameters);
    Developed result{};
    result.base = resolved.dmin;
    if (developed.status != negaflow::imaging::ManualNegativeDevelopStatus::ok) {
        expect(false, "develop succeeds");
        return result;
    }
    if (auto_levels) {
        negaflow::imaging::SceneCorrectionParameters scene{true, false, true, region};
        negaflow::imaging::SceneCorrectionInfo info{};
        expect(negaflow::imaging::apply_scene_correction(
                   {developed.image.pixels.data(), developed.image.pixels.size(), developed.image.width,
                    developed.image.height, developed.image.stride_pixels},
                   scene, info) == negaflow::core::KernelStatus::ok,
               "auto levels succeeds");
    }
    for (std::uint32_t k = 0U; k < patch_count; ++k) {
        const std::uint32_t cx = image_x0 + k * patch_width + patch_width / 2U;
        std::array<double, 3> sum{};
        double n = 0.0;
        for (std::uint32_t y = 485U; y < 515U; ++y) {
            for (std::uint32_t x = cx - 8U; x < cx + 8U; ++x) {
                const auto& p = developed.image.pixels[static_cast<std::size_t>(y) * frame_width + x];
                sum[0] += p.red;
                sum[1] += p.green;
                sum[2] += p.blue;
                n += 1.0;
            }
        }
        result.patches.push_back({sum[0] / n, sum[1] / n, sum[2] / n});
    }
    return result;
}

void expect_neutral(const Developed& developed, const double tolerance, const std::string& name) {
    for (std::size_t k = 2U; k < developed.patches.size(); ++k) {
        const auto& p = developed.patches[k];
        expect(std::abs(p[0] / p[2] - 1.0) <= tolerance,
               name + ": patch " + std::to_string(k) + " R/B " + std::to_string(p[0] / p[2]));
    }
}

void expect_base(const Developed& developed, const std::string& name) {
    const std::array<double, 3> truth = portra_base();
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        expect(std::abs(developed.base[channel] / truth[channel] - 1.0) <= 0.02,
               name + ": base channel " + std::to_string(channel) + " " +
                   std::to_string(developed.base[channel] / truth[channel]));
    }
}

// 홀더가 리베이트를 가려 사진에 붙어 있어도(크롭 없음) Dmax 가 틀어지지 않습니다.
void test_holder_edge_blends_do_not_skew_density_range() {
    CameraScanFrame frame{};
    frame.rebate = Rebate::between_frames_only;
    expect_neutral(develop(frame, false), 0.02, "holder edge");
}

// 크롭하면 베이스는 크롭 바깥 띠에서 찾습니다 — 사진 안의 유채색 그림자를 베이스로 잡지 않습니다.
void test_crop_finds_base_outside_and_ignores_coloured_shadow() {
    CameraScanFrame frame{};
    frame.coloured_shadow = std::array<double, 3>{0.12, 0.30, 0.22};
    const Developed developed = develop(frame, true);
    expect_base(developed, "coloured shadow");
    expect_neutral(developed, 0.02, "coloured shadow");
}

// 크롭 바깥 띠에서는 비네팅으로 베이스만큼 어두워진 웜 LED 를 색도로 걸러 냅니다.
void test_crop_band_rejects_dim_warm_backlight() {
    CameraScanFrame frame{};
    frame.light = {0.95, 0.836, 0.684};   // 웜 LED(1 : 0.88 : 0.72)
    frame.vignette = 0.55;
    const Developed developed = develop(frame, true);
    const std::array<double, 3> truth = portra_base();
    const double expected = std::log10((truth[0] * 1.0) / (truth[2] * 0.72));
    expect(std::abs(std::log10(developed.base[0] / developed.base[2]) - expected) <= 0.05,
           "dim warm backlight: the backlight chroma was taken as the base");
    expect_neutral(developed, 0.03, "dim warm backlight");
}

// 홀더가 광원을 가려 띠에 광원이 없으면 강등하지 않습니다 — 이웃 프레임의 얇은 푸른 그림자 면은
// 베이스보다 오렌지지만(로그 R/B +0.37) 빨강·초록이 거의 감쇠되지 않아 마스크 색도가 아닙니다.
void test_crop_band_keeps_base_when_light_is_hidden() {
    CameraScanFrame frame{};
    frame.light_visible = false;
    frame.neighbour_shade = std::array<double, 3>{0.08, 0.20, 0.45};
    const Developed developed = develop(frame, true);
    expect_base(developed, "hidden light");
    expect_neutral(developed, 0.02, "hidden light");
}

// 자동 레벨도 크롭 안에서 잽니다 — 홀더·백라이트를 화이트/블랙포인트로 잡지 않습니다.
// 크롭이 베이스를 잘라 내 띠에 짙은 이웃 프레임·홀더만 남으면 띠에서 고르지 않습니다 — 크롭 안
// 사진에 그보다 뚜렷이 밝은 필름이 있으니 띠 값은 베이스일 수 없습니다. 크롭이 없을 때와 같은
// 답을 냅니다(macOS `testCropThatRemovesBaseFallsBackToWholeFrame`).
void test_crop_that_removes_base_falls_back_to_whole_frame() {
    CameraScanFrame frame{};
    frame.rebate = Rebate::hidden;
    frame.light_visible = false;
    const Developed cropped = develop(frame, true);
    const Developed whole = develop(frame, false);
    const std::array<double, 3> truth = portra_base();
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        expect(std::abs(cropped.base[channel] / whole.base[channel] - 1.0) <= 0.02,
               "crop changed the base: channel " + std::to_string(channel) + " " +
                   std::to_string(cropped.base[channel]) + " vs " + std::to_string(whole.base[channel]));
        expect(cropped.base[channel] / truth[channel] > 0.6,
               "dense band picked as base: channel " + std::to_string(channel) + " " +
                   std::to_string(cropped.base[channel] / truth[channel]));
    }
    expect_neutral(cropped, 0.03, "crop removed base");
}

// 베이스가 화면에 없는 컷: 가장 얇은 면이 결이 있어(이웃 15% 문턱에 조각나) 성분이 되지 못해도,
// 더 어두운 매끈한 면을 베이스로 잡지 않습니다(macOS `testFrameWithoutVisibleBaseDoesNotSettleOnSmoothMidtone`).
void test_frame_without_visible_base_does_not_settle_on_smooth_midtone() {
    const std::array<double, 3> base = portra_base();
    WorkingImage image{};
    image.width = 1024U;
    image.height = 640U;
    image.stride_pixels = image.width;
    image.pixels.resize(static_cast<std::size_t>(image.width) * image.height);
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            // 왼쪽 40%: 8px 바둑판(밀도 0.02 / 0.30) — 얇은 면이 대각으로만 이어집니다. 나머지: 매끈한 0.40.
            const double density = x < 410U ? (((x / 8U) + (y / 8U)) % 2U == 0U ? 0.02 : 0.30) : 0.40;
            const double scale = std::pow(10.0, -density);
            image.pixels[static_cast<std::size_t>(y) * image.width + x] = {
                static_cast<float>(base[0] * scale), static_cast<float>(base[1] * scale),
                static_cast<float>(base[2] * scale), 1.0F};
        }
    }
    negaflow::imaging::ImageTransformParameters transform{};
    transform.has_crop = true;
    transform.crop = {0.02, 0.02, 0.96, 0.96};
    const std::array<std::optional<negaflow::imaging::AnalysisRegion>, 2> regions{
        std::nullopt,
        negaflow::imaging::analysis_region_from_transform(transform, image.width, image.height)};
    for (const auto& region : regions) {
        const auto resolved = negaflow::imaging::resolve_auto_negative_base(
            image, negaflow::imaging::NegativeFilmType::color, region);
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            const double ratio = resolved.dmin[channel] / base[channel];
            expect(ratio > 0.75 && ratio < 1.02,
                   std::string("smooth midtone picked as base (crop ") + (region ? "yes" : "no") +
                       "): channel " + std::to_string(channel) + " " + std::to_string(ratio));
        }
    }
}

void test_auto_levels_measures_inside_crop() {
    const Developed developed = develop(CameraScanFrame{}, true, true);
    expect_neutral(developed, 0.02, "auto levels");
    const auto& brightest = developed.patches[20];
    expect(0.2126 * brightest[0] + 0.7152 * brightest[1] + 0.0722 * brightest[2] > 0.85,
           "auto levels stretches the photo area to the output white");
}

// 가장자리 띠 제외는 두께 있는 비필름 영역에만 겁니다. 흩어진 단일 점(그레인·양자화로 게이트를
// 넘은 칸)마다 이웃을 지우면, 그 점이 몰린 곳의 진짜 최농부가 함께 사라져 Dmax 가 낮게 잡힙니다
// (macOS 실측: 베이스 근처 밝기 면의 점 뒤집힘으로 필름 91% 가 지워져 같은 화상의 원본과 sRGB
// 사본이 Dmax R 0.146 vs 0.238 — 화면·내보내기 불일치의 원인).
void test_edge_exclusion_ignores_isolated_gate_flips() {
    // 축소가 없도록 측정 격자 폭(320)에 맞춘 원본입니다 — 점이 한 칸으로 남습니다.
    constexpr std::uint32_t width = 320U, height = 213U;
    const std::array<double, 3> base = portra_base();
    constexpr double max_density = 1.6;
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const double d = max_density * static_cast<double>(x) / (width - 1U);   // 오른쪽이 최농부
            const bool speck = x > width * 2U / 3U && x % 4U == 0U && y % 4U == 0U;
            const double scale = speck ? 1.3 : std::pow(10.0, -d);                  // 점은 베이스보다 밝다
            image.pixels[static_cast<std::size_t>(y) * width + x] = {
                static_cast<float>(base[0] * scale), static_cast<float>(base[1] * scale),
                static_cast<float>(base[2] * scale), 1.0F};
        }
    }
    negaflow::imaging::ManualNegativeDevelopParameters parameters{};
    parameters.dmin = {static_cast<float>(base[0]), static_cast<float>(base[1]), static_cast<float>(base[2])};
    parameters.film_type = negaflow::imaging::NegativeFilmType::color;
    const std::array<float, 3> dmax =
        negaflow::imaging::develop_manual_negative(std::move(image), parameters).info.dmax_normalized;
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        // 인셋(6%)이 오른쪽 끝을 조금 자르므로 최농부는 1.6D 의 94% 근처입니다.
        expect(dmax[channel] > 0.85 * max_density,
               "isolated gate flips removed the densest film: channel " + std::to_string(channel) +
                   " Dmax " + std::to_string(dmax[channel]));
    }
}

}  // namespace

int main() {
    test_edge_exclusion_ignores_isolated_gate_flips();
    test_holder_edge_blends_do_not_skew_density_range();
    test_crop_finds_base_outside_and_ignores_coloured_shadow();
    test_crop_band_rejects_dim_warm_backlight();
    test_crop_band_keeps_base_when_light_is_hidden();
    test_crop_that_removes_base_falls_back_to_whole_frame();
    test_frame_without_visible_base_does_not_settle_on_smooth_midtone();
    test_auto_levels_measures_inside_crop();
    if (failures != 0) {
        std::cerr << failures << " camera scan measurement check(s) failed\n";
        return 1;
    }
    std::cout << "camera scan measurement tests passed\n";
    return 0;
}
