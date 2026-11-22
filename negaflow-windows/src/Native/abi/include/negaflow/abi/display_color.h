#pragma once

/* Display colour management for the preview canvases.

   With Advanced Color off, Windows sends application pixels to the display as if they were
   sRGB, so a wide-gamut monitor shows the sRGB preview oversaturated. The shell reads the
   monitor's ICC profile (GetICMProfileW) and moves the preview into it just before drawing.
   With Advanced Color on, the system does the sRGB-to-display conversion itself and the
   profile API answers sRGB: the table built from it is the identity, `is_identity` reports
   it, and the shell draws the pixels unchanged.

   Only what is drawn is converted. Cached previews, histograms, thumbnails and exports stay
   sRGB. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct nf_display_color_transform_v1 nf_display_color_transform_v1;

/* sRGB -> `monitor_icc` (relative colorimetric). `is_identity` is 1 when every grid point
   lands within two 8-bit steps of where it started (ICM itself moves dark sRGB-to-sRGB grid
   points by about one step); applying it would change nothing visible. */
NF_API nf_status_t NF_CALL nf_display_color_transform_create_v1(
    const uint8_t* monitor_icc,
    uint32_t monitor_icc_size,
    nf_display_color_transform_v1** transform,
    uint32_t* is_identity,
    uint32_t* native_error_code);

/* Soft-proof round trip: sRGB -> `proof_icc` -> sRGB (relative colorimetric, BEST_MODE), the
   same transform the per-frame proof used to run through ICM, as a 33^3 table built once per
   profile. `is_identity` as above. Applied and destroyed with the functions below. */
NF_API nf_status_t NF_CALL nf_proof_color_transform_create_v1(
    const uint8_t* proof_icc,
    uint32_t proof_icc_size,
    nf_display_color_transform_v1** transform,
    uint32_t* is_identity,
    uint32_t* native_error_code);

/* BGRA8, `stride_bytes` apart in both buffers. Alpha is copied unchanged. `source` and
   `destination` may be the same buffer. */
NF_API nf_status_t NF_CALL nf_display_color_transform_apply_bgra_v1(
    const nf_display_color_transform_v1* transform,
    const uint8_t* source,
    uint8_t* destination,
    uint32_t width,
    uint32_t height,
    uint32_t stride_bytes);

NF_API void NF_CALL nf_display_color_transform_destroy_v1(
    nf_display_color_transform_v1* transform);

#ifdef __cplusplus
}
#endif
