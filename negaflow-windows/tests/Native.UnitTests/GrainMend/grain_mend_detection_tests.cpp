#include "grain_mend_test_support.h"

#include "grain_mend_component_gates.h"
#include "grain_mend_detector.h"
#include "grain_mend_resample.h"
#include "grain_mend_speck_detector.h"
#include "grain_mend_stitch.h"
#include "grain_mend_tile_plan.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace grain_mend_tests {

void test_labeled_integer_gate_boundaries_match_macos() {
    constexpr double sensitivity = (3.1 - 0.7) / (6.0 - 0.7);
    negaflow::imaging::grain_mend_detail::Component area_boundary{};
    area_boundary.pixels.resize(490U);
    area_boundary.maximum_x = 27U;
    area_boundary.maximum_y = 17U;
    negaflow::imaging::grain_mend_detail::Component thickness_boundary{};
    thickness_boundary.pixels.resize(522U);
    thickness_boundary.maximum_x = 29U;
    thickness_boundary.maximum_y = 17U;
    expect(
        negaflow::imaging::grain_mend_detail::labeled_maximum_dust_area(
            150.0, sensitivity, false) == 489U &&
            negaflow::imaging::grain_mend_detail::labeled_maximum_thickness(
                sensitivity) == 17.0 &&
            !negaflow::imaging::grain_mend_detail::passes_dust_gate(
                area_boundary, 489U, 4.0, 3.0, 17.0) &&
            !negaflow::imaging::grain_mend_detail::passes_dust_gate(
                thickness_boundary, 489U, 4.0, 3.0, 17.0),
        "labeled dust area and thickness use macOS positive integer truncation");
}

void test_tile_local_structure_grid_precedes_speck_merge() {
    using negaflow::imaging::grain_mend_detail::DetectionImage;
    using negaflow::imaging::grain_mend_detail::remove_tile_local_structure_grid;

    DetectionImage tile{};
    tile.width = 256U;
    tile.height = 256U;
    tile.brightest_channel.assign(
        static_cast<std::size_t>(tile.width) * tile.height, 0.5F);
    std::vector<std::uint8_t> evidence(tile.brightest_channel.size(), 0U);
    constexpr std::array<std::uint32_t, 3U> centers{72U, 96U, 120U};
    for (const std::uint32_t center_y : centers) {
        for (const std::uint32_t center_x : centers) {
            for (std::uint32_t y = center_y - 7U; y <= center_y + 7U; ++y) {
                evidence[static_cast<std::size_t>(y) * tile.width + center_x] = 2U;
            }
        }
    }
    for (std::uint32_t y = 40U; y < 82U; ++y) {
        evidence[static_cast<std::size_t>(y) * tile.width + 220U] = 2U;
    }

    remove_tile_local_structure_grid(tile, evidence);

    const std::size_t speck = 96U * tile.width + 96U;
    std::vector<std::uint8_t> speck_mask(evidence.size(), 0U);
    std::vector<float> speck_confidence(evidence.size(), 0.0F);
    speck_mask[speck] = 1U;
    speck_mask[speck + 1U] = 1U;
    speck_confidence[speck] = 0.75F;
    speck_confidence[speck + 1U] = 0.75F;
    std::vector<std::uint8_t> occupancy(evidence.size(), 0U);
    std::size_t accepted = 0U;
    for (std::size_t index = 0U; index < evidence.size(); ++index) {
        if (evidence[index] != 0U) {
            occupancy[index] = 1U;
            ++accepted;
        }
    }
    std::vector<negaflow::imaging::grain_mend_detail::ClassifiedComponent>
        components{};
    negaflow::imaging::grain_mend_detail::merge_micro_specks_into(
        speck_mask,
        speck_confidence,
        tile.width,
        tile.height,
        &components,
        occupancy,
        accepted);

    expect(
        (evidence[speck] & 2U) == 0U &&
            (evidence[60U * tile.width + 220U] & 2U) != 0U &&
            occupancy[speck] != 0U && occupancy[speck + 1U] != 0U &&
            components.size() == 1U &&
            components.front().classification ==
                negaflow::imaging::grain_mend_detail::DefectClassification::
                    micro_speck,
        "tile-local grid rejection removes repeated structure before speck merge");
}

