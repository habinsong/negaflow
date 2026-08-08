#include "negaflow/output/working_to_srgb16.h"

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
        expect(result.image.samples[3] == 65'535U, "white quantizes to maximum");
        expect(result.image.samples[4] == 0U, "negative output clips at final boundary");
        expect(result.image.samples[5] == 65'535U, "extended output clips at final boundary");
    }
    expect(result.info.encoded_pixel_bytes == 12U, "encoded byte count is exact");
    expect(result.info.clipped_color_components == 2U, "clipped component count is exact");
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
            negaflow::output::WorkingToSrgb16Status::non_opaque_alpha,
        "alpha is not silently discarded");

    image = make_image();
    negaflow::output::WorkingToSrgb16Limits limits{};
    limits.max_encoded_pixel_bytes = 11U;
    expect(
        negaflow::output::convert_working_to_srgb16(image, limits).status ==
            negaflow::output::WorkingToSrgb16Status::memory_limit_exceeded,
        "encoded pixel budget is enforced before allocation");
}

}  // namespace

int main() {
    test_quantization();
    test_rejections();
    if (failures != 0) {
        std::cerr << failures << " working-to-sRGB16 test(s) failed\n";
        return 1;
    }
    std::cout << "working-to-sRGB16 tests passed\n";
    return 0;
}
