// 스캐너 타깃 렌더링은 화이트 밸런스·노출·기본 톤 **뒤**에 걸립니다 — 같은 슬라이더를 준 MAIN
// 결과에 렌더링만 얹은 값과 같아야 합니다(macOS `testSceneSlidersActBeforeTheScannerRendering`).
// 예전에는 렌더링이 반전 직후에 있어, 흰색을 0.95 근처까지 그린 출력 위에서 MAIN 의 여유(흰색
// 0.70)를 전제로 만든 슬라이더가 다시 돌았습니다(흰색 계열 +0.5 의 클리핑이 MAIN 0%·SP 20.7%,
// 2026-11-07 실측). 슬라이더가 모두 0 이면 앞 단계가 항등이라 기본 그림은 그대로입니다(골든).

#include "negaflow/imaging/scanner_target_grade.h"
#include "negaflow/pipeline/develop_export.h"
#include "synthetic_wic_tiff.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
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

constexpr std::uint32_t patch_count = 21U;
constexpr std::uint32_t patch_width = 24U;
constexpr std::uint32_t width = patch_count * patch_width;
constexpr std::uint32_t height = 48U;
constexpr std::array<double, 3> dmin{0.18, 0.11, 0.08};

[[nodiscard]] double decode(const double v) {
    return v <= 0.04045 ? v / 12.92 : std::pow((v + 0.055) / 1.055, 2.4);
}

[[nodiscard]] double encode(const double v) {
    const double x = std::clamp(v, 0.0, 1.0);
    return x <= 0.0031308 ? x * 12.92 : 1.055 * std::pow(x, 1.0 / 2.4) - 0.055;
}

// 패치 가운데 8×8 의 sRGB 평균(0~255).
[[nodiscard]] std::array<double, 3> patch_mean(const std::vector<std::uint8_t>& bgra, const std::uint32_t patch) {
    std::array<double, 3> sum{};
    const std::uint32_t cx = patch * patch_width + patch_width / 2U;
    for (std::uint32_t y = height / 2U - 4U; y < height / 2U + 4U; ++y) {
        for (std::uint32_t x = cx - 4U; x < cx + 4U; ++x) {
            const std::size_t at = (static_cast<std::size_t>(y) * width + x) * 4U;
            sum[0] += bgra[at + 2U];
            sum[1] += bgra[at + 1U];
            sum[2] += bgra[at];
        }
    }
    for (double& c : sum) { c /= 64.0; }
    return sum;
}

}  // namespace

int main() {
    // 중립 밀도 웨지: 패치 k 의 베이스 위 밀도 = 1.55·k/20(왼쪽이 장면 검정, 오른쪽이 장면 흰색).
    std::vector<std::uint16_t> samples(static_cast<std::size_t>(width) * height * 3U);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const double density = 1.55 * static_cast<double>(x / patch_width) / (patch_count - 1U);
            for (std::size_t c = 0U; c < 3U; ++c) {
                const double transmittance = std::pow(10.0, -(dmin[c] + density));
                samples[(static_cast<std::size_t>(y) * width + x) * 3U + c] =
                    static_cast<std::uint16_t>(std::lround(transmittance * 65535.0));
            }
        }
    }
    const std::filesystem::path source =
        std::filesystem::temp_directory_path() / L"negaflow-scanner-target-slider-order.tiff";
    {
        const std::vector<std::uint8_t> tiff =
            negaflow::test_fixtures::make_uncompressed_rgb16_tiff(width, height, samples);
        std::ofstream out(source, std::ios::binary | std::ios::trunc);
        out.write(reinterpret_cast<const char*>(tiff.data()), static_cast<std::streamsize>(tiff.size()));
        expect(out.good() && !tiff.empty(), "wrote the synthetic wedge");
    }

    negaflow::pipeline::DevelopExportRequest request{};
    request.source = source;
    request.film_polarity = negaflow::pipeline::FilmPolarity::negative;
    request.base_estimation_mode = negaflow::pipeline::NegativeBaseEstimationMode::manual;
    request.negative.dmin = {static_cast<float>(dmin[0]), static_cast<float>(dmin[1]), static_cast<float>(dmin[2])};
    request.auto_balance = true;
    request.retain_preview_raw = false;
    request.color_model.warmth = 0.3F;
    request.tone.exposure_stops = 0.4F;
    request.tone.basic.whites = 0.5F;
    request.tone.basic.highlights = 0.3F;

    const auto preview = [&](const negaflow::pipeline::DevelopTarget target) {
        negaflow::pipeline::DevelopExportRequest r = request;
        r.develop_target = target;
        std::vector<std::uint8_t> pixels(static_cast<std::size_t>(width) * height * 4U, 0U);
        const auto outcome = negaflow::pipeline::develop_preview(r, width, height, pixels.data(), pixels.size());
        expect(outcome.succeeded && outcome.image_width == width && outcome.image_height == height,
            "preview renders the wedge at full size");
        return pixels;
    };

    const std::vector<std::uint8_t> main = preview(negaflow::pipeline::DevelopTarget::main);
    const std::array<std::pair<negaflow::pipeline::DevelopTarget, negaflow::imaging::ScannerTargetStyle>, 3> targets{{
        {negaflow::pipeline::DevelopTarget::sp3000, negaflow::imaging::ScannerTargetStyle::sp3000},
        {negaflow::pipeline::DevelopTarget::f135, negaflow::imaging::ScannerTargetStyle::f135},
        {negaflow::pipeline::DevelopTarget::hr, negaflow::imaging::ScannerTargetStyle::hr},
    }};
    for (const auto& [target, style] : targets) {
        const std::vector<std::uint8_t> rendered = preview(target);
        // MAIN 패치를 선형으로 되돌려 같은 타깃 렌더링만 얹습니다.
        std::vector<negaflow::core::Rgba32F> expected(patch_count);
        for (std::uint32_t k = 0U; k < patch_count; ++k) {
            const auto m = patch_mean(main, k);
            expected[k] = {static_cast<float>(decode(m[0] / 255.0)), static_cast<float>(decode(m[1] / 255.0)),
                           static_cast<float>(decode(m[2] / 255.0)), 1.0F};
        }
        negaflow::imaging::ScannerTargetGradeInfo info{};
        expect(negaflow::imaging::apply_scanner_target_grade(
                   {expected.data(), expected.size(), patch_count, 1U, patch_count},
                   style, false, false, L"", info) == negaflow::core::KernelStatus::ok,
            "the reference rendering applies");
        double worst = 0.0;
        for (std::uint32_t k = 0U; k < patch_count; ++k) {
            const auto r = patch_mean(rendered, k);
            const std::array<double, 3> e{expected[k].red, expected[k].green, expected[k].blue};
            for (std::size_t c = 0U; c < 3U; ++c) {
                worst = std::max(worst, std::abs(r[c] - encode(e[c]) * 255.0));
            }
        }
        std::cout << "target " << static_cast<int>(target) << " worst " << worst << " codes\n";
        expect(worst <= 3.0, "the target equals MAIN with the same sliders plus the fixed rendering");
        const auto white = patch_mean(rendered, patch_count - 1U);
        const double luma = 0.2126 * white[0] + 0.7152 * white[1] + 0.0722 * white[2];
        expect(luma < 252.0, "the scene white does not stick to paper white when the sliders lift it");
    }

    std::error_code ignored;
    std::filesystem::remove(source, ignored);
    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "scanner_target_slider_order ok\n";
    return 0;
}
