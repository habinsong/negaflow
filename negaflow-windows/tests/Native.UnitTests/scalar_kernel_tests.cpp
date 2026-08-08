#include "negaflow/core/negative_inversion.h"
#include "negaflow/core/pixel.h"
#include "negaflow/core/pointwise.h"
#include "scalar_foundation_fixture.h"

#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstdint>
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

void expect_status(
    const negaflow::core::KernelStatus actual,
    const negaflow::core::KernelStatus expected,
    const char* const message) {
    expect(actual == expected, message);
}

[[nodiscard]] bool nearly_equal(
    const float actual,
    const float expected,
    const float absolute_tolerance = 5.0e-6F,
    const float relative_tolerance = 5.0e-6F) {
    const float difference = std::abs(actual - expected);
    const float scale = std::max(std::abs(actual), std::abs(expected));
    return difference <= absolute_tolerance + (relative_tolerance * scale);
}

void test_layout_validation() {
    negaflow::core::Rgba32F pixel{};
    const negaflow::core::ConstImageView valid{&pixel, 1U, 1U, 1U, 1U};
    expect_status(
        negaflow::core::validate_image_view(valid),
        negaflow::core::KernelStatus::ok,
        "1x1 layout is valid");

    const negaflow::core::ConstImageView null_view{nullptr, 1U, 1U, 1U, 1U};
    expect_status(
        negaflow::core::validate_image_view(null_view),
        negaflow::core::KernelStatus::invalid_argument,
        "null pixel storage is rejected");

    const negaflow::core::ConstImageView zero_width{&pixel, 1U, 0U, 1U, 1U};
    expect_status(
        negaflow::core::validate_image_view(zero_width),
        negaflow::core::KernelStatus::invalid_dimensions,
        "zero width is rejected");

    const negaflow::core::ConstImageView short_stride{&pixel, 1U, 2U, 1U, 1U};
    expect_status(
        negaflow::core::validate_image_view(short_stride),
        negaflow::core::KernelStatus::invalid_stride,
        "stride shorter than width is rejected");

    const negaflow::core::ConstImageView too_small{&pixel, 1U, 1U, 2U, 1U};
    expect_status(
        negaflow::core::validate_image_view(too_small),
        negaflow::core::KernelStatus::buffer_too_small,
        "insufficient capacity is rejected");

    const negaflow::core::ConstImageView overflow{
        &pixel,
        std::numeric_limits<std::size_t>::max(),
        std::numeric_limits<std::uint32_t>::max(),
        std::numeric_limits<std::uint32_t>::max(),
        std::numeric_limits<std::size_t>::max(),
    };
    expect_status(
        negaflow::core::validate_image_view(overflow),
        negaflow::core::KernelStatus::size_overflow,
        "oversized row arithmetic is rejected");
}

void test_pointwise_extended_range_and_stride() {
    const negaflow::core::Rgba32F padding{91.0F, 92.0F, 93.0F, 0.0F};
    std::array<negaflow::core::Rgba32F, 8> input{{
        {-0.1F, 0.18F, 1.1F, 0.0F},
        {0.0F, 1.0F, 2.0F, 0.5F},
        {0.25F, 0.5F, 0.75F, 1.0F},
        padding,
        {1.5F, -0.25F, 0.125F, 1.0F},
        {0.2F, 0.3F, 0.4F, 0.25F},
        {4.0F, 3.0F, 2.0F, 0.75F},
        padding,
    }};
    std::array<negaflow::core::Rgba32F, 8> output{};
    output[3] = padding;
    output[7] = padding;

    const negaflow::core::ConstImageView input_view{input.data(), input.size(), 3U, 2U, 4U};
    const negaflow::core::ImageView output_view{output.data(), output.size(), 3U, 2U, 4U};
    expect_status(
        negaflow::core::apply_exposure(input_view, output_view, 1.0F),
        negaflow::core::KernelStatus::ok,
        "exposure succeeds on an odd-width strided fixture");
    expect(nearly_equal(output[0].red, -0.2F), "exposure preserves negative working values");
    expect(nearly_equal(output[0].green, 0.36F), "exposure doubles mid gray");
    expect(nearly_equal(output[0].blue, 2.2F), "exposure preserves values above one");
    expect(output[0].alpha == input[0].alpha, "exposure preserves zero alpha exactly");
    expect(output[1].alpha == input[1].alpha, "exposure preserves fractional alpha exactly");
    expect(output[3].red == padding.red && output[7].blue == padding.blue,
           "pointwise kernels do not write stride padding");

    std::array<negaflow::core::Rgba32F, 1> matrix_input{{{-0.1F, 0.25F, 1.1F, 0.5F}}};
    std::array<negaflow::core::Rgba32F, 1> matrix_output{};
    const negaflow::core::ColorMatrix3x4 matrix{{
        1.0F, 0.0F, 0.0F, 0.25F,
        0.0F, 2.0F, 0.0F, -0.75F,
        0.0F, 0.0F, 2.0F, 0.0F,
    }};
    expect_status(
        negaflow::core::apply_color_matrix(
            {matrix_input.data(), matrix_input.size(), 1U, 1U, 1U},
            {matrix_output.data(), matrix_output.size(), 1U, 1U, 1U},
            matrix),
        negaflow::core::KernelStatus::ok,
        "color matrix succeeds");
    expect(nearly_equal(matrix_output[0].red, 0.15F), "matrix applies RGB bias");
    expect(nearly_equal(matrix_output[0].green, -0.25F), "matrix does not clamp negative output");
    expect(nearly_equal(matrix_output[0].blue, 2.2F), "matrix does not clamp highlight output");
    expect(matrix_output[0].alpha == 0.5F, "matrix preserves alpha exactly");
}

