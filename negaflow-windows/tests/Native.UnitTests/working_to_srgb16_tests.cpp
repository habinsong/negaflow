#include "negaflow/output/working_to_srgb16.h"

#include "negaflow/color/srgb_transfer.h"
#include "negaflow/imaging/display_gamut_map.h"

#include <algorithm>
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

negaflow::imaging::WorkingImage make_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 2U;
    image.height = 1U;
    image.stride_pixels = 3U;
    image.pixels = {
        {0.0F, 0.0031308F, 0.21404114F, 1.0F},
        {1.0F, -0.1F, 1.1F, 1.0F},
        {0.75F, 0.75F, 0.75F, 1.0F},
    };
    return image;
}

std::uint16_t quantize_encoded(const float linear) {
    const float encoded = negaflow::color::linear_to_srgb_encoded(std::clamp(linear, 0.0F, 1.0F));
    return static_cast<std::uint16_t>(std::floor(encoded * 65'535.0F + 0.5F));
}

std::array<std::uint16_t, 3U> expected_folded(const negaflow::core::Rgba32F pixel) {
    const negaflow::core::Rgba32F folded = negaflow::imaging::tone_safe_unit_rgb(pixel);
    return {quantize_encoded(folded.red), quantize_encoded(folded.green), quantize_encoded(folded.blue)};
}

void test_quantization() {
    const auto result = negaflow::output::convert_working_to_srgb16(make_image());
    expect(
        result.status == negaflow::output::WorkingToSrgb16Status::ok,
        "valid working image converts");
    expect(
        result.image.width == 2U && result.image.height == 1U &&
            result.image.stride_bytes == 12U,
        "output dimensions and packed stride are exact");
    expect(result.image.samples.size() == 6U, "padding pixels are not exported");
    if (result.image.samples.size() == 6U) {
        expect(result.image.samples[0] == 0U, "black quantizes to zero");
        expect(result.image.samples[1] == 2'651U, "sRGB breakpoint quantizes exactly");
        expect(result.image.samples[2] == 32'768U, "linear midpoint maps to encoded half");
        // 범위 밖 화소는 프리뷰와 같은 hue-safe 접기를 거칩니다(macOS
        // `DisplayGamutMap.apply(to:encodedIn:)`). 채널마다 자르면 (65535, 0, 65535) 로
        // 색상이 틀어집니다.
        const std::array<std::uint16_t, 3U> folded = expected_folded({1.0F, -0.1F, 1.1F, 1.0F});
        expect(result.image.samples[3] == folded[0], "extended red folds like the preview");
        expect(result.image.samples[4] == 0U, "the negative channel lands on zero after folding");
        expect(result.image.samples[5] == folded[2], "extended blue folds like the preview");
        expect(
            result.image.samples[3] < 65'535U && result.image.samples[5] < 65'535U,
            "folding keeps the hue instead of clipping each channel");
    }
    expect(result.info.encoded_pixel_bytes == 12U, "encoded byte count is exact");
    expect(result.info.clipped_color_components == 2U, "clipped component count is exact");
}

void test_linear_quantization() {
    negaflow::output::WorkingToSrgb16Limits limits{};
    limits.encode_transfer = false;
    const auto result = negaflow::output::convert_working_to_srgb16(make_image(), limits);
    expect(
        result.status == negaflow::output::WorkingToSrgb16Status::ok,
        "valid working image converts without an output transfer");
    expect(
        result.image.samples.size() == 6U &&
            result.image.samples[0] == 0U && result.image.samples[1] == 205U &&
            result.image.samples[2] == 14'027U && result.image.samples[3] == 65'535U &&
            result.image.samples[4] == 0U && result.image.samples[5] == 65'535U,
        "linear RGB16 quantization preserves bounded working values exactly");
}

void test_rejections() {
    negaflow::imaging::WorkingImage image = make_image();
    image.width = 0U;
    expect(
        negaflow::output::convert_working_to_srgb16(image).status ==
            negaflow::output::WorkingToSrgb16Status::invalid_dimensions,
        "zero dimensions are rejected");

    image = make_image();
    image.stride_pixels = 1U;
    expect(
        negaflow::output::convert_working_to_srgb16(image).status ==
            negaflow::output::WorkingToSrgb16Status::invalid_stride,
        "short stride is rejected");

    image = make_image();
    image.pixels.pop_back();
    expect(
        negaflow::output::convert_working_to_srgb16(image).status ==
            negaflow::output::WorkingToSrgb16Status::buffer_size_mismatch,
        "buffer mismatch is rejected");

    image = make_image();
    image.pixels[0].red = std::numeric_limits<float>::quiet_NaN();
    expect(
        negaflow::output::convert_working_to_srgb16(image).status ==
            negaflow::output::WorkingToSrgb16Status::non_finite_pixel,
        "non-finite pixels are rejected");

    image = make_image();
    image.pixels[0].alpha = 0.5F;
    expect(
        negaflow::output::convert_working_to_srgb16(image).status ==
            negaflow::output::WorkingToSrgb16Status::ok,
        "RGB export deliberately omits non-opaque alpha when preservation is off");

    negaflow::output::WorkingToSrgb16Limits alpha_limits{};
    alpha_limits.preserve_alpha = true;
    const auto alpha_result = negaflow::output::convert_working_to_srgb16(image, alpha_limits);
    expect(
        alpha_result.status == negaflow::output::WorkingToSrgb16Status::ok &&
            alpha_result.image.channels == 4U && alpha_result.image.stride_bytes == 16U &&
            alpha_result.image.samples.size() == 8U && alpha_result.image.samples[3] == 32'768U,
        "preserved alpha is straight, fourth-channel and linearly quantized");

    image = make_image();
    negaflow::output::WorkingToSrgb16Limits limits{};
    limits.max_encoded_pixel_bytes = 11U;
    expect(
        negaflow::output::convert_working_to_srgb16(image, limits).status ==
            negaflow::output::WorkingToSrgb16Status::memory_limit_exceeded,
        "encoded pixel budget is enforced before allocation");
}

void test_inspection_and_bounded_rows() {
    const auto inspection = negaflow::output::inspect_working_to_srgb16(make_image());
    expect(
        inspection.status == negaflow::output::WorkingToSrgb16Status::ok &&
            inspection.image.width == 2U && inspection.image.height == 1U &&
            inspection.image.stride_bytes == 12U && inspection.image.samples.empty(),
        "inspection reports the packed layout without materializing samples");
    expect(
        inspection.info.encoded_pixel_bytes == 12U &&
            inspection.info.clipped_color_components == 2U,
        "inspection preserves conversion byte and clipping information");

    std::array<std::uint16_t, 6U> samples{};
    std::uint64_t clipped_components = 0U;
    const auto status = negaflow::output::convert_working_to_srgb16_rows(
        make_image(),
        0U,
        1U,
        samples.data(),
        samples.size(),
        clipped_components);
    const std::array<std::uint16_t, 3U> folded = expected_folded({1.0F, -0.1F, 1.1F, 1.0F});
    expect(
        status == negaflow::output::WorkingToSrgb16Status::ok &&
            samples[0] == 0U && samples[1] == 2'651U && samples[2] == 32'768U &&
            samples[3] == folded[0] && samples[4] == 0U && samples[5] == folded[2] &&
            clipped_components == 2U,
        "bounded row conversion matches the full-image quantization");
}

}  // namespace

int main() {
    test_quantization();
    test_linear_quantization();
    test_rejections();
    test_inspection_and_bounded_rows();
    if (failures != 0) {
        std::cerr << failures << " working-to-sRGB16 test(s) failed\n";
        return 1;
    }
    std::cout << "working-to-sRGB16 tests passed\n";
    return 0;
}
