#pragma once

/* Flatbed frame-grid detection and the handle that owns its ordered result. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

#define NF_FLATBED_FRAME_GRID_OK 0U
#define NF_FLATBED_FRAME_GRID_INVALID_INPUT 1U
#define NF_FLATBED_FRAME_GRID_CANCELLED 2U
#define NF_FLATBED_FRAME_GRID_ALLOCATION_FAILED 3U

#define NF_FLATBED_FRAME_FULL_FRAME_35MM 0U
#define NF_FLATBED_FRAME_SQUARE_35MM 1U
#define NF_FLATBED_FRAME_HALF_FRAME_35MM 2U
#define NF_FLATBED_FRAME_MEDIUM_645 3U
#define NF_FLATBED_FRAME_MEDIUM_66 4U
#define NF_FLATBED_FRAME_MEDIUM_67 5U
#define NF_FLATBED_FRAME_MEDIUM_68 6U
#define NF_FLATBED_FRAME_MEDIUM_69 7U
#define NF_FLATBED_FRAME_MEDIUM_612 8U
#define NF_FLATBED_FRAME_MEDIUM_617 9U

typedef struct nf_flatbed_frame_grid_summary_v1 {
    uint32_t struct_size;
    uint32_t reserved;
    uint32_t status;
    uint32_t reserved2;
    uint64_t detection_count;
} nf_flatbed_frame_grid_summary_v1;

typedef struct nf_flatbed_frame_detection_v1 {
    uint32_t struct_size;
    uint32_t row;
    uint32_t column;
    uint32_t reserved;
    double x;
    double y;
    double width;
    double height;
    double confidence;
    /* Optional tail since 2026-08-24. Older 56-byte callers receive the common fields. */
    double straighten_angle;
} nf_flatbed_frame_detection_v1;

typedef struct nf_flatbed_frame_grid_handle_v1 nf_flatbed_frame_grid_handle_v1;

/* Detects frame apertures in one top-first normalized linear luminance preview. The
   opaque handle owns the ordered result until destroy, so reading detections does not
   rerun the detector. A successful empty grid still returns a handle. */
NF_API nf_status_t NF_CALL nf_detect_flatbed_frame_grid_v1(
    const float* luminance,
    uint32_t stride_bytes,
    uint32_t width,
    uint32_t height,
    double physical_width_mm,
    double physical_height_mm,
    uint32_t format,
    const uint32_t* cancel_requested,
    nf_flatbed_frame_grid_summary_v1* summary,
    nf_flatbed_frame_grid_handle_v1** handle);
NF_API nf_status_t NF_CALL nf_detect_flatbed_frame_edges_v1(
    const float* luminance,
    uint32_t stride_bytes,
    uint32_t width,
    uint32_t height,
    uint32_t format,
    const uint32_t* cancel_requested,
    nf_flatbed_frame_grid_summary_v1* summary,
    nf_flatbed_frame_grid_handle_v1** handle);
NF_API nf_status_t NF_CALL nf_flatbed_frame_grid_get_detection_v1(
    const nf_flatbed_frame_grid_handle_v1* handle,
    uint64_t index,
    nf_flatbed_frame_detection_v1* detection);
NF_API void NF_CALL nf_flatbed_frame_grid_destroy_v1(
    nf_flatbed_frame_grid_handle_v1* handle);

#ifdef __cplusplus
}
#endif
