#include "negaflow_abi.h"

#include <cstddef>

// 공개 C ABI 구조체 크기와 패딩이 결정하는 오프셋을 고정합니다.
// 관리 쪽 손 선언과 어긋나면 바인딩은 되지만 읽은 값이 쓰레기입니다.

static_assert(sizeof(nf_build_info_v1) == 44U);
static_assert(offsetof(nf_build_info_v1, source_commit_sha1) == 24U);

// The managed side declares the same layout by hand. A drift on either side would
// still bind and then read garbage, so the sizes and the two offsets that padding
// actually decides are pinned here.
static_assert(sizeof(nf_develop_export_request_v1) == 96U);
static_assert(offsetof(nf_develop_export_request_v1, film_emulation_intensity) == 80U);
static_assert(sizeof(nf_develop_export_request_v2) == 96U);
static_assert(offsetof(nf_develop_export_request_v2, base_estimation_mode) == 32U);
static_assert(offsetof(nf_develop_export_request_v2, film_emulation_intensity) == 80U);
static_assert(sizeof(nf_develop_export_request_v3) == 112U);
static_assert(offsetof(nf_develop_export_request_v3, base_estimation_mode) == 32U);
static_assert(offsetof(nf_develop_export_request_v3, density) == 92U);
static_assert(sizeof(nf_develop_export_request_v4) == 128U);
static_assert(offsetof(nf_develop_export_request_v4, density) == 92U);
static_assert(offsetof(nf_develop_export_request_v4, film_stock_dmin_id) == 112U);
static_assert(sizeof(nf_point_curve_point_v1) == 16U);
static_assert(sizeof(nf_point_curve_v1) == 1032U);
static_assert(offsetof(nf_point_curve_v1, points) == 8U);
static_assert(sizeof(nf_develop_export_request_v5) == 4256U);
static_assert(offsetof(nf_develop_export_request_v5, point_curve_rgb) == 128U);
static_assert(sizeof(nf_develop_export_request_v6) == 4352U);
static_assert(offsetof(nf_develop_export_request_v6, color_mixer_hue) == 4256U);
static_assert(sizeof(nf_develop_export_request_v7) == 4400U);
static_assert(offsetof(nf_develop_export_request_v7, color_grading_shadows_hue) == 4352U);
static_assert(sizeof(nf_develop_export_request_v8) == 4408U);
static_assert(offsetof(nf_develop_export_request_v8, defect_removal_strength) == 4400U);
static_assert(sizeof(nf_develop_export_request_v9) == 4440U);
static_assert(offsetof(nf_develop_export_request_v9, noise_reduction_strength) == 4408U);
static_assert(offsetof(nf_develop_export_request_v9, noise_reduction_film_profile) == 4432U);
static_assert(sizeof(nf_develop_export_request_v10) == 4464U);
static_assert(offsetof(nf_develop_export_request_v10, texture_grain) == 4440U);
static_assert(offsetof(nf_develop_export_request_v10, texture_vignette) == 4456U);
static_assert(sizeof(nf_develop_export_request_v11) == 4552U);
static_assert(offsetof(nf_develop_export_request_v11, bw_toning_mode) == 4464U);
static_assert(offsetof(nf_develop_export_request_v11, straighten_angle) == 4544U);
static_assert(sizeof(nf_local_dodge_burn_point_v1) == 8U);
static_assert(sizeof(nf_local_dodge_burn_stroke_v1) == 16U);
static_assert(sizeof(nf_local_dodge_burn_adjustment_v1) == 64U);
static_assert(sizeof(nf_develop_export_request_v12) == 4600U);
static_assert(offsetof(nf_develop_export_request_v12, local_adjustments) == 4552U);
static_assert(offsetof(nf_develop_export_request_v12, local_strokes) == 4568U);
static_assert(offsetof(nf_develop_export_request_v12, local_points) == 4584U);
static_assert(sizeof(nf_develop_export_request_v13) == 4632U);
static_assert(offsetof(nf_develop_export_request_v13, warmth) == 4600U);
static_assert(offsetof(nf_develop_export_request_v13, blue_primary) == 4628U);
static_assert(sizeof(nf_develop_export_request_v14) == 4640U);
static_assert(offsetof(nf_develop_export_request_v14, auto_levels) == 4632U);
static_assert(offsetof(nf_develop_export_request_v14, auto_neutral_balance) == 4636U);
static_assert(sizeof(nf_develop_export_request_v15) == 4648U);
static_assert(offsetof(nf_develop_export_request_v15, develop_target) == 4640U);
static_assert(offsetof(nf_develop_export_request_v15, reserved) == 4644U);
static_assert(sizeof(nf_develop_export_request_v16) == 4656U);
static_assert(offsetof(nf_develop_export_request_v16, scanner_profile_id) == 4648U);
static_assert(sizeof(nf_develop_export_request_v17) == 4664U);
static_assert(offsetof(nf_develop_export_request_v17, film_polarity) == 4656U);
static_assert(sizeof(nf_defect_region_edit_v1) == 56U);
static_assert(offsetof(nf_defect_region_edit_v1, strength) == 32U);
static_assert(offsetof(nf_defect_region_edit_v1, preferred_angle_degrees) == 48U);
static_assert(sizeof(nf_develop_export_request_v18) == 4696U);
static_assert(offsetof(nf_develop_export_request_v18, defect_region_edits) == 4664U);
static_assert(offsetof(nf_develop_export_request_v18, defect_mask_bytes) == 4680U);
static_assert(sizeof(nf_develop_export_request_v19) == 4720U);
static_assert(offsetof(nf_develop_export_request_v19, defect_source_file_bytes) == 4696U);
static_assert(offsetof(nf_develop_export_request_v19, defect_source_sha256) == 4704U);
static_assert(sizeof(nf_defect_clone_point_v1) == 16U);
static_assert(sizeof(nf_defect_clone_stroke_v1) == 40U);
static_assert(offsetof(nf_defect_clone_stroke_v1, offset_x) == 8U);
static_assert(sizeof(nf_defect_clone_edit_v1) == 24U);
static_assert(offsetof(nf_defect_clone_edit_v1, strength) == 16U);
static_assert(sizeof(nf_defect_recipe_edit_ref_v1) == 8U);
static_assert(sizeof(nf_develop_export_request_v20) == 4784U);
static_assert(offsetof(nf_develop_export_request_v20, defect_clone_edits) == 4720U);
static_assert(offsetof(nf_develop_export_request_v20, defect_clone_strokes) == 4736U);
static_assert(offsetof(nf_develop_export_request_v20, defect_clone_points) == 4752U);
static_assert(offsetof(nf_develop_export_request_v20, defect_edit_order) == 4768U);
static_assert(sizeof(nf_defect_brush_point_v1) == 16U);
static_assert(sizeof(nf_defect_brush_stroke_v1) == 16U);
static_assert(offsetof(nf_defect_brush_stroke_v1, thickness) == 8U);
static_assert(sizeof(nf_defect_brush_edit_v1) == 24U);
static_assert(offsetof(nf_defect_brush_edit_v1, strength) == 16U);
static_assert(sizeof(nf_develop_export_request_v21) == 4832U);
static_assert(offsetof(nf_develop_export_request_v21, defect_brush_edits) == 4784U);
static_assert(offsetof(nf_develop_export_request_v21, defect_brush_strokes) == 4800U);
static_assert(offsetof(nf_develop_export_request_v21, defect_brush_points) == 4816U);
static_assert(sizeof(nf_defect_infrared_edit_v1) == 24U);
static_assert(offsetof(nf_defect_infrared_edit_v1, attenuation_offset) == 12U);
static_assert(sizeof(nf_develop_export_request_v24) == 4864U);
static_assert(offsetof(nf_develop_export_request_v24, defect_infrared_edits) == 4832U);
static_assert(offsetof(
                  nf_develop_export_request_v24,
                  defect_infrared_attenuation_bytes) == 4848U);
