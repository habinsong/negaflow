#include "working_image_report.h"

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

[[nodiscard]] negaflow::imaging::WorkingImage make_padded_image(
    const negaflow::core::Rgba32F padding) {
    negaflow::imaging::WorkingImage image{};
    image.width = 2U;
    image.height = 2U;
    image.stride_pixels = 3U;
    image.pixels = {
        {0.0F, 0.25F, 0.5F, 1.0F},
        {-1.0F, 2.0F, 3.5F, 0.75F},
        padding,
        {0.125F, -0.5F, 1.5F, 1.0F},
        {10.0F, 20.0F, 30.0F, 0.0F},
        padding,
    };
    return image;
}

void test_versioned_active_pixel_statistics() {
    const auto first = negaflow::cli::compute_working_image_statistics(
        make_padded_image({91.0F, 92.0F, 93.0F, 94.0F}));
    const auto second = negaflow::cli::compute_working_image_statistics(
        make_padded_image({-91.0F, -92.0F, -93.0F, -94.0F}));

    expect(
        negaflow::cli::working_pixel_fingerprint_algorithm_version ==
            "fnv1a64-rgba32f-bits-le-v1",
        "the diagnostic pixel fingerprint has a stable algorithm version");
    expect(first.valid && second.valid, "valid padded images produce statistics");
    expect(
        first.minimum[0] == -1.0F && first.minimum[1] == -0.5F &&
            first.minimum[2] == 0.5F && first.minimum[3] == 0.0F,
        "channel minima include active pixels only");
    expect(
        first.maximum[0] == 10.0F && first.maximum[1] == 20.0F &&
            first.maximum[2] == 30.0F && first.maximum[3] == 1.0F,
        "channel maxima include active pixels only");
    expect(
        first.fingerprint_fnv1a64 == 0x0380197c28c8059bULL,
        "the little-endian RGBA32F fingerprint matches the v1 fixture");
    expect(
        first.fingerprint_fnv1a64 == second.fingerprint_fnv1a64 &&
            first.minimum == second.minimum && first.maximum == second.maximum,
        "stride padding does not affect diagnostic statistics");

    auto malformed = make_padded_image({0.0F, 0.0F, 0.0F, 0.0F});
    malformed.stride_pixels = 1U;
    expect(
        !negaflow::cli::compute_working_image_statistics(malformed).valid,
        "a stride smaller than width is rejected without reading pixels");
    malformed.stride_pixels = 3U;
    malformed.pixels.resize(4U);
    expect(
        !negaflow::cli::compute_working_image_statistics(malformed).valid,
        "an undersized pixel buffer is rejected without reading past its end");
    malformed = make_padded_image({0.0F, 0.0F, 0.0F, 0.0F});
    malformed.pixels[0].red = std::numeric_limits<float>::quiet_NaN();
    expect(
        !negaflow::cli::compute_working_image_statistics(malformed).valid,
        "a non-finite active pixel is rejected without publishing partial statistics");
}

}  // namespace

int main() {
    test_versioned_active_pixel_statistics();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"working_image_report\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
