#include "negaflow/pipeline/defect_region_stage.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <span>
#include <vector>

namespace {

using negaflow::core::Rgba32F;
using negaflow::imaging::WorkingImage;
using negaflow::pipeline::DefectRegionEdit;
using negaflow::pipeline::DefectRegionParameters;
using negaflow::pipeline::DefectRegionStageStatus;

int failures = 0;

void expect(const bool condition, const char* const name) {
    if (!condition) {
        std::cerr << "FAIL: " << name << '\n';
        ++failures;
    }
}

[[nodiscard]] bool near(const float left, const float right) noexcept {
    return std::abs(left - right) <= 1.0e-7F;
}

[[nodiscard]] float quantize_linear16(const float value) noexcept {
    return static_cast<float>(std::floor(
        static_cast<double>(std::clamp(value, 0.0F, 1.0F)) * 65'535.0 + 0.5) /
        65'535.0);
}

[[nodiscard]] WorkingImage make_image() {
    WorkingImage image{};
    image.width = 7U;
    image.height = 7U;
    image.stride_pixels = 7U;
    image.pixels.resize(49U);
    for (std::uint32_t y = 0U; y < 7U; ++y) {
        for (std::uint32_t x = 0U; x < 7U; ++x) {
            image.pixels[static_cast<std::size_t>(y) * 7U + x] = {
                0.10123F + static_cast<float>(x) * 0.03711F,
                0.21457F + static_cast<float>(y) * 0.02831F,
                0.32789F + static_cast<float>(x + y) * 0.01973F,
                1.0F,
            };
        }
    }
    return image;
}

void test_region_materializes_full_strength_rgba16_patch_before_blend() {
    const WorkingImage original = make_image();
    WorkingImage expected_roi{};
    expected_roi.width = 5U;
    expected_roi.height = 5U;
    expected_roi.stride_pixels = 5U;
    expected_roi.pixels.resize(25U);
    for (std::uint32_t y = 0U; y < 5U; ++y) {
        std::copy_n(
            original.pixels.begin() + static_cast<std::ptrdiff_t>((y + 1U) * 7U + 1U),
            5U,
            expected_roi.pixels.begin() + static_cast<std::ptrdiff_t>(y * 5U));
    }
    std::vector<std::uint8_t> mask(25U, 0U);
    mask[12U] = 255U;
    const auto repaired = negaflow::imaging::repair_defect_components(
        std::move(expected_roi), std::span<const std::uint8_t>{mask}, 5U, {});

    DefectRegionEdit edit{};
    edit.roi_x = 1U;
    edit.roi_y = 1U;
    edit.width = 5U;
    edit.height = 5U;
    edit.mask = mask;
    edit.mask_stride_bytes = 5U;
    edit.repair.strength = 0.5;
    DefectRegionParameters parameters{};
    parameters.edits.push_back(edit);
    const auto result = negaflow::pipeline::apply_defect_region_edits(
        original, parameters);

    const std::size_t center = 3U * 7U + 3U;
    const Rgba32F base = original.pixels[center];
    const Rgba32F full = repaired.image.pixels[12U];
    const float expected_red =
        base.red * 0.5F + quantize_linear16(full.red) * 0.5F;
    expect(result.status == DefectRegionStageStatus::ok,
           "region_rgba16_status_ok");
    expect(result.info.applied && result.info.applied_edit_count == 1U,
           "region_rgba16_reports_applied_layer");
    expect(near(result.image.pixels[center].red, expected_red),
           "region_quantizes_full_strength_patch_before_layer_blend");
    expect(!near(
               result.image.pixels[center].red,
               base.red * 0.5F + full.red * 0.5F),
           "region_does_not_forward_unquantized_float_patch");
    expect(result.image.pixels[2U * 7U + 2U].red ==
               original.pixels[2U * 7U + 2U].red,
           "region_keeps_pixels_outside_materialized_patch_exact");

    parameters.edits[0].repair.strength = 0.998;
    const auto below_boundary = negaflow::pipeline::apply_defect_region_edits(
        original, parameters);
    parameters.edits[0].repair.strength = 0.999;
    const auto at_boundary = negaflow::pipeline::apply_defect_region_edits(
        original, parameters);
    parameters.edits[0].repair.strength = 1.0;
    const auto full_strength = negaflow::pipeline::apply_defect_region_edits(
        original, parameters);
    const float full_red = quantize_linear16(full.red);
    const float below_red = base.red +
        (full_red - base.red) * static_cast<float>(0.998);
    expect(near(below_boundary.image.pixels[center].red, below_red),
           "region_strength_below_0999_blends");
    expect(near(at_boundary.image.pixels[center].red, full_red) &&
               near(full_strength.image.pixels[center].red, full_red),
           "region_strength_0999_and_one_apply_full_patch");
}

}  // namespace

int main() {
    test_region_materializes_full_strength_rgba16_patch_before_blend();
    if (failures != 0) {
        std::cerr << failures << " defect region stage test(s) failed\n";
        return EXIT_FAILURE;
    }
    std::cout << "defect region stage tests passed\n";
    return EXIT_SUCCESS;
}