void test_parameter_and_sample_rejection() {
    const negaflow::core::Rgba32F source{0.1F, 0.2F, 0.3F, 1.0F};
    negaflow::core::Rgba32F output{};
    const negaflow::core::ConstImageView input_view{&source, 1U, 1U, 1U, 1U};
    const negaflow::core::ImageView output_view{&output, 1U, 1U, 1U, 1U};
    expect_status(
        negaflow::core::apply_exposure(
            input_view,
            output_view,
            std::numeric_limits<float>::quiet_NaN()),
        negaflow::core::KernelStatus::non_finite_parameter,
        "non-finite exposure is rejected");

    negaflow::core::ColorMatrix3x4 matrix = negaflow::core::ColorMatrix3x4::identity();
    matrix.values[3] = std::numeric_limits<float>::infinity();
    expect_status(
        negaflow::core::apply_color_matrix(input_view, output_view, matrix),
        negaflow::core::KernelStatus::non_finite_parameter,
        "non-finite matrix is rejected");

    const negaflow::core::Rgba32F nan_source{
        std::numeric_limits<float>::quiet_NaN(),
        0.2F,
        0.3F,
        1.0F,
    };
    expect_status(
        negaflow::core::apply_exposure(
            {&nan_source, 1U, 1U, 1U, 1U},
            output_view,
            0.0F),
        negaflow::core::KernelStatus::non_finite_input,
        "non-finite source sample is rejected");

    const negaflow::core::Rgba32F invalid_alpha{0.1F, 0.2F, 0.3F, 1.1F};
    expect_status(
        negaflow::core::validate_finite_pixels({&invalid_alpha, 1U, 1U, 1U, 1U}),
        negaflow::core::KernelStatus::alpha_out_of_range,
        "alpha outside zero-to-one is rejected");
}

void test_response_constant_bits() {
    const negaflow::core::PrintResponse color =
        negaflow::core::color_negative_print_response();
    expect(std::bit_cast<std::uint32_t>(color.normal_range) == 0x3FC66666U,
           "color density range float bits are locked");
    expect(std::bit_cast<std::uint32_t>(color.y_ceiling) == 0xBD3B6C35U,
           "color response ceiling float bits are locked");
    expect(std::bit_cast<std::uint32_t>(color.amplitude) == 0x403D124FU,
           "color response amplitude float bits are locked");
    expect(std::bit_cast<std::uint32_t>(color.rate) == 0x407B6C08U,
           "color response rate float bits are locked");
    expect(std::bit_cast<std::uint32_t>(color.shape) == 0x3F5F49D0U,
           "color response shape float bits are locked");

    const negaflow::core::PrintResponse black_and_white =
        negaflow::core::black_and_white_negative_print_response();
    expect(std::bit_cast<std::uint32_t>(black_and_white.normal_range) == 0x400AE148U,
           "B&W density range float bits are locked");
    expect(std::bit_cast<std::uint32_t>(black_and_white.rate) == 0x4074F68DU,
           "B&W response rate float bits are locked");
    expect(std::bit_cast<std::uint32_t>(black_and_white.shape) == 0x3F839CBAU,
           "B&W response shape float bits are locked");
}

