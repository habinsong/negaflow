#pragma once

/* Output-only options that never enter the stored recipe - v26 through v34. */

#include "negaflow/abi/defect_recipe.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Output sharpening is a final, output-space operation. It follows image transform
   and is never stored in the develop recipe. dpi 0 selects the medium reference DPI. */
typedef struct nf_develop_export_request_v26 {
    nf_develop_export_request_v25 v25;
    float output_sharpening_strength;
    uint32_t output_sharpening_medium;
    int32_t output_sharpening_dpi;
    uint32_t output_sharpening_reserved;
} nf_develop_export_request_v26;

/* v27 preserves v26 and appends the six macOS creative primary-calibration controls.
   Every control is finite in the stored slider range -1...1. */
typedef struct nf_develop_export_request_v27 {
    nf_develop_export_request_v26 v26;
    float primary_calibration_red_hue;
    float primary_calibration_red_saturation;
    float primary_calibration_green_hue;
    float primary_calibration_green_saturation;
    float primary_calibration_blue_hue;
    float primary_calibration_blue_saturation;
    uint32_t primary_calibration_reserved0;
    uint32_t primary_calibration_reserved1;
} nf_develop_export_request_v27;

/* v28 preserves the v27 develop recipe and appends output-only JPEG quality and
   DPI metadata. dpi zero means no user override; it never changes pixel dimensions. */
typedef struct nf_develop_export_request_v28 {
    nf_develop_export_request_v27 v27;
    float jpeg_quality;
    uint32_t output_dpi;
    uint32_t output_options_reserved0;
    uint32_t output_options_reserved1;
} nf_develop_export_request_v28;

/* v29 preserves v28 and appends the optional output long-edge cap. Zero retains
   source dimensions; a positive value only downsizes a published artifact after
   the recipe's geometry transform and before output sharpening. */
typedef struct nf_develop_export_request_v29 {
    nf_develop_export_request_v28 v28;
    uint32_t output_long_edge;
    uint32_t output_geometry_reserved0;
    uint32_t output_geometry_reserved1;
    uint32_t output_geometry_reserved2;
} nf_develop_export_request_v29;

/* v30 preserves v29 and appends TIFF-only encoding selection. PNG and TIFF both
   honor v28's output_dpi metadata; preview ignores all output-only fields. */
typedef struct nf_develop_export_request_v30 {
    nf_develop_export_request_v29 v29;
    uint32_t tiff_compression;
    uint32_t output_encoding_reserved0;
    uint32_t output_encoding_reserved1;
    uint32_t output_encoding_reserved2;
} nf_develop_export_request_v30;


/* v31 preserves v30 and appends the published sample depth. 8 or 16; PNG and TIFF honor
   it, JPEG is eight-bit by definition and ignores it, and preview ignores it entirely.
   Eight-bit output is dithered in the sRGB-encoded space before quantization. */
typedef struct nf_develop_export_request_v31 {
    nf_develop_export_request_v30 v30;
    uint32_t output_bit_depth;
    uint32_t output_depth_reserved0;
    uint32_t output_depth_reserved1;
    uint32_t output_depth_reserved2;
} nf_develop_export_request_v31;

/* v32 preserves v31 and appends the published colour space: 0 sRGB, 1 Display P3,
   2 Adobe RGB (1998). PNG and TIFF convert the pixels and carry the matching profile.
   JPEG publishes sRGB only and refuses anything else rather than mislabelling the colour.
   Preview ignores it. */
typedef struct nf_develop_export_request_v32 {
    nf_develop_export_request_v31 v31;
    uint32_t output_color_space;
    uint32_t output_space_reserved0;
    uint32_t output_space_reserved1;
    uint32_t output_space_reserved2;
} nf_develop_export_request_v32;

/* v33 preserves v32 and appends the export metadata policy with the values it writes.
   Policy: 0 minimal, 1 copyright only, 2 remove location, 3 all. Every string is
   optional; a null or empty one leaves that tag out. PNG carries no EXIF, so the
   policy leaves no trace in a PNG. */
typedef struct nf_develop_export_request_v33 {
    nf_develop_export_request_v32 v32;
    uint32_t metadata_policy;
    uint32_t metadata_reserved0;
    uint32_t metadata_reserved1;
    uint32_t metadata_reserved2;
    const wchar_t* metadata_make;
    const wchar_t* metadata_model;
    const wchar_t* metadata_software;
    const wchar_t* metadata_artist;
    const wchar_t* metadata_copyright;
    const wchar_t* metadata_film_type;
    const wchar_t* metadata_film_stock;
    /* "yyyy:MM:dd HH:mm:ss", EXIF form, UTC. */
    const wchar_t* metadata_captured_at;
} nf_develop_export_request_v33;

/* v34 appends the macOS preserve-alpha export option. JPEG rejects it; PNG and TIFF
   publish straight alpha when it is non-zero. Reserved words must be zero. */
typedef struct nf_develop_export_request_v34 {
    nf_develop_export_request_v33 v33;
    uint32_t preserve_alpha;
    uint32_t alpha_reserved0;
    uint32_t alpha_reserved1;
    uint32_t alpha_reserved2;
} nf_develop_export_request_v34;

/* v35 appends the validated fingerprint of the ordered render-affecting Defects recipe.
   It is a cache invalidation identity only; the projected edit payload remains authoritative. */
typedef struct nf_develop_export_request_v35 {
    nf_develop_export_request_v34 v34;
    const uint8_t* defect_recipe_sha256;
    uint32_t defect_recipe_sha256_size;
    uint32_t defect_recipe_identity_reserved;
} nf_develop_export_request_v35;

/* v36 appends an explicit canonical identity for the ordered prefix preceding the
   newest edit. It is an optimization hint only and is ignored unless the retained
   full-resolution cleaned raw has that exact recipe identity. */
typedef struct nf_develop_export_request_v36 {
    nf_develop_export_request_v35 v35;
    const uint8_t* defect_recipe_append_prefix_sha256;
    uint32_t defect_recipe_append_prefix_sha256_size;
    uint32_t defect_recipe_append_prefix_edit_count;
} nf_develop_export_request_v36;

#ifdef __cplusplus
}
#endif
