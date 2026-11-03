#include "negaflow/imaging/scanner_target_grade.h"
#include "negaflow/color/srgb_transfer.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {

void expect(const bool condition, const char* const message) {
    if (!condition) throw std::runtime_error(message);
}

negaflow::core::ImageView view(
    std::vector<negaflow::core::Rgba32F>& pixels,
    const std::uint32_t width,
    const std::uint32_t height) {
    return {pixels.data(), pixels.size(), width, height, width};
}

std::vector<negaflow::core::Rgba32F> fixture(
    const std::uint32_t width,
    const std::uint32_t height) {
    std::vector<negaflow::core::Rgba32F> pixels(width * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float u = static_cast<float>(x) / (width - 1U);
            const float v = static_cast<float>(y) / (height - 1U);
            pixels[static_cast<std::size_t>(y) * width + x] = {
                0.02F + (0.86F * u),
                0.03F + (0.75F * v),
                0.04F + (0.60F * (1.0F - u) * (0.4F + v * 0.6F)),
                0.70F,
            };
        }
    }
    return pixels;
}

bool images_differ(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) {
    if (left.size() != right.size()) return true;
    for (std::size_t i = 0U; i < left.size(); ++i) {
        if (std::abs(left[i].red - right[i].red) > 1.0e-6F ||
            std::abs(left[i].green - right[i].green) > 1.0e-6F ||
            std::abs(left[i].blue - right[i].blue) > 1.0e-6F ||
            std::abs(left[i].alpha - right[i].alpha) > 1.0e-6F) {
            return true;
        }
    }
    return false;
}

void test_four_targets_are_distinct_and_bounded() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 48U;
    const auto source = fixture(width, height);
    std::vector<std::vector<negaflow::core::Rgba32F>> outputs;
    for (const auto target : {
             negaflow::imaging::ScannerTargetStyle::noritsu,
             negaflow::imaging::ScannerTargetStyle::sp3000,
             negaflow::imaging::ScannerTargetStyle::f135,
             negaflow::imaging::ScannerTargetStyle::hr}) {
        auto pixels = source;
        negaflow::imaging::ScannerTargetGradeInfo info{};
        expect(
            negaflow::imaging::apply_scanner_target_grade(
                view(pixels, width, height), target, false, false, {}, info) ==
                negaflow::core::KernelStatus::ok,
            "scanner target grade succeeds");
        expect(info.applied, "scanner target is active");
        for (const auto& pixel : pixels) {
            expect(std::isfinite(pixel.red) && std::isfinite(pixel.green) &&
                       std::isfinite(pixel.blue),
                   "scanner target output is finite");
            expect(pixel.alpha == 0.70F, "scanner target preserves alpha");
        }
        outputs.push_back(std::move(pixels));
    }
    for (std::size_t i = 0U; i < outputs.size(); ++i) {
        bool differs_from_source = false;
        for (std::size_t p = 0U; p < source.size(); ++p) {
            differs_from_source = differs_from_source ||
                std::abs(outputs[i][p].red - source[p].red) > 1.0e-4F ||
                std::abs(outputs[i][p].green - source[p].green) > 1.0e-4F ||
                std::abs(outputs[i][p].blue - source[p].blue) > 1.0e-4F;
        }
        expect(differs_from_source, "scanner target differs from MAIN");
    }
    expect(images_differ(outputs[0], outputs[1]) &&
               images_differ(outputs[1], outputs[2]) &&
               images_differ(outputs[2], outputs[3]),
           "scanner targets remain visually distinct");
}

