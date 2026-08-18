#pragma once

/* Bounded source probes used by import and relink before a catalog path changes. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

#define NF_TIFF_SOURCE_PROBE_OK 0U
#define NF_TIFF_SOURCE_PROBE_UNREADABLE 1U
#define NF_TIFF_SOURCE_PROBE_UNSUPPORTED 2U

#define NF_STANDARD_IMAGE_SOURCE_PROBE_OK 0U
#define NF_STANDARD_IMAGE_SOURCE_PROBE_UNREADABLE 1U
#define NF_STANDARD_IMAGE_SOURCE_PROBE_UNSUPPORTED 2U

/* A bounded TIFF probe result used by import and relink before a catalog path changes.
   It carries source traits only; no image samples or caller-owned allocations cross the ABI. */
typedef struct nf_tiff_source_info_v1 {
    uint32_t struct_size;
    uint32_t status;
    uint32_t pixel_width;
    uint32_t pixel_height;
    uint16_t samples_per_pixel;
    uint16_t bits_per_sample;
    uint16_t sample_format;
    uint16_t orientation;
    uint64_t file_bytes;
} nf_tiff_source_info_v1;

/* A bounded JPEG/PNG probe used by import and relink. Decoded pixels never cross the
   ABI; the 16-bit RGBA traits describe the normalized WIC decode contract. */
typedef struct nf_standard_image_source_info_v1 {
    uint32_t struct_size;
    uint32_t status;
    uint32_t pixel_width;
    uint32_t pixel_height;
    uint16_t samples_per_pixel;
    uint16_t bits_per_sample;
    uint16_t sample_format;
    uint16_t orientation;
    uint64_t file_bytes;
} nf_standard_image_source_info_v1;

NF_API nf_status_t NF_CALL nf_probe_tiff_source_v1(
    const wchar_t* source_path,
    nf_tiff_source_info_v1* result);

NF_API nf_status_t NF_CALL nf_probe_standard_image_source_v1(
    const wchar_t* source_path,
    nf_standard_image_source_info_v1* result);

#ifdef __cplusplus
}
#endif