void test_detection_sensitivity_controls_candidate_thresholds() {
    const auto dust_clean = make_uniform_image(96U, 72U);
    auto faint_dust = dust_clean;
    constexpr std::size_t dust_index = 31U * 96U + 43U;
    faint_dust.pixels[dust_index] = {0.27F, 0.27F, 0.27F, 1.0F};

    negaflow::imaging::GrainMendParameters conservative_dust{1.0};
    conservative_dust.dust_sensitivity = 0.0;
    conservative_dust.scratch_sensitivity = 0.0;
    const auto dust_low = negaflow::imaging::apply_grain_mend(
        faint_dust,
        conservative_dust);
    negaflow::imaging::GrainMendParameters sensitive_dust = conservative_dust;
    sensitive_dust.dust_sensitivity = 1.0;
    const auto dust_high = negaflow::imaging::apply_grain_mend(
        std::move(faint_dust),
        sensitive_dust);
    expect(
        dust_low.status == negaflow::imaging::GrainMendStatus::ok &&
            !dust_low.info.applied &&
            dust_high.status == negaflow::imaging::GrainMendStatus::ok &&
            dust_high.info.applied &&
            pixel_error(dust_high.image.pixels[dust_index],
                        dust_clean.pixels[dust_index]) < 1.0e-5F,
        "dust sensitivity changes the normalized automatic detection threshold");

    const auto scratch_clean = make_uniform_image(128U, 96U);
    auto faint_scratch = scratch_clean;
    for (std::uint32_t x = 20U; x < 108U; ++x) {
        faint_scratch.pixels[48U * faint_scratch.width + x] =
            {0.225F, 0.225F, 0.225F, 1.0F};
    }
    negaflow::imaging::GrainMendParameters conservative_scratch{1.0};
    conservative_scratch.dust_sensitivity = 0.0;
    conservative_scratch.scratch_sensitivity = 0.0;
    const auto scratch_low = negaflow::imaging::apply_grain_mend(
        faint_scratch,
        conservative_scratch);
    negaflow::imaging::GrainMendParameters sensitive_scratch =
        conservative_scratch;
    sensitive_scratch.scratch_sensitivity = 1.0;
    const auto scratch_high = negaflow::imaging::apply_grain_mend(
        std::move(faint_scratch),
        sensitive_scratch);
    expect(
        scratch_low.status == negaflow::imaging::GrainMendStatus::ok &&
            !scratch_low.info.applied &&
            scratch_high.status == negaflow::imaging::GrainMendStatus::ok &&
            scratch_high.info.applied,
        "scratch sensitivity changes the normalized automatic detection threshold");
}

void test_whole_frame_structure_filter_preserves_grid_lines() {
    const auto clean = make_uniform_image(256U, 256U);
    auto source = clean;
    constexpr std::array<std::uint32_t, 3U> centers{72U, 96U, 120U};
    for (const std::uint32_t center_y : centers) {
        for (const std::uint32_t center_x : centers) {
            for (std::uint32_t y = center_y - 7U; y <= center_y + 7U; ++y) {
                source.pixels[static_cast<std::size_t>(y) * source.width + center_x] =
                    {0.28F, 0.28F, 0.28F, 1.0F};
            }
        }
    }
    for (std::uint32_t y = 40U; y < 82U; ++y) {
        source.pixels[static_cast<std::size_t>(y) * source.width + 220U] =
            {0.28F, 0.28F, 0.28F, 1.0F};
    }

    negaflow::imaging::GrainMendParameters unfiltered{1.0};
    const auto without_filter = negaflow::imaging::apply_grain_mend(
        source,
        unfiltered);
    negaflow::imaging::GrainMendParameters filtered = unfiltered;
    filtered.reject_structure_lines = true;
    const auto with_filter = negaflow::imaging::apply_grain_mend(
        std::move(source),
        filtered);
    const std::size_t grid_index = 96U * clean.width + 96U;
    const std::size_t isolated_index = 60U * clean.width + 220U;
    expect(
        without_filter.status == negaflow::imaging::GrainMendStatus::ok &&
            with_filter.status == negaflow::imaging::GrainMendStatus::ok &&
            pixel_error(without_filter.image.pixels[grid_index],
                        clean.pixels[grid_index]) < 1.0e-5F &&
            pixel_error(with_filter.image.pixels[grid_index],
                        clean.pixels[grid_index]) > 0.20F &&
            pixel_error(with_filter.image.pixels[isolated_index],
                        clean.pixels[isolated_index]) < 1.0e-5F,
        "whole-frame structure protection rejects a repeated grid but keeps an isolated scratch");
}

