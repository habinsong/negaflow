#include "GrainMend/grain_mend_test_support.h"

#include <iostream>

using namespace grain_mend_tests;

int main() {
    test_labeled_integer_gate_boundaries_match_macos();
    test_tile_local_structure_grid_precedes_speck_merge();
    test_review_preserves_exact_component_ownership_and_acceptance();
    test_review_nearest_hit_matches_macos_ring_order();
    test_dust_and_thin_scratch_are_repaired();
    test_grain_only_field_is_not_wiped();
    test_diagonal_scratch_is_repaired();
    test_chromatic_dust_is_detected_without_luminance_dilution();
    test_off_axis_scratches_are_repaired();
    test_dense_chromatic_grain_field_is_not_repaired();
    test_wide_highlight_and_dark_structure_are_protected();
    test_large_frame_lanczos_detection_and_affine_mask();
    test_rounded_short_axis_keeps_the_uniform_lanczos_scale();
    test_strength_zero_is_bit_exact_and_partial_strength_blends();
    test_detection_sensitivity_controls_candidate_thresholds();
    test_whole_frame_structure_filter_preserves_grid_lines();
    test_stitch_keeps_highest_confidence_classification();
    test_whole_frame_tiles_stitch_a_boundary_scratch();
    test_labeled_detection_adds_curved_thin_scratch_evidence();
    test_invalid_inputs_fail_closed();
    test_cancellation_stops_detection_and_keeps_results();
    test_detection_only_agrees_with_the_repair_path();
    test_guided_detection_crops_to_the_selected_roi();
    test_micro_speck_detection_is_optional_and_additive();
    test_micro_specks_become_classified_components();
    test_isolated_dark_blob_is_classified_dust_or_pinhole();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"grain_mend\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