void test_positive_is_weaker_and_monochrome_stays_neutral() {
    constexpr std::uint32_t width = 32U;
    constexpr std::uint32_t height = 24U;
    const auto source = fixture(width, height);
    auto negative = source;
    auto positive = source;
    auto monochrome = source;
    negaflow::imaging::ScannerTargetGradeInfo info{};
    expect(negaflow::imaging::apply_scanner_target_grade(
               view(negative, width, height),
               negaflow::imaging::ScannerTargetStyle::f135,
               false, false, {}, info) == negaflow::core::KernelStatus::ok,
           "negative target succeeds");
    expect(negaflow::imaging::apply_scanner_target_grade(
               view(positive, width, height),
               negaflow::imaging::ScannerTargetStyle::f135,
               false, true, {}, info) == negaflow::core::KernelStatus::ok,
           "positive target succeeds");
    expect(negaflow::imaging::apply_scanner_target_grade(
               view(monochrome, width, height),
               negaflow::imaging::ScannerTargetStyle::hr,
               true, false, {}, info) == negaflow::core::KernelStatus::ok,
           "monochrome target succeeds");
    double negative_delta = 0.0;
    double positive_delta = 0.0;
    for (std::size_t i = 0U; i < source.size(); ++i) {
        negative_delta += std::abs(negative[i].red - source[i].red) +
            std::abs(negative[i].green - source[i].green) +
            std::abs(negative[i].blue - source[i].blue);
        positive_delta += std::abs(positive[i].red - source[i].red) +
            std::abs(positive[i].green - source[i].green) +
            std::abs(positive[i].blue - source[i].blue);
        expect(std::abs(monochrome[i].red - monochrome[i].green) < 1.0e-6F &&
                   std::abs(monochrome[i].green - monochrome[i].blue) < 1.0e-6F,
               "monochrome target remains neutral");
    }
    expect(positive_delta < negative_delta,
           "positive scanner character is weaker than negative");
}

void test_matched_profile_relative_signature_selection() {
    constexpr std::uint32_t width = 48U;
    constexpr std::uint32_t height = 32U;
    const auto source = fixture(width, height);
    auto common = source;
    auto ektar = source;
    auto pairless = source;
    auto mismatched = source;

    negaflow::imaging::ScannerTargetGradeInfo common_info{};
    negaflow::imaging::ScannerTargetGradeInfo ektar_info{};
    negaflow::imaging::ScannerTargetGradeInfo pairless_info{};
    negaflow::imaging::ScannerTargetGradeInfo mismatched_info{};
    expect(negaflow::imaging::apply_scanner_target_grade(
               view(common, width, height),
               negaflow::imaging::ScannerTargetStyle::noritsu,
               false, false, {}, common_info) == negaflow::core::KernelStatus::ok,
           "rendering without profile succeeds");
    expect(negaflow::imaging::apply_scanner_target_grade(
               view(ektar, width, height),
               negaflow::imaging::ScannerTargetStyle::noritsu,
               false, false,
               L"noritsu__color-nega__kodak-ektar-100",
               ektar_info) == negaflow::core::KernelStatus::ok,
           "matched Ektar signature succeeds");
    expect(negaflow::imaging::apply_scanner_target_grade(
               view(pairless, width, height),
               negaflow::imaging::ScannerTargetStyle::noritsu,
               false, false,
               L"noritsu__color-nega__kodak-portra-400",
               pairless_info) == negaflow::core::KernelStatus::ok,
           "pairless profile keeps the rendering");
    expect(negaflow::imaging::apply_scanner_target_grade(
               view(mismatched, width, height),
               negaflow::imaging::ScannerTargetStyle::sp3000,
               false, false,
               L"noritsu__color-nega__kodak-ektar-100",
               mismatched_info) == negaflow::core::KernelStatus::ok,
           "mismatched scanner profile keeps the rendering");

    expect(!common_info.relative_signature_applied,
           "empty profile applies no relative signature (rendering table carries identity)");
    expect(ektar_info.relative_signature_applied,
           "matched profile selects film-specific relative signature");
    expect(!pairless_info.relative_signature_applied,
           "profile without a matched roll pair invents no relative signature");
    expect(!mismatched_info.relative_signature_applied,
           "profile from the other scanner invents no relative signature");
    expect(images_differ(common, ektar),
           "a chosen film profile adds its measured relative signature");
    expect(!images_differ(common, pairless),
           "a profile without a matched pair leaves the rendering alone");
}

