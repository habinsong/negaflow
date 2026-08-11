#include "negaflow/pipeline/defect_infrared_stage.h"

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
using negaflow::pipeline::DefectInfraredEdit;
using negaflow::pipeline::DefectInfraredItem;
using negaflow::pipeline::DefectInfraredStageStatus;

int failures = 0;

void expect(const bool condition, const char* const name) {
    if (!condition) {
        std::cerr << "FAIL: " << name << '\n';
        ++failures;
    }
}

[[nodiscard]] bool near(const float left, const float right) {
    return std::abs(left - right) <= 1.0e-6F;
}

[[nodiscard]] WorkingImage make_image(
    const std::uint32_t width,
    const std::uint32_t height) {
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            image.pixels[static_cast<std::size_t>(y) * width + x] = {
                0.12F + static_cast<float>(x) * 0.025F,
                0.18F + static_cast<float>(y) * 0.02F,
                0.24F + static_cast<float>(x + y) * 0.015F,
                0.73F,
            };
        }
    }
    return image;
}

void write_r16(
    std::vector<std::uint8_t>& bytes,
    const std::size_t pixel,
    const std::uint16_t value) {
    bytes[pixel * 2U] = static_cast<std::uint8_t>(value & 0xffU);
    bytes[pixel * 2U + 1U] = static_cast<std::uint8_t>(value >> 8U);
}

void test_partial_attenuation_without_core_does_not_inpaint() {
    WorkingImage image = make_image(5U, 5U);
    const WorkingImage original = image;
    std::vector<std::uint8_t> core(9U, 0U);
    std::vector<std::uint8_t> attenuation(18U, 0U);
    write_r16(attenuation, 4U, 32768U);
    DefectInfraredEdit edit{};
    edit.roi_x = 1U;
    edit.roi_y = 1U;
    edit.width = 3U;
    edit.height = 3U;
    edit.core_mask = core;
    edit.core_mask_stride_bytes = 3U;
    edit.attenuation_r16 = attenuation;
    edit.attenuation_stride_bytes = 6U;

    const auto result = negaflow::pipeline::apply_defect_infrared_edit(
        std::move(image), edit);
    const std::size_t center = 2U * 5U + 2U;
    const double transmittance =
        std::max(1.0 - 32768.0 / 65535.0, 0.5);
    expect(result.status == DefectInfraredStageStatus::ok,
           "partial_status_ok");
    expect(result.info.attenuated_pixels == 1U,
           "partial_counts_attenuated_pixel");
    expect(result.info.repaired_pixels == 0U,
           "partial_zero_core_skips_repair");
    expect(near(
               result.image.pixels[center].red,
               static_cast<float>(original.pixels[center].red / transmittance)),
           "partial_divides_source_red_by_transmittance");
    expect(result.image.pixels[0U].red == original.pixels[0U].red,
           "partial_leaves_outside_pixel_exact");
    expect(result.image.pixels[center].alpha == original.pixels[center].alpha,
           "partial_preserves_alpha");
}

