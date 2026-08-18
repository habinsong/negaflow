#pragma once

/* Infrared defect detection and the handle that owns its variable payloads. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

#define NF_INFRARED_DETECTION_OK 0U
#define NF_INFRARED_DETECTION_UNREADABLE 1U
#define NF_INFRARED_DETECTION_TOO_SMALL 2U
#define NF_INFRARED_DETECTION_NO_DEFECTS 3U
#define NF_INFRARED_DETECTION_COVERAGE_TOO_HIGH 4U
#define NF_INFRARED_DETECTION_CANCELLED 5U
#define NF_INFRARED_DETECTION_ALLOCATION_FAILED 6U

#define NF_INFRARED_ALIGNMENT_NOT_REQUESTED 0U
#define NF_INFRARED_ALIGNMENT_ALIGNED 1U
#define NF_INFRARED_ALIGNMENT_INSUFFICIENT_TEXTURE 2U
#define NF_INFRARED_ALIGNMENT_WEAK_CORRELATION 3U
#define NF_INFRARED_ALIGNMENT_SEARCH_LIMIT_REACHED 4U

#define NF_INFRARED_DEFECT_DUST 0U
#define NF_INFRARED_DEFECT_SCRATCH_HORIZONTAL 1U
#define NF_INFRARED_DEFECT_SCRATCH_VERTICAL 2U
#define NF_INFRARED_DEFECT_SCRATCH_DIAGONAL 3U

typedef struct nf_infrared_detector_parameters_v1 {
    uint32_t struct_size;
    uint32_t reserved;
    double sensitivity;
    double maximum_coverage;
    int32_t dilate_radius;
    int32_t minimum_area;
    int32_t alignment_search_radius;
    int32_t cluster_tile;
    int32_t cluster_padding;
    uint32_t reserved2;
} nf_infrared_detector_parameters_v1;

typedef struct nf_infrared_detection_summary_v1 {
    uint32_t struct_size;
    uint32_t reserved;
    uint32_t status;
    uint32_t width;
    uint32_t height;
    int32_t offset_x;
    int32_t offset_y;
    uint32_t alignment_status;
    uint32_t alignment_search_radius;
    uint32_t alignment_downsample_factor;
    uint32_t reserved2;
    uint32_t reserved3;
    double coverage;
    double median_gain;
    double alignment_peak_correlation;
    double alignment_runner_up_correlation;
    uint64_t candidate_count;
    uint64_t confirmed_count;
    uint64_t cluster_count;
    uint64_t component_count;
} nf_infrared_detection_summary_v1;

typedef struct nf_infrared_cluster_v1 {
    uint32_t struct_size;
    uint32_t reserved;
    uint32_t roi_x;
    uint32_t roi_y_up;
    uint32_t width;
    uint32_t height;
    uint64_t core_mask_byte_count;
    uint64_t attenuation_value_count;
} nf_infrared_cluster_v1;

typedef struct nf_infrared_component_v1 {
    uint32_t struct_size;
    uint32_t classification;
    double confidence;
    uint64_t area;
    uint64_t preview_point_count;
} nf_infrared_component_v1;

typedef struct nf_infrared_preview_point_v1 {
    uint32_t x;
    uint32_t y;
} nf_infrared_preview_point_v1;

typedef struct nf_infrared_detection_handle_v1 nf_infrared_detection_handle_v1;

/* Detects one paired top-first linear float IR/red frame exactly once. The returned
   opaque handle owns all variable payloads until destroy; descriptor calls first
   report sizes with null payload pointers, then copy without rerunning detection. */
NF_API nf_status_t NF_CALL nf_detect_infrared_defects_v1(
    const float* infrared,
    uint32_t infrared_stride_bytes,
    const float* red,
    uint32_t red_stride_bytes,
    uint32_t width,
    uint32_t height,
    const nf_infrared_detector_parameters_v1* parameters,
    const uint32_t* cancel_requested,
    nf_infrared_detection_summary_v1* summary,
    nf_infrared_detection_handle_v1** handle);
NF_API nf_status_t NF_CALL nf_detect_infrared_defects_from_tiff_v1(
    const wchar_t* visible_path,
    const wchar_t* infrared_path,
    const nf_infrared_detector_parameters_v1* parameters,
    const uint32_t* cancel_requested,
    nf_infrared_detection_summary_v1* summary,
    nf_infrared_detection_handle_v1** handle);
NF_API nf_status_t NF_CALL nf_infrared_detection_get_cluster_v1(
    const nf_infrared_detection_handle_v1* handle,
    uint64_t index,
    nf_infrared_cluster_v1* cluster,
    uint8_t* core_mask,
    uint64_t core_mask_capacity_bytes,
    uint16_t* attenuation_r16,
    uint64_t attenuation_capacity_values);
NF_API nf_status_t NF_CALL nf_infrared_detection_get_component_v1(
    const nf_infrared_detection_handle_v1* handle,
    uint64_t index,
    nf_infrared_component_v1* component,
    nf_infrared_preview_point_v1* preview_points,
    uint64_t preview_point_capacity);
NF_API void NF_CALL nf_infrared_detection_destroy_v1(
    nf_infrared_detection_handle_v1* handle);

#ifdef __cplusplus
}
#endif