void test_stitch_keeps_highest_confidence_classification() {
    using negaflow::imaging::grain_mend_detail::ClassifiedComponent;
    using negaflow::imaging::grain_mend_detail::DefectClassification;
    using negaflow::imaging::grain_mend_detail::stitch_region_defect_tiles;

    // Two core pieces that 8-connect across a tile seam. macOS keeps the
    // higher-confidence class instead of re-running PCA on the union.
    ClassifiedComponent vertical{};
    vertical.pixels = {10U * 32U + 15U, 11U * 32U + 15U, 12U * 32U + 15U};
    vertical.minimum_x = 15U;
    vertical.maximum_x = 15U;
    vertical.minimum_y = 10U;
    vertical.maximum_y = 12U;
    vertical.is_scratch = true;
    vertical.classification = DefectClassification::scratch_vertical;
    vertical.confidence = 0.90;

    ClassifiedComponent horizontal{};
    horizontal.pixels = {12U * 32U + 16U, 12U * 32U + 17U};
    horizontal.minimum_x = 16U;
    horizontal.maximum_x = 17U;
    horizontal.minimum_y = 12U;
    horizontal.maximum_y = 12U;
    horizontal.is_scratch = true;
    horizontal.classification = DefectClassification::scratch_horizontal;
    horizontal.confidence = 0.30;

    ClassifiedComponent dust{};
    dust.pixels = {12U * 32U + 16U};
    dust.minimum_x = 16U;
    dust.maximum_x = 16U;
    dust.minimum_y = 12U;
    dust.maximum_y = 12U;
    dust.is_scratch = false;
    dust.classification = DefectClassification::dust;
    dust.confidence = 0.80;

    const auto stitched = stitch_region_defect_tiles(
        {vertical, horizontal, dust}, 32U, 24U);
    std::size_t scratches = 0U;
    std::size_t dusts = 0U;
    bool kept_vertical = false;
    for (const auto& component : stitched) {
        if (component.is_scratch) {
            ++scratches;
            kept_vertical = kept_vertical ||
                (component.classification ==
                     DefectClassification::scratch_vertical &&
                 component.confidence == 0.90 &&
                 component.pixels.size() == 5U);
        } else {
            ++dusts;
        }
    }
    expect(scratches == 1U && dusts == 1U && kept_vertical,
           "stitch unions same-kind 8-neighbors and keeps the higher-confidence class");
}

void test_whole_frame_tiles_stitch_a_boundary_scratch() {
    const auto clean = make_uniform_image(1'600U, 96U);
    auto source = clean;
    for (std::uint32_t x = 750U; x < 850U; ++x) {
        source.pixels[48U * source.width + x] =
            {0.34F, 0.34F, 0.34F, 1.0F};
    }

    negaflow::imaging::GrainMendParameters parameters{1.0};
    parameters.dust_sensitivity = 0.0;
    parameters.scratch_sensitivity = 1.0;
    parameters.reject_structure_lines = true;
    const auto repaired = negaflow::imaging::apply_grain_mend(
        std::move(source),
        parameters);
    const std::size_t left = 48U * clean.width + 799U;
    const std::size_t right = left + 1U;
    expect(
        repaired.status == negaflow::imaging::GrainMendStatus::ok &&
            repaired.info.applied &&
            repaired.info.detection_width == clean.width &&
            repaired.info.detection_height == clean.height &&
            pixel_error(repaired.image.pixels[left], clean.pixels[left]) < 1.0e-5F &&
            pixel_error(repaired.image.pixels[right], clean.pixels[right]) < 1.0e-5F,
        "whole-frame tiles stitch one scratch across a non-overlapping core boundary");
}

void test_labeled_detection_adds_curved_thin_scratch_evidence() {
    const auto clean = make_uniform_image(256U, 256U);
    auto source = clean;
    int previous_x = 128;
    for (std::uint32_t y = 32U; y < 224U; ++y) {
        const int current_x = 128 + static_cast<int>(std::lround(
            12.0 * std::sin(static_cast<double>(y) * 0.12)));
        const int first = std::min(previous_x, current_x);
        const int last = std::max(previous_x, current_x);
        for (int x = first; x <= last; ++x) {
            source.pixels[static_cast<std::size_t>(y) * source.width +
                          static_cast<std::size_t>(x)] =
                {0.30F, 0.30F, 0.30F, 1.0F};
        }
        previous_x = current_x;
    }

    const auto detection =
        negaflow::imaging::grain_mend_detail::make_detection_image(source);
    const auto simple = negaflow::imaging::grain_mend_detail::find_candidates(
        detection, 0.0, 1.0, 0.75, false);
    const auto labeled = negaflow::imaging::grain_mend_detail::find_candidates(
        detection, 0.0, 1.0, 0.75, true);
    const auto scratch_count = [](const std::vector<std::uint8_t>& map,
                                  const std::uint8_t level) {
        return static_cast<std::size_t>(std::count_if(
            map.begin(), map.end(), [&](const std::uint8_t value) {
                return (value & level) != 0U;
            }));
    };
    const std::size_t simple_weak = scratch_count(simple.weak, 2U);
    const std::size_t labeled_weak = scratch_count(labeled.weak, 2U);
    const std::size_t labeled_strong = scratch_count(labeled.strong, 2U);
    expect(
        labeled_weak > simple_weak && labeled_strong != 0U,
        "labeled detection adds strong and weak evidence for a curved thin scratch");
}

}  // namespace grain_mend_tests
