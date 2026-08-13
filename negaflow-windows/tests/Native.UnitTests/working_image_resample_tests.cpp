#include "negaflow/imaging/working_image_resample.h"

#include <cmath>
#include <cstring>
#include <iostream>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] negaflow::imaging::WorkingImage opaque_gradient() {
    negaflow::imaging::WorkingImage image{};
    image.width = 8U;
    image.height = 4U;
    image.stride_pixels = image.width;
    image.pixels.resize(static_cast<std::size_t>(image.width) * image.height);
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            image.pixels[static_cast<std::size_t>(y) * image.width + x] = {
                static_cast<float>(x) / 7.0F,
                static_cast<float>(y) / 3.0F,
                static_cast<float>(x + y) / 10.0F,
                1.0F,
            };
        }
    }
    return image;
}

void test_lanczos_downscale_preserves_working_contract() {
    const auto source = opaque_gradient();
    const auto result = negaflow::imaging::resample_working_image_lanczos3(source, 4U, 2U);
    bool opaque_and_finite = result.status == negaflow::imaging::WorkingImageResampleStatus::ok;
    for (const auto pixel : result.image.pixels) {
        opaque_and_finite = opaque_and_finite && pixel.alpha == 1.0F &&
            std::isfinite(pixel.red) && std::isfinite(pixel.green) &&
            std::isfinite(pixel.blue);
    }
    expect(
        result.image.width == 4U && result.image.height == 2U &&
            result.image.stride_pixels == 4U && result.image.pixels.size() == 8U,
        "downscale returns the requested output geometry");
    expect(opaque_and_finite, "downscale keeps the linear working image opaque and finite");
    expect(
        source.pixels.front().red == 0.0F && source.pixels.back().green == 1.0F,
        "downscale does not mutate the source image");
}

void test_identity_and_invalid_geometry() {
    const auto source = opaque_gradient();
    const auto identity = negaflow::imaging::resample_working_image_lanczos3(source, 8U, 4U);
    expect(
        identity.status == negaflow::imaging::WorkingImageResampleStatus::ok &&
            identity.image.pixels.size() == source.pixels.size() &&
            std::memcmp(
                identity.image.pixels.data(), source.pixels.data(),
                source.pixels.size() * sizeof(source.pixels.front())) == 0,
        "identity resize preserves every source pixel");

    const auto upscale = negaflow::imaging::resample_working_image_lanczos3(source, 9U, 4U);
    expect(
        upscale.status == negaflow::imaging::WorkingImageResampleStatus::invalid_dimensions,
        "upscale is rejected");
}

}  // namespace

int main() {
    test_lanczos_downscale_preserves_working_contract();
    test_identity_and_invalid_geometry();
    return failures == 0 ? 0 : 1;
}