void test_core_repair_reads_attenuation_corrected_context() {
    WorkingImage image = make_image(7U, 7U);
    const WorkingImage original = image;
    std::vector<std::uint8_t> core(25U, 0U);
    core[12U] = 255U;
    std::vector<std::uint8_t> attenuation(50U, 0U);
    for (std::size_t pixel = 0U; pixel < 25U; ++pixel) {
        write_r16(attenuation, pixel, 32768U);
    }

    DefectInfraredEdit edit{};
    edit.roi_x = 1U;
    edit.roi_y = 1U;
    edit.width = 5U;
    edit.height = 5U;
    edit.core_mask = core;
    edit.core_mask_stride_bytes = 5U;
    edit.attenuation_r16 = attenuation;
    edit.attenuation_stride_bytes = 10U;
    const auto result = negaflow::pipeline::apply_defect_infrared_edit(
        std::move(image), edit);

    WorkingImage expected_roi{};
    expected_roi.width = 5U;
    expected_roi.height = 5U;
    expected_roi.stride_pixels = 5U;
    expected_roi.pixels.resize(25U);
    const double transmittance =
        std::max(1.0 - 32768.0 / 65535.0, 0.5);
    for (std::uint32_t y = 0U; y < 5U; ++y) {
        for (std::uint32_t x = 0U; x < 5U; ++x) {
            Rgba32F pixel = original.pixels[
                static_cast<std::size_t>(y + 1U) * 7U + x + 1U];
            pixel.red = static_cast<float>(
                std::clamp(
                    static_cast<double>(pixel.red) / transmittance, 0.0, 1.0));
            pixel.green = static_cast<float>(
                std::clamp(
                    static_cast<double>(pixel.green) / transmittance, 0.0, 1.0));
            pixel.blue = static_cast<float>(
                std::clamp(
                    static_cast<double>(pixel.blue) / transmittance, 0.0, 1.0));
            expected_roi.pixels[static_cast<std::size_t>(y) * 5U + x] = pixel;
        }
    }
    const auto expected = negaflow::imaging::repair_defect_components(
        std::move(expected_roi),
        std::span<const std::uint8_t>(core),
        5U,
        {});
    const std::size_t output_center = 3U * 7U + 3U;
    expect(result.status == DefectInfraredStageStatus::ok,
           "core_status_ok");
    expect(result.info.repaired_pixels != 0U,
           "core_repair_runs_after_attenuation");
    expect(expected.status ==
               negaflow::imaging::DefectComponentRepairStatus::ok &&
           near(result.image.pixels[output_center].red,
                expected.image.pixels[12U].red) &&
           near(result.image.pixels[output_center].green,
                expected.image.pixels[12U].green) &&
           near(result.image.pixels[output_center].blue,
                expected.image.pixels[12U].blue),
           "core_matches_attenuation_then_component_repair_order");
}

void test_legacy_mask_only_matches_component_repair() {
    WorkingImage image = make_image(7U, 7U);
    const WorkingImage original = image;
    std::vector<std::uint8_t> core(25U, 0U);
    core[12U] = 255U;
    DefectInfraredEdit edit{};
    edit.roi_x = 1U;
    edit.roi_y = 1U;
    edit.width = 5U;
    edit.height = 5U;
    edit.core_mask = core;
    edit.core_mask_stride_bytes = 5U;
    const auto result = negaflow::pipeline::apply_defect_infrared_edit(
        std::move(image), edit);

    WorkingImage expected_roi{};
    expected_roi.width = 5U;
    expected_roi.height = 5U;
    expected_roi.stride_pixels = 5U;
    expected_roi.pixels.resize(25U);
    for (std::uint32_t y = 0U; y < 5U; ++y) {
        std::copy_n(
            original.pixels.begin() + static_cast<std::ptrdiff_t>(
                static_cast<std::size_t>(y + 1U) * 7U + 1U),
            5U,
            expected_roi.pixels.begin() + static_cast<std::ptrdiff_t>(
                static_cast<std::size_t>(y) * 5U));
    }
    const auto expected = negaflow::imaging::repair_defect_components(
        std::move(expected_roi),
        std::span<const std::uint8_t>(core),
        5U,
        {});
    expect(result.status == DefectInfraredStageStatus::ok,
           "legacy_status_ok");
    expect(near(result.image.pixels[24U].red, expected.image.pixels[12U].red),
           "legacy_matches_component_repair_fallback");
}

