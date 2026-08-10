#include "negaflow/imaging/scanner_target_grade.h"

#include <algorithm>
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
           "common relative signature succeeds");
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
           "pairless profile keeps documented character");
    expect(negaflow::imaging::apply_scanner_target_grade(
               view(mismatched, width, height),
               negaflow::imaging::ScannerTargetStyle::sp3000,
               false, false,
               L"noritsu__color-nega__kodak-ektar-100",
               mismatched_info) == negaflow::core::KernelStatus::ok,
           "mismatched scanner profile keeps documented character");

    expect(common_info.relative_signature_applied,
           "empty profile selects consistent common relative signature");
    expect(ektar_info.relative_signature_applied,
           "matched profile selects film-specific relative signature");
    expect(!pairless_info.relative_signature_applied,
           "profile without a matched roll pair invents no relative signature");
    expect(!mismatched_info.relative_signature_applied,
           "profile from the other scanner invents no relative signature");
    expect(images_differ(common, ektar),
           "film-specific and common relative signatures remain distinct");
    expect(images_differ(common, pairless),
           "relative refinement changes documented-only pixels");
}

}  // namespace

int main() {
    try {
        test_four_targets_are_distinct_and_bounded();
        test_positive_is_weaker_and_monochrome_stays_neutral();
        test_matched_profile_relative_signature_selection();
        std::cout << "Scanner target grade tests passed\n";
        return 0;
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        return 1;
    }
}
