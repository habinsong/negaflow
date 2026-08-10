#include "negaflow/imaging/color_model.h"

#include <array>
#include <cmath>
#include <iostream>
#include <limits>

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

}  // namespace

int main() {
    test_identity_and_fixed_matrix_controls();
    test_chroma_controls_and_validation();
    if (failures == 0) {
        std::cout << "ColorModel tests passed\n";
    }
    return failures == 0 ? 0 : 1;
}
