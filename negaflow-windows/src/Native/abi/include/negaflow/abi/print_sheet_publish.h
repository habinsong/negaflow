#pragma once

/* Publishing a finished print sheet: the page is already composed and already in the
   published colour space, so this writes those code values and tags the file with that
   profile. Separate from the develop export entry points, which take a recipe and a source
   file and make the pixels themselves. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Formats match `nf_develop_export_format`: 0 PNG 16-bit, 1 TIFF 16-bit, 2 JPEG 8-bit.
   TIFF compression matches `nf_develop_tiff_compression`: 0 none, 1 LZW, 2 deflate.

   `samples` is 3-channel RGB16, row-major, `stride_bytes` apart. `sample_count` is the
   number of uint16 values the caller owns, so a short buffer is refused instead of read
   past. `output_icc_profile` may be null: then the file carries the system sRGB profile,
   the same one every other sRGB file on the machine carries. */
typedef struct nf_print_sheet_publish_request_v1 {
    uint32_t struct_size;
    uint32_t format;
    const wchar_t* destination_path;
    const uint16_t* samples;
    uint64_t sample_count;
    uint32_t width;
    uint32_t height;
    uint32_t stride_bytes;
    uint32_t output_dpi;
    float jpeg_quality;
    uint32_t tiff_compression;
    const uint8_t* output_icc_profile;
    uint32_t output_icc_profile_size;
    uint32_t reserved;
} nf_print_sheet_publish_request_v1;

/* `status` is `negaflow::output::PrintSheetPublishStatus`; zero is a published file.
   `bits_per_sample` is what the file actually carries, so the caller can prove the 16-bit
   option reached the encoder instead of trusting the option it asked for. */
typedef struct nf_print_sheet_publish_result_v1 {
    uint32_t struct_size;
    uint32_t status;
    uint32_t native_error_code;
    uint32_t cleanup_error_code;
    uint32_t bits_per_sample;
    uint32_t color_profile_bytes;
    uint64_t artifact_bytes;
    uint32_t published;
    uint32_t reserved;
} nf_print_sheet_publish_result_v1;

NF_API nf_status_t NF_CALL nf_publish_print_sheet_v1(
    const nf_print_sheet_publish_request_v1* request,
    nf_print_sheet_publish_result_v1* result);

#ifdef __cplusplus
}
#endif