void test_negative_inversion_color_fixture() {
    constexpr float base = negaflow::fixtures::color_negative_dmin;
    const float mid_transmission =
        base * std::pow(10.0F, -negaflow::fixtures::color_negative_cases[1].density);
    const float dense_transmission =
        base * std::pow(10.0F, -negaflow::fixtures::color_negative_cases[2].density);
    std::array<negaflow::core::Rgba32F, 4> input{{
        {base, base, base, 1.0F},
        {mid_transmission, mid_transmission, mid_transmission, 0.5F},
        {dense_transmission, dense_transmission, dense_transmission, 1.0F},
        {0.90F, 1.0e-8F, -0.1F, 0.25F},
    }};
    std::array<negaflow::core::Rgba32F, 4> output{};
    const negaflow::core::NegativeInversionParameters parameters{
        {base, base, base},
        {
            negaflow::fixtures::color_negative_dmax_normalized,
            negaflow::fixtures::color_negative_dmax_normalized,
            negaflow::fixtures::color_negative_dmax_normalized,
        },
    };
    expect_status(
        negaflow::core::apply_negative_inversion(
            {input.data(), input.size(), 4U, 1U, 4U},
            {output.data(), output.size(), 4U, 1U, 4U},
            parameters,
            negaflow::core::color_negative_print_response()),
        negaflow::core::KernelStatus::ok,
        "color negative inversion fixture succeeds");

    expect(nearly_equal(
               output[0].red,
               static_cast<float>(negaflow::fixtures::color_negative_cases[0].expected),
               2.0e-7F,
               2.0e-6F),
           "film base maps to the color print toe");
    expect(nearly_equal(
               output[1].red,
               static_cast<float>(negaflow::fixtures::color_negative_cases[1].expected)),
           "normal 0.60D mid density maps to linear mid gray");
    expect(nearly_equal(
               output[2].red,
               static_cast<float>(negaflow::fixtures::color_negative_cases[2].expected)),
           "dense color fixture matches the macOS double reference");
    expect(output[3].red > 0.0F && output[3].red < 0.001F,
           "above-base transmission mirrors continuously below the toe");
    expect(output[3].green == output[3].blue,
           "very low and negative transmission use the same lower guard");
    expect(output[1].alpha == 0.5F && output[3].alpha == 0.25F,
           "negative inversion preserves alpha exactly");
}

void test_negative_inversion_validation_and_bw_anchor() {
    constexpr float base = 0.72F;
    negaflow::core::Rgba32F source{base, base, base, 1.0F};
    negaflow::core::Rgba32F output{9.0F, 9.0F, 9.0F, 1.0F};
    negaflow::core::NegativeInversionParameters parameters{
        {base, base, base},
        {2.17F, 2.17F, 2.17F},
    };
    expect_status(
        negaflow::core::apply_negative_inversion(
            {&source, 1U, 1U, 1U, 1U},
            {&output, 1U, 1U, 1U, 1U},
            parameters,
            negaflow::core::black_and_white_negative_print_response()),
        negaflow::core::KernelStatus::ok,
        "B&W negative base fixture succeeds");
    expect(nearly_equal(output.red, 0.0005F, 2.0e-7F, 2.0e-6F),
           "film base maps to the B&W print toe");

    parameters.dmin[0] = 0.0F;
    expect_status(
        negaflow::core::apply_negative_inversion(
            {&source, 1U, 1U, 1U, 1U},
            {&output, 1U, 1U, 1U, 1U},
            parameters,
            negaflow::core::color_negative_print_response()),
        negaflow::core::KernelStatus::invalid_parameter,
        "zero Dmin is rejected");

    parameters.dmin[0] = base;
    parameters.dmax_normalized[1] = std::numeric_limits<float>::quiet_NaN();
    expect_status(
        negaflow::core::apply_negative_inversion(
            {&source, 1U, 1U, 1U, 1U},
            {&output, 1U, 1U, 1U, 1U},
            parameters,
            negaflow::core::color_negative_print_response()),
        negaflow::core::KernelStatus::non_finite_parameter,
        "non-finite density range is rejected");
}

}  // namespace

int main() {
    test_layout_validation();
    test_pointwise_extended_range_and_stride();
    test_parameter_and_sample_rejection();
    test_response_constant_bits();
    test_negative_inversion_color_fixture();
    test_negative_inversion_validation_and_bw_anchor();

    if (failures != 0) {
        std::cerr << failures << " scalar kernel assertion(s) failed\n";
        return 1;
    }

    std::cout << "All scalar kernel tests passed\n";
    return 0;
}
