#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/grain_mend.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace grain_mend_tests {

// 실패 개수는 suite 전체가 공유합니다. 각 번역 단위가 자기 것을 세면 main 이 합계를 낼 수
// 없습니다.
extern int failures;

void expect(bool condition, const char* message);

[[nodiscard]] negaflow::imaging::WorkingImage make_clean_image(
    std::uint32_t width = 96U,
    std::uint32_t height = 72U);

[[nodiscard]] negaflow::imaging::WorkingImage make_uniform_image(
    std::uint32_t width,
    std::uint32_t height,
    float value = 0.20F);

[[nodiscard]] bool same_pixels(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept;

// 채널마다 다른 잡음을 얹습니다. 휘도만 보면 지워지는 색 먼지를 만들 때 씁니다.
void add_chromatic_grain(
    negaflow::imaging::WorkingImage& image,
    std::uint32_t seed,
    std::uint32_t probability_per_thousand,
    float amplitude);

void add_dark_micro_speck(
    negaflow::imaging::WorkingImage& image,
    std::uint32_t x,
    std::uint32_t y,
    std::uint32_t size,
    float drop);

[[nodiscard]] float pixel_error(
    negaflow::core::Rgba32F actual,
    negaflow::core::Rgba32F expected) noexcept;

// 옅은 스크래치를 그리고 그 화소 자리를 냅니다. 검출이 실제로 그 자리를 잡았는지 보려면
// 그린 자리를 알아야 합니다.
[[nodiscard]] std::vector<std::size_t> draw_faint_scratch(
    negaflow::imaging::WorkingImage& image,
    double angle_degrees);

// 수리 경로: 먼지·가는 스크래치·대각·색 먼지·축 밖 스크래치.
void test_dust_and_thin_scratch_are_repaired();
void test_grain_only_field_is_not_wiped();
void test_diagonal_scratch_is_repaired();
void test_chromatic_dust_is_detected_without_luminance_dilution();
void test_off_axis_scratches_are_repaired();

// 보호 경로: 지우면 안 되는 것을 지키는가, 그리고 강도·축소 규율.
void test_dense_chromatic_grain_field_is_not_repaired();
void test_wide_highlight_and_dark_structure_are_protected();
void test_large_frame_lanczos_detection_and_affine_mask();
void test_rounded_short_axis_keeps_the_uniform_lanczos_scale();
void test_strength_zero_is_bit_exact_and_partial_strength_blends();

// 검출 경로: 민감도, 전면 구조 필터, 타일 stitch, 라벨 검출.
void test_labeled_integer_gate_boundaries_match_macos();
void test_tile_local_structure_grid_precedes_speck_merge();
void test_review_preserves_exact_component_ownership_and_acceptance();
void test_review_nearest_hit_matches_macos_ring_order();
void test_detection_sensitivity_controls_candidate_thresholds();
void test_whole_frame_structure_filter_preserves_grid_lines();
void test_stitch_keeps_highest_confidence_classification();
void test_whole_frame_tiles_stitch_a_boundary_scratch();
void test_labeled_detection_adds_curved_thin_scratch_evidence();

// 계약 경로: 잘못된 입력, 취소, 검출과 수리의 일치, 가이드 ROI, 분류.
void test_invalid_inputs_fail_closed();
void test_cancellation_stops_detection_and_keeps_results();
void test_detection_only_agrees_with_the_repair_path();
void test_guided_detection_crops_to_the_selected_roi();
void test_isolated_dark_blob_is_classified_dust_or_pinhole();
void test_micro_specks_become_classified_components();
void test_micro_speck_detection_is_optional_and_additive();

}  // namespace grain_mend_tests