static_assert(sizeof(nf_defect_infrared_item_v1) == 16U);
static_assert(sizeof(nf_develop_export_request_v25) == 4880U);
static_assert(offsetof(
                  nf_develop_export_request_v25,
                  defect_infrared_items) == 4864U);
static_assert(sizeof(nf_develop_export_request_v26) == 4896U);
static_assert(offsetof(
                  nf_develop_export_request_v26,
                  output_sharpening_strength) == 4880U);
static_assert(sizeof(nf_develop_export_request_v27) == 4928U);
static_assert(offsetof(
                  nf_develop_export_request_v27,
                  primary_calibration_red_hue) == 4896U);
static_assert(sizeof(nf_develop_export_request_v28) == 4944U);
static_assert(offsetof(nf_develop_export_request_v28, jpeg_quality) == 4928U);
static_assert(sizeof(nf_develop_export_request_v29) == 4960U);
static_assert(offsetof(nf_develop_export_request_v29, output_long_edge) == 4944U);
static_assert(sizeof(nf_develop_export_request_v30) == 4976U);
static_assert(offsetof(nf_develop_export_request_v30, tiff_compression) == 4960U);
static_assert(sizeof(nf_develop_export_request_v31) == 4992U);
static_assert(offsetof(nf_develop_export_request_v31, output_bit_depth) == 4976U);
static_assert(sizeof(nf_develop_export_request_v33) == 5088U);
static_assert(offsetof(nf_develop_export_request_v33, metadata_policy) == 5008U);
static_assert(sizeof(nf_develop_export_request_v34) == 5104U);
static_assert(offsetof(nf_develop_export_request_v34, preserve_alpha) == 5088U);
static_assert(sizeof(nf_develop_export_request_v35) == 5120U);
static_assert(offsetof(nf_develop_export_request_v35, defect_recipe_sha256) == 5104U);
static_assert(sizeof(nf_develop_export_request_v32) == 5008U);
static_assert(offsetof(nf_develop_export_request_v32, output_color_space) == 4992U);
static_assert(sizeof(nf_grain_mend_detect_parameters_v1) == 40U);
static_assert(sizeof(nf_grain_mend_detect_parameters_v2) == 72U);
static_assert(offsetof(nf_grain_mend_detect_parameters_v2, dust_sensitivity) == 40U);
static_assert(sizeof(nf_grain_mend_detect_parameters_v3) == 80U);
static_assert(offsetof(nf_grain_mend_detect_parameters_v3, detect_micro_specks) == 72U);
static_assert(sizeof(nf_develop_export_result_v1) == 136U);
static_assert(offsetof(nf_develop_export_result_v1, failure_name) == 12U);
static_assert(offsetof(nf_develop_export_result_v1, source_file_bytes) == 104U);
static_assert(sizeof(nf_develop_export_result_v2) == 152U);
static_assert(offsetof(nf_develop_export_result_v2, applied_dmin) == 136U);
// v3 has to keep the v2 prefix byte for byte; only then is the appended cancellation
// answer a pure addition rather than a silent reinterpretation of an existing field.
static_assert(sizeof(nf_develop_export_result_v3) == 160U);
static_assert(offsetof(nf_develop_export_result_v3, failure_name) == 12U);
static_assert(offsetof(nf_develop_export_result_v3, source_file_bytes) == 104U);
static_assert(offsetof(nf_develop_export_result_v3, applied_dmin) == 136U);
static_assert(offsetof(nf_develop_export_result_v3, base_source) == 148U);
static_assert(offsetof(nf_develop_export_result_v3, cancelled) == 152U);
static_assert(sizeof(nf_film_base_measurement_v1) == 184U);
static_assert(sizeof(nf_develop_export_result_v4) == 344U);
static_assert(offsetof(nf_develop_export_result_v4, v3) == 0U);
static_assert(offsetof(nf_develop_export_result_v4, measurement) == 160U);
static_assert(sizeof(nf_develop_debug_metrics_v1) == 44U);
static_assert(sizeof(nf_develop_export_result_v5) == 392U);
static_assert(offsetof(nf_develop_export_result_v5, v4) == 0U);
static_assert(offsetof(nf_develop_export_result_v5, debug_metrics) == 344U);
static_assert(offsetof(nf_film_base_measurement_v1, sample_coverage) == 40U);
static_assert(sizeof(nf_develop_run_state_v1) == 16U);
static_assert(sizeof(nf_soft_proof_media_v1) == 40U);
static_assert(offsetof(nf_soft_proof_media_v1, paper_white_rgb) == 16U);
static_assert(offsetof(nf_soft_proof_media_v1, black_ink_rgb) == 28U);
static_assert(sizeof(nf_soft_proof_v1) == 44U);
static_assert(offsetof(nf_soft_proof_v1, paper_white_rgb) == 16U);
static_assert(offsetof(nf_soft_proof_v1, black_ink_rgb) == 28U);
static_assert(offsetof(nf_soft_proof_v1, clipping_overlay) == 40U);
static_assert(sizeof(nf_auto_adjust_result_v1) == 88U);
static_assert(offsetof(nf_auto_adjust_result_v1, exposure) == 8U);
static_assert(offsetof(nf_auto_adjust_result_v1, warmth) == 72U);
static_assert(offsetof(nf_auto_adjust_result_v1, tint) == 80U);
static_assert(sizeof(nf_infrared_detector_parameters_v1) == 48U);
static_assert(offsetof(nf_infrared_detector_parameters_v1, maximum_coverage) == 16U);
static_assert(sizeof(nf_infrared_detection_summary_v1) == 112U);
static_assert(offsetof(nf_infrared_detection_summary_v1, coverage) == 48U);
static_assert(offsetof(nf_infrared_detection_summary_v1, candidate_count) == 80U);
static_assert(sizeof(nf_infrared_cluster_v1) == 40U);
static_assert(offsetof(nf_infrared_cluster_v1, core_mask_byte_count) == 24U);
static_assert(sizeof(nf_infrared_component_v1) == 32U);
static_assert(sizeof(nf_infrared_preview_point_v1) == 8U);
static_assert(sizeof(nf_flatbed_frame_grid_summary_v1) == 24U);
static_assert(sizeof(nf_flatbed_frame_detection_v1) == 56U);
static_assert(offsetof(nf_flatbed_frame_detection_v1, x) == 16U);
static_assert(sizeof(nf_tiff_source_info_v1) == 32U);
static_assert(offsetof(nf_tiff_source_info_v1, file_bytes) == 24U);
static_assert(sizeof(nf_standard_image_source_info_v1) == 32U);
static_assert(offsetof(nf_standard_image_source_info_v1, file_bytes) == 24U);
static_assert(offsetof(nf_develop_run_state_v1, cancel_requested) == 4U);
static_assert(offsetof(nf_develop_run_state_v1, stage) == 8U);
static_assert(offsetof(nf_develop_run_state_v1, progress_permille) == 12U);
