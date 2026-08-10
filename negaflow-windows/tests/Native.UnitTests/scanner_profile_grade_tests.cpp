#include "negaflow/imaging/scanner_profile_grade.h"

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

void test_registry_resolves_canonical_profile() {
    negaflow::imaging::ScannerProfileGradeParameters parameters{};
    std::string_view hash;
    expect(
        negaflow::imaging::try_get_scanner_profile_grade_parameters(
            L"noritsu__color-nega__kodak-ultramax-400", parameters, hash),
        "canonical scanner profile resolves");
    expect(std::abs(parameters.gamma - 0.982067196F) < 1.0e-7F,
           "profile gamma matches the compiled manifest derivation");
    expect(hash == "sha256:732c440568ab0c40e00cf1ad5f4931190e52c6b16f724daf9067b1065d135310",
           "profile hash remains available for render provenance");
}

void test_unknown_profile_is_exact_identity() {
    std::vector<negaflow::core::Rgba32F> pixels{{0.42F, 0.40F, 0.36F, 0.65F}};
    const auto before = pixels;
    negaflow::imaging::ScannerProfileGradeInfo info{};
    expect(
        negaflow::imaging::apply_scanner_profile_grade(
            view(pixels, 1U, 1U), L"unknown-profile", info) ==
            negaflow::core::KernelStatus::ok,
        "unknown scanner profile follows optional-load semantics");
    expect(!info.profile_found && !info.applied,
           "unknown scanner profile is reported inactive");
    expect(
        pixels[0].red == before[0].red &&
            pixels[0].green == before[0].green &&
            pixels[0].blue == before[0].blue &&
            pixels[0].alpha == before[0].alpha,
        "unknown scanner profile is exact identity");
}

void test_profiles_produce_distinct_bounded_grades() {
    constexpr std::uint32_t width = 8U;
    constexpr std::uint32_t height = 8U;
    std::vector<negaflow::core::Rgba32F> ektar(width * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float value = 0.18F + (0.62F * static_cast<float>(x) / 7.0F);
            ektar[static_cast<std::size_t>(y) * width + x] = {
                value,
                value * 0.90F,
                value * 0.74F,
                0.70F,
            };
        }
    }
    auto ultramax = ektar;
    negaflow::imaging::ScannerProfileGradeInfo ektar_info{};
    negaflow::imaging::ScannerProfileGradeInfo ultramax_info{};
    expect(
        negaflow::imaging::apply_scanner_profile_grade(
            view(ektar, width, height),
            L"noritsu__color-nega__kodak-ektar-100",
            ektar_info) == negaflow::core::KernelStatus::ok,
        "Ektar scanner profile grade succeeds");
    expect(
        negaflow::imaging::apply_scanner_profile_grade(
            view(ultramax, width, height),
            L"noritsu__color-nega__kodak-ultramax-400",
            ultramax_info) == negaflow::core::KernelStatus::ok,
        "UltraMax scanner profile grade succeeds");
    expect(ektar_info.applied && ultramax_info.applied,
           "known scanner profiles are active");
    bool distinct = false;
    for (std::size_t i = 0U; i < ektar.size(); ++i) {
        distinct = distinct || std::abs(ektar[i].red - ultramax[i].red) > 1.0e-4F ||
                   std::abs(ektar[i].green - ultramax[i].green) > 1.0e-4F ||
                   std::abs(ektar[i].blue - ultramax[i].blue) > 1.0e-4F;
        expect(ektar[i].red >= 0.0F && ektar[i].red <= 1.0F &&
                   ektar[i].green >= 0.0F && ektar[i].green <= 1.0F &&
                   ektar[i].blue >= 0.0F && ektar[i].blue <= 1.0F,
               "scanner profile output stays in the unit gamut");
        expect(ektar[i].alpha == 0.70F && ultramax[i].alpha == 0.70F,
               "scanner profile grade preserves alpha");
    }
    expect(distinct, "different scanner profiles produce distinct tone and color");
}

}  // namespace

int main() {
    try {
        test_registry_resolves_canonical_profile();
        test_unknown_profile_is_exact_identity();
        test_profiles_produce_distinct_bounded_grades();
        std::cout << "Scanner profile grade tests passed\n";
        return 0;
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        return 1;
    }
}