void test_item_clusters_share_base_and_publish_only_correction_bounds() {
    WorkingImage image = make_image(8U, 5U);
    const WorkingImage original = image;
    std::vector<std::uint8_t> first_core(15U, 0U);
    std::vector<std::uint8_t> first_attenuation(30U, 0U);
    write_r16(first_attenuation, 6U, 32768U);
    write_r16(first_attenuation, 8U, 32768U);
    write_r16(first_attenuation, 9U, 32768U);
    DefectInfraredEdit first{};
    first.roi_x = 1U;
    first.roi_y = 1U;
    first.width = 5U;
    first.height = 3U;
    first.core_mask = first_core;
    first.core_mask_stride_bytes = 5U;
    first.attenuation_r16 = first_attenuation;
    first.attenuation_stride_bytes = 10U;

    std::vector<std::uint8_t> second_core(21U, 0U);
    std::vector<std::uint8_t> second_attenuation(42U, 0U);
    write_r16(second_attenuation, 11U, 32768U);
    write_r16(second_attenuation, 13U, 32768U);
    DefectInfraredEdit second{};
    second.roi_x = 0U;
    second.roi_y = 1U;
    second.width = 7U;
    second.height = 3U;
    second.core_mask = second_core;
    second.core_mask_stride_bytes = 7U;
    second.attenuation_r16 = second_attenuation;
    second.attenuation_stride_bytes = 14U;

    DefectInfraredItem item{};
    item.clusters = {first, second};
    const auto result = negaflow::pipeline::apply_defect_infrared_item(
        std::move(image), item);
    const double transmittance =
        std::max(1.0 - 32768.0 / 65535.0, 0.5);
    const std::size_t first_only = 2U * 8U + 2U;
    const std::size_t overlap = 2U * 8U + 4U;
    const std::size_t second_only = 2U * 8U + 6U;
    const std::size_t later_rectangle_hole = 2U * 8U + 5U;
    expect(result.status == DefectInfraredStageStatus::ok,
           "item_overlap_status_ok");
    expect(result.info.attenuated_pixels == 5U,
           "item_overlap_counts_cluster_evidence");
    expect(near(
               result.image.pixels[first_only].red,
               static_cast<float>(
                   original.pixels[first_only].red / transmittance)),
           "wider_second_roi_padding_does_not_overwrite_first_patch");
    expect(near(
               result.image.pixels[overlap].red,
               static_cast<float>(
                   original.pixels[overlap].red / transmittance)),
           "overlapping_cluster_attenuation_uses_item_base_once");
    expect(near(
               result.image.pixels[second_only].red,
               static_cast<float>(
                   original.pixels[second_only].red / transmittance)),
           "second_cluster_correction_is_published");
    expect(result.image.pixels[later_rectangle_hole].red ==
               original.pixels[later_rectangle_hole].red,
           "later_exact_rectangle_hole_overwrites_earlier_patch_with_base");
}

void test_malformed_payload_fails_closed() {
    WorkingImage image = make_image(5U, 5U);
    std::vector<std::uint8_t> core(9U, 0U);
    std::vector<std::uint8_t> attenuation(17U, 0U);
    DefectInfraredEdit edit{};
    edit.roi_x = 1U;
    edit.roi_y = 1U;
    edit.width = 3U;
    edit.height = 3U;
    edit.core_mask = core;
    edit.core_mask_stride_bytes = 3U;
    edit.attenuation_r16 = attenuation;
    edit.attenuation_stride_bytes = 6U;
    const auto result = negaflow::pipeline::apply_defect_infrared_edit(
        std::move(image), edit);
    expect(result.status == DefectInfraredStageStatus::invalid_argument,
           "malformed_r16_rejected");
    expect(result.image.pixels.empty(),
           "malformed_r16_discards_partial_output");

    attenuation.resize(19U, 0U);
    edit.attenuation_r16 = attenuation;
    const auto oversized = negaflow::pipeline::apply_defect_infrared_edit(
        make_image(5U, 5U), edit);
    expect(oversized.status == DefectInfraredStageStatus::invalid_argument &&
               oversized.image.pixels.empty(),
           "oversized_r16_is_rejected_and_discarded");
}

}  // namespace

int main() {
    test_partial_attenuation_without_core_does_not_inpaint();
    test_core_repair_reads_attenuation_corrected_context();
    test_legacy_mask_only_matches_component_repair();
    test_item_clusters_share_base_and_publish_only_correction_bounds();
    test_malformed_payload_fails_closed();
    if (failures != 0) {
        std::cerr << failures << " infrared stage test(s) failed\n";
        return EXIT_FAILURE;
    }
    std::cout << "infrared stage tests passed\n";
    return EXIT_SUCCESS;
}
