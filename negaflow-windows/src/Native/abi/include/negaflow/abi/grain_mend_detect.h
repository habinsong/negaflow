#pragma once

/* GrainMend detection - what the automatic repair would touch, instead of touching it. */

#include "negaflow/abi/develop_output.h"
#include "negaflow/abi/develop_result.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Runs the develop pipeline to the GrainMend stage and reports what the automatic repair
   would touch, instead of touching it. The reviewable GrainMend tools (Auto and Guided)
   need the decision rather than the result.

   Detection must come from this pipeline, not from a standalone call on the scan:
   GrainMend runs after the film look, on the developed positive, and the same dust looks
   nothing alike on the negative.

   `mask` receives one byte per pixel of the capped analysis image, whose size the result
   reports. Pass a null `mask` to learn `mask_byte_count` without copying; the maximum is
   1800 * 1800, so a caller may also allocate once and never ask. Too small a buffer fails
   with "mask_buffer_too_small" and still reports the size needed. `destination_path` in
   the request is ignored. */
typedef struct nf_grain_mend_detection_v1 {
    uint32_t struct_size;
    uint32_t reserved;
    uint32_t width;
    uint32_t height;
    uint64_t accepted_pixels;
    uint64_t mask_byte_count;
} nf_grain_mend_detection_v1;

/* v2 adds the exact raw source rectangle used to make the capped mask. The
   detector and mask are top-first; the caller converts to the recipe's y-up
   convention only when it commits an accepted result. */
typedef struct nf_grain_mend_detect_parameters_v1 {
    uint32_t struct_size;
    uint32_t reserved;
    double roi_x;
    double roi_y;
    double roi_width;
    double roi_height;
} nf_grain_mend_detect_parameters_v1;

/* v3 keeps the ROI prefix and adds the per-run detector tuning used by the
   review controls. These values are deliberately not stored in a Defects
   sidecar: they only decide what the transient review session proposes. */
typedef struct nf_grain_mend_detect_parameters_v2 {
    nf_grain_mend_detect_parameters_v1 v1;
    double dust_sensitivity;
    double scratch_sensitivity;
    double protect_detail;
    uint32_t reject_structure_lines;
    uint32_t reserved;
} nf_grain_mend_detect_parameters_v2;

/* v4 retains all transient review tuning and appends the optional macOS micro-speck
   pass. The bit is intentionally separate from persisted Defects edits: it only
   changes the proposal the user is about to accept. */
typedef struct nf_grain_mend_detect_parameters_v3 {
    nf_grain_mend_detect_parameters_v2 v2;
    uint32_t detect_micro_specks;
    uint32_t reserved;
} nf_grain_mend_detect_parameters_v3;

typedef struct nf_grain_mend_detection_v2 {
    uint32_t struct_size;
    uint32_t reserved;
    uint32_t width;
    uint32_t height;
    uint64_t accepted_pixels;
    uint64_t mask_byte_count;
    uint32_t source_width;
    uint32_t source_height;
    uint32_t roi_x;
    uint32_t roi_y;
    uint32_t roi_width;
    uint32_t roi_height;
} nf_grain_mend_detection_v2;

/* 채택된 결함 하나. 분류 값은 grain_mend_detail::DefectClassification 과 같은 순서다:
   0 dust, 1 pinhole, 2 scratch_horizontal, 3 scratch_vertical, 4 scratch_diagonal,
   5 emulsion_damage, 6 micro_speck. 좌표는 검출 이미지(width x height) 기준이다. */
typedef struct nf_grain_mend_component_v1 {
    uint32_t struct_size;
    uint32_t classification;
    double confidence;
    uint64_t area;
    uint32_t minimum_x;
    uint32_t minimum_y;
    uint32_t maximum_x;
    uint32_t maximum_y;
    /* 이 컴포넌트의 미리보기 점이 놓인 자리. 점들은 컴포넌트 순서대로 한 평면 배열에
       이어 담긴다 — 배열 하나만 넘기면 되므로 IR 경로와 같은 모양이다. */
    uint64_t preview_point_offset;
    uint64_t preview_point_count;
} nf_grain_mend_component_v1;

