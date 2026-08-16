#include "negaflow/imaging/color_model.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <string>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool exact_pixel(
    const negaflow::core::Rgba32F left,
    const negaflow::core::Rgba32F right) noexcept {
    return left.red == right.red && left.green == right.green &&
           left.blue == right.blue && left.alpha == right.alpha;
}

void test_identity_and_fixed_matrix_controls() {
    std::array<negaflow::core::Rgba32F, 3> pixels{{
        {-0.2F, 0.4F, 1.2F, 0.25F},
        {0.6F, 0.3F, 0.1F, 1.0F},
        {91.0F, 92.0F, 93.0F, 0.0F},
    }};
    const auto original = pixels;
    expect(
        negaflow::imaging::apply_color_model(
            {pixels.data(), pixels.size(), 2U, 1U, 3U},
            {pixels.data(), pixels.size(), 2U, 1U, 3U},
            {}) == negaflow::core::KernelStatus::ok &&
            exact_pixel(pixels[0], original[0]) &&
            exact_pixel(pixels[1], original[1]) &&
            exact_pixel(pixels[2], original[2]),
        "identity ColorModel preserves extended pixels and padding");

    negaflow::imaging::ColorModelParameters controls{};
    controls.warmth = 1.0F;
    controls.tint = 1.0F;
    controls.red_primary = 0.5F;
    pixels = original;
    expect(
        negaflow::imaging::apply_color_model(
            {pixels.data(), pixels.size(), 2U, 1U, 3U},
            {pixels.data(), pixels.size(), 2U, 1U, 3U},
            controls) == negaflow::core::KernelStatus::ok &&
            std::abs(pixels[1].red - (0.6F * 1.18F * 0.88F * 1.16F)) < 1.0e-6F &&
            std::abs(pixels[1].green - (0.3F * 1.03F * 1.24F)) < 1.0e-6F &&
            std::abs(pixels[1].blue - (0.1F * 0.82F * 0.88F)) < 1.0e-6F &&
            pixels[1].alpha == 1.0F && exact_pixel(pixels[2], original[2]),
        "ColorModel applies macOS matrix controls in fixed order");
}

void test_chroma_controls_and_validation() {
    negaflow::core::Rgba32F low_chroma{0.52F, 0.50F, 0.48F, 0.75F};
    const auto original = low_chroma;
    negaflow::imaging::ColorModelParameters controls{};
    controls.color_depth = 0.5F;
    controls.vibrance = 0.5F;
    controls.saturation = 0.5F;
    expect(
        negaflow::imaging::apply_color_model(
            {&low_chroma, 1U, 1U, 1U, 1U},
            {&low_chroma, 1U, 1U, 1U, 1U},
            controls) == negaflow::core::KernelStatus::ok &&
            (low_chroma.red - low_chroma.blue) >
                (original.red - original.blue) &&
            low_chroma.alpha == original.alpha,
        "ColorModel chroma controls increase low-chroma separation");

    controls = {};
    controls.tint = 1.01F;
    expect(!negaflow::imaging::valid_color_model_parameters(controls),
           "ColorModel rejects controls outside the slider range");
    controls.tint = std::numeric_limits<float>::quiet_NaN();
    expect(
        negaflow::imaging::apply_color_model(
            {&low_chroma, 1U, 1U, 1U, 1U},
            {&low_chroma, 1U, 1U, 1U, 1U},
            controls) == negaflow::core::KernelStatus::non_finite_parameter,
        "ColorModel rejects non-finite controls");
}

[[nodiscard]] std::vector<negaflow::core::Rgba32F> read_rgba_f32(
    const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    std::vector<negaflow::core::Rgba32F> pixels(256U * 141U);
    input.read(
        reinterpret_cast<char*>(pixels.data()),
        static_cast<std::streamsize>(pixels.size() * sizeof(negaflow::core::Rgba32F)));
    expect(
        (input.good() || input.eof()) &&
            input.gcount() == static_cast<std::streamsize>(pixels.size() * sizeof(negaflow::core::Rgba32F)),
        "CIVibrance f32 golden is readable");
    pixels.resize(33U * 33U * 33U);
    return pixels;
}

