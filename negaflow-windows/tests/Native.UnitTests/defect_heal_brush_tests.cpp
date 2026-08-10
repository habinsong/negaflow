#include "negaflow/imaging/defect_heal_brush.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <span>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        ++failures;
        std::cerr << "FAIL: " << message << '\n';
    }
}

[[nodiscard]] negaflow::imaging::WorkingImage make_textured_gradient(
    const std::uint32_t width = 256U,
    const std::uint32_t height = 192U) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float texture = static_cast<float>(
                static_cast<int>((x * 17U + y * 29U) % 13U) - 6) * 0.001F;
            image.pixels[static_cast<std::size_t>(y) * width + x] = {
                0.18F + static_cast<float>(x) * 0.0015F + texture,
                0.22F + static_cast<float>(y) * 0.0012F - texture,
                0.16F + static_cast<float>(x + y) * 0.0008F + texture,
                0.35F + static_cast<float>((x + y) % 5U) * 0.1F,
            };
        }
    }
    return image;
}

[[nodiscard]] bool same_pixels(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept {
    return left.size() == right.size() &&
        std::memcmp(
            left.data(),
            right.data(),
            left.size() * sizeof(negaflow::core::Rgba32F)) == 0;
}

void test_center_stroke_heals_locally_and_preserves_alpha() {
    auto image = make_textured_gradient();
    const auto original = image.pixels;
    const std::vector<negaflow::imaging::DefectBrushPoint> points{
        {0.42, 0.50},
        {0.58, 0.50},
    };
    const negaflow::imaging::DefectBrushStroke stroke{points, 0.025};
    const auto result = negaflow::imaging::apply_defect_heal_brush(
        std::move(image),
        {std::span<const negaflow::imaging::DefectBrushStroke>(&stroke, 1U),
         1.0});

    const std::size_t center = 96U * 256U + 128U;
    expect(
        result.status == negaflow::imaging::DefectHealBrushStatus::ok &&
            result.info.applied && result.info.applied_chunk_count == 1U &&
            result.info.healed_component_count == 1U &&
            result.info.fallback_chunk_count == 0U,
        "a center brush stroke uses the displaced heal path");
    expect(
        result.image.pixels[center].red != original[center].red &&
            result.image.pixels[center].alpha == original[center].alpha,
        "the brush changes RGB while preserving source alpha");
    expect(
        std::memcmp(
            result.image.pixels.data(),
            original.data(),
            8U * sizeof(negaflow::core::Rgba32F)) == 0,
        "pixels outside the repair halo remain byte exact");
}

void test_layer_strength_mixes_one_full_strength_result() {
    auto full_input = make_textured_gradient();
    auto half_input = full_input;
    const auto original = full_input.pixels;
    const std::vector<negaflow::imaging::DefectBrushPoint> points{{0.5, 0.5}};
    const negaflow::imaging::DefectBrushStroke stroke{points, 0.03};
    const auto full = negaflow::imaging::apply_defect_heal_brush(
        std::move(full_input),
        {std::span<const negaflow::imaging::DefectBrushStroke>(&stroke, 1U),
         1.0});
    const auto half = negaflow::imaging::apply_defect_heal_brush(
        std::move(half_input),
        {std::span<const negaflow::imaging::DefectBrushStroke>(&stroke, 1U),
         0.5});
    const std::size_t center = 96U * 256U + 128U;
    const float expected =
        original[center].red * 0.5F + full.image.pixels[center].red * 0.5F;
    expect(
        full.status == negaflow::imaging::DefectHealBrushStatus::ok &&
            half.status == negaflow::imaging::DefectHealBrushStatus::ok &&
            std::abs(half.image.pixels[center].red - expected) < 2.0e-5F,
        "brush layer strength mixes the cached full-strength repair once");
}

void test_identity_and_invalid_input_fail_closed() {
    auto image = make_textured_gradient();
    const auto original = image.pixels;
    const auto identity = negaflow::imaging::apply_defect_heal_brush(
        image, {{}, 1.0});
    expect(
        identity.status == negaflow::imaging::DefectHealBrushStatus::ok &&
            !identity.info.applied && same_pixels(identity.image.pixels, original),
        "an empty brush recipe is exact identity");

    const std::vector<negaflow::imaging::DefectBrushPoint> points{{
        std::numeric_limits<double>::quiet_NaN(),
        0.5,
    }};
    const negaflow::imaging::DefectBrushStroke invalid{points, 0.02};
    const auto failed = negaflow::imaging::apply_defect_heal_brush(
        std::move(image),
        {std::span<const negaflow::imaging::DefectBrushStroke>(&invalid, 1U),
         1.0});
    expect(
        failed.status ==
                negaflow::imaging::DefectHealBrushStatus::invalid_argument &&
            failed.image.pixels.empty(),
        "non-finite brush geometry fails closed");

    auto outside_image = make_textured_gradient();
    const std::vector<negaflow::imaging::DefectBrushPoint> outside_points{{
        2.0,
        0.5,
    }};
    const negaflow::imaging::DefectBrushStroke outside{
        outside_points,
        0.02,
    };
    const auto outside_result = negaflow::imaging::apply_defect_heal_brush(
        std::move(outside_image),
        {std::span<const negaflow::imaging::DefectBrushStroke>(&outside, 1U),
         1.0});
    expect(
        outside_result.status ==
                negaflow::imaging::DefectHealBrushStatus::invalid_argument &&
            outside_result.image.pixels.empty(),
        "out-of-range normalized brush geometry fails closed");
}

}  // namespace

int main() {
    test_center_stroke_heals_locally_and_preserves_alpha();
    test_layer_strength_mixes_one_full_strength_result();
    test_identity_and_invalid_input_fail_closed();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"defect_heal_brush\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