// 맥 `ScannerRenderingTests` 와 같은 골든입니다(적합 스크립트의 기준 구현, double).
// 두 플랫폼의 렌더링이 같은 식·같은 표라는 것을 이 값이 고정합니다. 화상이 작아(20px)
// NORITSU 질감은 σ 가 0.05px 아래라 걸리지 않습니다 — 렌더링만 비교됩니다.
constexpr std::array<std::array<double, 3U>, 20U> golden_inputs{{
    {0.0, 0.0, 0.0},
    {1e-06, 1e-06, 1e-06},
    {0.0005, 0.0005, 0.0005},
    {0.01, 0.01, 0.01},
    {0.05, 0.05, 0.05},
    {0.18, 0.18, 0.18},
    {0.4, 0.4, 0.4},
    {0.7, 0.7, 0.7},
    {1.0, 1.0, 1.0},
    {2.0, 2.0, 2.0},
    {0.18, 0.09, 0.05},
    {0.05, 0.12, 0.3},
    {0.3, 0.2, 0.1},
    {0.6, 0.1, 0.05},
    {0.05, 0.5, 0.1},
    {0.02, 0.05, 0.6},
    {0.9, 0.85, 0.2},
    {1.5, 0.2, 0.1},
    {-0.05, 0.2, 0.3},
    {0.2, 0.2, -0.01}
}};

void expect_golden(
    const negaflow::imaging::ScannerTargetStyle style,
    const std::array<std::array<double, 3U>, 20U>& expected,
    const char* const message) {
    std::vector<negaflow::core::Rgba32F> pixels;
    for (const auto& v : golden_inputs) {
        pixels.push_back({static_cast<float>(v[0]), static_cast<float>(v[1]),
                          static_cast<float>(v[2]), 1.0F});
    }
    negaflow::imaging::ScannerTargetGradeInfo info{};
    expect(negaflow::imaging::apply_scanner_target_grade(
               view(pixels, static_cast<std::uint32_t>(pixels.size()), 1U),
               style, false, false, {}, info) == negaflow::core::KernelStatus::ok,
           message);
    expect(!info.texture_applied, "golden image is too small for the texture");
    for (std::size_t i = 0U; i < expected.size(); ++i) {
        // CPU 는 double 이지만 sRGB 왕복과 저장이 float 라 그 정밀도까지 맞습니다.
        expect(std::abs(pixels[i].red - expected[i][0]) < 2.0e-6 &&
                   std::abs(pixels[i].green - expected[i][1]) < 2.0e-6 &&
                   std::abs(pixels[i].blue - expected[i][2]) < 2.0e-6,
               message);
    }
}

