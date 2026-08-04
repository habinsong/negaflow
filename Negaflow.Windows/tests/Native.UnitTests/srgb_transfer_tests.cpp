#include "negaflow/color/srgb_transfer.h"

#include <cmath>
#include <iostream>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

void expect_near(
    const float actual,
    const float expected,
    const float tolerance,
    const char* const message) {
    expect(std::abs(actual - expected) <= tolerance, message);
}

}  // namespace

int main() {
    expect_near(negaflow::color::srgb_encoded_to_linear(0.0F), 0.0F, 0.0F, "zero");
    expect_near(
        negaflow::color::srgb_encoded_to_linear(0.04045F),
        0.003130805F,
        1.0e-8F,
        "sRGB breakpoint");
    expect_near(
        negaflow::color::srgb_encoded_to_linear(0.5F),
        0.21404114F,
        1.0e-7F,
        "sRGB midpoint");
    expect_near(negaflow::color::srgb_encoded_to_linear(1.0F), 1.0F, 1.0e-7F, "one");
    expect_near(
        negaflow::color::srgb_encoded_to_linear(-0.5F),
        -negaflow::color::srgb_encoded_to_linear(0.5F),
        1.0e-7F,
        "extended negative values are sign preserving");
    expect(
        negaflow::color::srgb_encoded_to_linear(1.25F) > 1.0F,
        "extended positive values are not clamped");
    expect_near(negaflow::color::linear_to_srgb_encoded(0.0F), 0.0F, 0.0F, "encode zero");
    expect_near(
        negaflow::color::linear_to_srgb_encoded(0.0031308F),
        0.040449936F,
        1.0e-8F,
        "encode sRGB breakpoint");
    expect_near(
        negaflow::color::linear_to_srgb_encoded(0.21404114F),
        0.5F,
        1.0e-7F,
        "encode sRGB midpoint");
    expect_near(negaflow::color::linear_to_srgb_encoded(1.0F), 1.0F, 1.0e-7F, "encode one");
    expect_near(
        negaflow::color::linear_to_srgb_encoded(-0.21404114F),
        -0.5F,
        1.0e-7F,
        "encode extended negative values are sign preserving");
    expect(
        negaflow::color::linear_to_srgb_encoded(1.25F) > 1.0F,
        "encode extended positive values are not clamped");

    if (failures != 0) {
        std::cerr << failures << " sRGB transfer test(s) failed\n";
        return 1;
    }
    std::cout << "sRGB transfer tests passed\n";
    return 0;
}