[[nodiscard]] float max_rgb_difference(
    const std::vector<negaflow::core::Rgba32F>& actual,
    const std::vector<negaflow::core::Rgba32F>& expected) noexcept {
    if (actual.size() != expected.size()) return std::numeric_limits<float>::infinity();
    float maximum = 0.0F;
    for (std::size_t index = 0U; index < actual.size(); ++index) {
        maximum = std::max(maximum, std::abs(actual[index].red - expected[index].red));
        maximum = std::max(maximum, std::abs(actual[index].green - expected[index].green));
        maximum = std::max(maximum, std::abs(actual[index].blue - expected[index].blue));
        maximum = std::max(maximum, std::abs(actual[index].alpha - expected[index].alpha));
    }
    return maximum;
}

void test_civibrance_goldens(const std::filesystem::path& golden_root) {
    const auto input = read_rgba_f32(golden_root / L"civibrance33-input-256x141.f32");
    struct Case final {
        float amount;
        const wchar_t* file;
    };
    constexpr Case cases[]{
        {-0.80F, L"civibrance33-am0.800-256x141.f32"},
        {-0.60F, L"civibrance33-am0.600-256x141.f32"},
        {-0.40F, L"civibrance33-am0.400-256x141.f32"},
        {-0.20F, L"civibrance33-am0.200-256x141.f32"},
        {-0.05F, L"civibrance33-am0.050-256x141.f32"},
        { 0.05F, L"civibrance33-a0.050-256x141.f32"},
        { 0.10F, L"civibrance33-a0.100-256x141.f32"},
        { 0.15F, L"civibrance33-a0.150-256x141.f32"},
        { 0.20F, L"civibrance33-a0.200-256x141.f32"},
        { 0.25F, L"civibrance33-a0.250-256x141.f32"},
        { 0.30F, L"civibrance33-a0.300-256x141.f32"},
        { 0.35F, L"civibrance33-a0.350-256x141.f32"},
        { 0.40F, L"civibrance33-a0.400-256x141.f32"},
        { 0.45F, L"civibrance33-a0.450-256x141.f32"},
        { 0.50F, L"civibrance33-a0.500-256x141.f32"},
        { 0.60F, L"civibrance33-a0.600-256x141.f32"},
        { 0.80F, L"civibrance33-a0.800-256x141.f32"},
    };
    for (const Case& entry : cases) {
        auto actual = input;
        negaflow::imaging::ColorModelParameters parameters{};
        parameters.vibrance = entry.amount / 0.8F;
        const auto status = negaflow::imaging::apply_color_model(
            {actual.data(), actual.size(), static_cast<std::uint32_t>(actual.size()), 1U,
             static_cast<std::uint32_t>(actual.size())},
            {actual.data(), actual.size(), static_cast<std::uint32_t>(actual.size()), 1U,
             static_cast<std::uint32_t>(actual.size())},
            parameters);
        const auto expected = read_rgba_f32(golden_root / entry.file);
        const float difference = max_rgb_difference(actual, expected);
        if (difference >= 0.0020F) {
            std::cerr << "  CIVibrance amount=" << entry.amount
                      << " max_abs_difference=" << difference << '\n';
        }
        expect(
            status == negaflow::core::KernelStatus::ok && difference < 0.0020F,
            "ColorModel vibrance follows the full macOS CIVibrance golden range");
    }
}

}  // namespace

int main(const int argc, char** argv) {
    test_identity_and_fixed_matrix_controls();
    test_chroma_controls_and_validation();
    expect(argc == 2, "ColorModel CTest receives the CIVibrance golden directory");
    if (argc == 2) {
        test_civibrance_goldens(argv[1]);
    }
    if (failures == 0) {
        std::cout << "ColorModel tests passed\n";
    }
    return failures == 0 ? 0 : 1;
}