void test_rendering_matches_macos_golden() {
    expect_golden(negaflow::imaging::ScannerTargetStyle::sp3000, {{
        {0.000000000, 0.000000000, 0.000000000},
        {0.000000000, 0.000000000, 0.000000000},
        {0.003077398, 0.003077398, 0.003077398},
        {0.009874576, 0.009874576, 0.009874576},
        {0.038835673, 0.038835673, 0.038835673},
        {0.184842980, 0.184842980, 0.184842980},
        {0.527002073, 0.527002073, 0.527002073},
        {0.889629590, 0.889629590, 0.889629590},
        {0.948009224, 0.948009224, 0.948009224},
        {1.000000000, 1.000000000, 1.000000000},
        {0.167872384, 0.079947559, 0.042618936},
        {0.042558472, 0.109996501, 0.297167332},
        {0.345269853, 0.215223019, 0.095935079},
        {0.707538922, 0.088863754, 0.039825418},
        {0.036818102, 0.668358195, 0.088113503},
        {0.015744717, 0.040825820, 0.540912902},
        {1.000000000, 0.949530839, 0.416692060},
        {1.000000000, 0.519818167, 0.497384586},
        {0.000002736, 0.199118249, 0.314897082},
        {0.207233137, 0.207233137, 0.000002442}
    }}, "SP rendering matches the macOS golden");
    expect_golden(negaflow::imaging::ScannerTargetStyle::noritsu, {{
        {0.000000000, 0.000000000, 0.000000000},
        {0.000000000, 0.000000000, 0.000000000},
        {0.003441977, 0.003282575, 0.003348449},
        {0.010066629, 0.009600432, 0.009793092},
        {0.033811913, 0.034628369, 0.034068770},
        {0.136824079, 0.146747329, 0.142889845},
        {0.441281422, 0.486056674, 0.471569752},
        {0.837352542, 0.942752985, 0.912036812},
        {0.872718562, 0.983743762, 0.951553836},
        {1.000000000, 1.000000000, 1.000000000},
        {0.124193300, 0.068193066, 0.038275060},
        {0.036979125, 0.090172461, 0.210773412},
        {0.246657457, 0.175533638, 0.083930386},
        {0.495497603, 0.086051250, 0.041350238},
        {0.041273376, 0.580296467, 0.094816761},
        {0.016618380, 0.040153677, 0.380541719},
        {0.958946444, 1.000000000, 0.308551287},
        {1.000000000, 0.504135407, 0.469454865},
        {0.000007803, 0.157324181, 0.229307338},
        {0.153223092, 0.164490917, 0.000007423}
    }}, "HS rendering matches the macOS golden");
    expect_golden(negaflow::imaging::ScannerTargetStyle::f135, {{
        {0.002978025, 0.002978025, 0.002978025},
        {0.002978025, 0.002978025, 0.002978025},
        {0.003739903, 0.003739903, 0.003739903},
        {0.005450417, 0.005450417, 0.005450417},
        {0.024330880, 0.024330880, 0.024330880},
        {0.184842980, 0.184842980, 0.184842980},
        {0.527002073, 0.527002073, 0.527002073},
        {0.889629590, 0.889629590, 0.889629590},
        {0.948009224, 0.948009224, 0.948009224},
        {1.000000000, 1.000000000, 1.000000000},
        {0.143060362, 0.068131079, 0.036319735},
        {0.037794049, 0.097682386, 0.263899432},
        {0.349846259, 0.218075709, 0.097206658},
        {0.715637034, 0.089880841, 0.040281239},
        {0.036818102, 0.668358195, 0.088113503},
        {0.012250708, 0.031765905, 0.420875517},
        {1.000000000, 0.949530839, 0.416692060},
        {1.000000000, 0.519818167, 0.497384586},
        {0.000002692, 0.195932387, 0.309858777},
        {0.208082007, 0.208082007, 0.000002452}
    }}, "F135 rendering matches the macOS golden");
    expect_golden(negaflow::imaging::ScannerTargetStyle::hr, {{
        {0.002978025, 0.002978025, 0.002978025},
        {0.002978025, 0.002978025, 0.002978025},
        {0.003739903, 0.003739903, 0.003739903},
        {0.005450417, 0.005450417, 0.005450417},
        {0.024330880, 0.024330880, 0.024330880},
        {0.184842980, 0.184842980, 0.184842980},
        {0.527002073, 0.527002073, 0.527002073},
        {0.889629590, 0.889629590, 0.889629590},
        {0.948009224, 0.948009224, 0.948009224},
        {1.000000000, 1.000000000, 1.000000000},
        {0.137535913, 0.069506157, 0.038965752},
        {0.041126800, 0.098517997, 0.245808406},
        {0.340143960, 0.220202164, 0.104711758},
        {0.677447508, 0.100453205, 0.048006155},
        {0.046133951, 0.664090038, 0.102961650},
        {0.014660483, 0.035223989, 0.379524548},
        {1.000000000, 0.950992111, 0.402216960},
        {1.000000000, 0.520210741, 0.493495820},
        {0.000006628, 0.196907786, 0.300185068},
        {0.208081724, 0.208081724, 0.000006082}
    }}, "HR rendering matches the macOS golden");
}