/* 검출 이미지 기준 좌표다(원본 화소가 아니다). */
typedef struct nf_grain_mend_preview_point_v1 {
    uint32_t x;
    uint32_t y;
} nf_grain_mend_preview_point_v1;

/* v2 에 컴포넌트 수를 더한다. 마스크와 같은 두 번 부르기 규약이다: 버퍼를 null 로 주면
   개수만 채워 돌려주고, 그 크기로 다시 부르면 복사한다. 검출을 다시 돌리지 않는다. */
typedef struct nf_grain_mend_detection_v3 {
    nf_grain_mend_detection_v2 v2;
    uint64_t component_count;
    uint64_t preview_point_count;
} nf_grain_mend_detection_v3;

/* v3 에 macOS `DefectLabelField.automaticFalsePositiveRisk` /
   `automaticCandidatePixelFraction` 을 더한다. 전체 프레임 자동에서만 채워지고, 성분은
   하나도 버리지 않는다 — 화면은 개수 대신 경고 문구를 낼 뿐이다. */
typedef struct nf_grain_mend_detection_v4 {
    nf_grain_mend_detection_v3 v3;
    uint32_t automatic_false_positive_risk;
    uint32_t reserved;
    double automatic_candidate_pixel_fraction;
} nf_grain_mend_detection_v4;

NF_API nf_status_t NF_CALL nf_develop_detect_grain_mend_v1(
    const nf_develop_export_request_v27* request,
    uint8_t* mask,
    uint64_t mask_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_grain_mend_detection_v1* detection,
    nf_develop_export_result_v3* result);

NF_API nf_status_t NF_CALL nf_develop_detect_grain_mend_v2(
    const nf_develop_export_request_v27* request,
    const nf_grain_mend_detect_parameters_v1* parameters,
    uint8_t* mask,
    uint64_t mask_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_grain_mend_detection_v2* detection,
    nf_develop_export_result_v3* result);

NF_API nf_status_t NF_CALL nf_develop_detect_grain_mend_v3(
    const nf_develop_export_request_v27* request,
    const nf_grain_mend_detect_parameters_v2* parameters,
    uint8_t* mask,
    uint64_t mask_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_grain_mend_detection_v2* detection,
    nf_develop_export_result_v3* result);

NF_API nf_status_t NF_CALL nf_develop_detect_grain_mend_v4(
    const nf_develop_export_request_v27* request,
    const nf_grain_mend_detect_parameters_v3* parameters,
    uint8_t* mask,
    uint64_t mask_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_grain_mend_detection_v2* detection,
    nf_develop_export_result_v3* result);

/* v4 와 같은 검출이되 채택된 결함을 분류까지 함께 낸다. `components` 가 null 이면
   `detection->component_count` 만 채운다. */
NF_API nf_status_t NF_CALL nf_develop_detect_grain_mend_v5(
    const nf_develop_export_request_v27* request,
    const nf_grain_mend_detect_parameters_v3* parameters,
    uint8_t* mask,
    uint64_t mask_capacity_bytes,
    nf_grain_mend_component_v1* components,
    uint64_t component_capacity,
    nf_grain_mend_preview_point_v1* preview_points,
    uint64_t preview_point_capacity,
    nf_develop_run_state_v1* run_state,
    nf_grain_mend_detection_v3* detection,
    nf_develop_export_result_v3* result);

/* v5 와 같은 검출이되 자동 오검출 위험 플래그까지 낸다. macOS
   `applyingWholeFrameAutomaticRiskFlag` 의 결과이며 전체 프레임 자동에서만 채워진다. */
NF_API nf_status_t NF_CALL nf_develop_detect_grain_mend_v6(
    const nf_develop_export_request_v27* request,
    const nf_grain_mend_detect_parameters_v3* parameters,
    uint8_t* mask,
    uint64_t mask_capacity_bytes,
    nf_grain_mend_component_v1* components,
    uint64_t component_capacity,
    nf_grain_mend_preview_point_v1* preview_points,
    uint64_t preview_point_capacity,
    nf_develop_run_state_v1* run_state,
    nf_grain_mend_detection_v4* detection,
    nf_develop_export_result_v3* result);

#ifdef __cplusplus
}
#endif