double lab_a(const negaflow::core::Rgba32F& pixel) {
    const auto f = [](const double t) {
        return t > 216.0 / 24389.0 ? std::cbrt(t) : (t * 24389.0 / 27.0 + 16.0) / 116.0;
    };
    const double x = ((0.4124564 * pixel.red) + (0.3575761 * pixel.green) +
                      (0.1804375 * pixel.blue)) / 0.95047;
    const double y = (0.2126729 * pixel.red) + (0.7151522 * pixel.green) + (0.0721750 * pixel.blue);
    return 500.0 * (f(x) - f(y));
}

// 회색은 회색으로 남고(SP·F135·HR), HS 만 같은 롤 실측 차이만큼 초록 쪽으로 기웁니다.
// 고른 SP 프로파일은 여전히 실측 차분을 얹습니다.
void test_neutrals_and_chosen_profile() {
    std::vector<negaflow::core::Rgba32F> source;
    for (int i = 0; i <= 16; ++i) {
        const float v = static_cast<float>(0.18 * std::pow(2.0, -6.0 + (0.5 * i)));
        source.push_back({v, v, v, 1.0F});
    }
    const auto width = static_cast<std::uint32_t>(source.size());
    for (const auto style : {negaflow::imaging::ScannerTargetStyle::sp3000,
                             negaflow::imaging::ScannerTargetStyle::f135,
                             negaflow::imaging::ScannerTargetStyle::hr}) {
        auto graded = source;
        negaflow::imaging::ScannerTargetGradeInfo info{};
        expect(negaflow::imaging::apply_scanner_target_grade(
                   view(graded, width, 1U), style, false, false, {}, info) ==
                   negaflow::core::KernelStatus::ok,
               "neutral grade succeeds");
        for (const auto& p : graded) {
            expect(std::abs(p.red - p.green) < 1.0e-6F && std::abs(p.green - p.blue) < 1.0e-6F,
                   "SP/F135/HR keep neutrals neutral");
        }
    }
    auto hs = source;
    negaflow::imaging::ScannerTargetGradeInfo hs_info{};
    expect(negaflow::imaging::apply_scanner_target_grade(
               view(hs, width, 1U), negaflow::imaging::ScannerTargetStyle::noritsu,
               false, false, {}, hs_info) == negaflow::core::KernelStatus::ok,
           "HS neutral grade succeeds");
    for (const auto& p : hs) {
        const double a = lab_a(p);
        expect(a < 0.6 && a > -5.0, "HS neutral a* stays within the measured green lean");
    }

    auto chosen = source;
    negaflow::imaging::ScannerTargetGradeInfo chosen_info{};
    expect(negaflow::imaging::apply_scanner_target_grade(
               view(chosen, width, 1U),
               negaflow::imaging::ScannerTargetStyle::sp3000,
               false, false,
               L"sp-3000__color-nega__kodak-ektar-100",
               chosen_info) == negaflow::core::KernelStatus::ok,
           "SP with a bundled profile succeeds");
    expect(chosen_info.relative_signature_applied,
           "a bundled SP profile the user picks still applies its measured signature");
}

}  // namespace

int main() {
    try {
        test_four_targets_are_distinct_and_bounded();
        test_positive_is_weaker_and_monochrome_stays_neutral();
        test_matched_profile_relative_signature_selection();
        test_rendering_matches_macos_golden();
        test_neutrals_and_chosen_profile();
        std::cout << "Scanner target grade tests passed\n";
        return 0;
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        return 1;
    }
}
