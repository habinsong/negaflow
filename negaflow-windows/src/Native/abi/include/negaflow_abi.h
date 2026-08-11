#pragma once

#include "negaflow_abi_version.h"

#include <stdint.h>

#if defined(_WIN32)
#if defined(NEGAFLOW_NATIVE_EXPORTS)
#define NF_API __declspec(dllexport)
#else
#define NF_API __declspec(dllimport)
#endif
#define NF_CALL __cdecl
#else
#define NF_API
#define NF_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t nf_status_t;

#define NF_STATUS_OK 0U
#define NF_STATUS_INVALID_ARGUMENT 1U
#define NF_STATUS_STRUCT_TOO_SMALL 2U

#define NF_ARCHITECTURE_UNKNOWN 0U
#define NF_ARCHITECTURE_X64 1U
#define NF_ARCHITECTURE_ARM64 2U

#define NF_CPU_FEATURE_AVX_USABLE (1U << 0U)
#define NF_CPU_FEATURE_AVX2 (1U << 1U)
#define NF_CPU_FEATURE_FMA (1U << 2U)
#define NF_CPU_FEATURE_NEON_BASELINE (1U << 3U)

#define NF_COMPILER_UNKNOWN 0U
#define NF_COMPILER_MSVC 1U

typedef struct nf_build_info_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint32_t architecture;
    uint32_t cpu_feature_flags;
    uint32_t compiler_id;
    uint32_t compiler_version;
    uint8_t source_commit_sha1[20];
} nf_build_info_v1;

#define NF_EXPORT_FORMAT_PNG16 0U
#define NF_EXPORT_FORMAT_TIFF16 1U

#define NF_FILM_TYPE_COLOR 0U
#define NF_FILM_TYPE_BLACK_AND_WHITE 1U

#define NF_FILM_POLARITY_NEGATIVE 0U
#define NF_FILM_POLARITY_POSITIVE 1U

#define NF_BASE_ESTIMATION_AUTO 0U
#define NF_BASE_ESTIMATION_PRESET 1U
#define NF_BASE_ESTIMATION_MANUAL 2U

#define NF_DEVELOP_BASE_SOURCE_MANUAL 0U
#define NF_DEVELOP_BASE_SOURCE_AUTO_SCENE_EDGE 1U
#define NF_DEVELOP_BASE_SOURCE_AUTO_FALLBACK 2U
#define NF_DEVELOP_BASE_SOURCE_AUTO_CONNECTED_COMPONENT 3U
#define NF_DEVELOP_BASE_SOURCE_AUTO_CONTINUOUS_BORDER 4U
#define NF_DEVELOP_BASE_SOURCE_AUTO_DISTRIBUTED_MASK 5U
#define NF_DEVELOP_BASE_SOURCE_AUTO_STRIP_FALLBACK 6U
#define NF_DEVELOP_BASE_SOURCE_PRESET_MEASURED 7U
#define NF_DEVELOP_BASE_SOURCE_PRESET_FALLBACK 8U

#define NF_DEVELOP_SOURCE_FILM_SCAN 0U
#define NF_DEVELOP_SOURCE_RENDERED_DIGITAL 1U

#define NF_FILM_LOOK_ROUTE_INVALID 0U
#define NF_FILM_LOOK_ROUTE_IDENTITY 1U
#define NF_FILM_LOOK_ROUTE_FILM_SCAN_EMULATION 2U
#define NF_FILM_LOOK_ROUTE_DIGITAL_FILM_LOOK 3U

/* Stage identifiers mirror negaflow::pipeline::DevelopExportStage. A failure
   reports the stage together with that stage's own status name, so the caller
   never has to collapse two different refusals into one code. */
#define NF_DEVELOP_STAGE_NONE 0U
#define NF_DEVELOP_STAGE_REQUEST_VALIDATION 1U
#define NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE 2U
#define NF_DEVELOP_STAGE_DECODE 3U
#define NF_DEVELOP_STAGE_OBSERVE_SOURCE_AFTER 4U
#define NF_DEVELOP_STAGE_FILM_LOOK_WORKSPACE 5U
#define NF_DEVELOP_STAGE_DEVELOP 6U
#define NF_DEVELOP_STAGE_TONE_ADJUST 7U
#define NF_DEVELOP_STAGE_FILM_LOOK 8U
#define NF_DEVELOP_STAGE_OUTPUT 9U
#define NF_DEVELOP_STAGE_GRAIN_MEND 10U
#define NF_DEVELOP_STAGE_FILM_SCAN_DENOISE 11U
#define NF_DEVELOP_STAGE_LOCAL_DODGE_BURN 12U
#define NF_DEVELOP_STAGE_TEXTURE 13U
#define NF_DEVELOP_STAGE_BLACK_AND_WHITE 14U
#define NF_DEVELOP_STAGE_IMAGE_TRANSFORM 15U
#define NF_DEVELOP_STAGE_COLOR_MODEL 16U
#define NF_DEVELOP_STAGE_SCENE_CORRECTION 17U
#define NF_DEVELOP_STAGE_TARGET_GRADE 18U
#define NF_DEVELOP_STAGE_DEFECT_COMPONENT_REPAIR 19U
#define NF_DEVELOP_STAGE_DEFECT_CLONE_STAMP 20U
#define NF_DEVELOP_STAGE_DEFECT_BRUSH 21U
#define NF_DEVELOP_STAGE_OUTPUT_SHARPENING 22U

#define NF_OUTPUT_SHARPENING_SCREEN 0U
#define NF_OUTPUT_SHARPENING_MATTE_PAPER 1U
#define NF_OUTPUT_SHARPENING_GLOSSY_PAPER 2U

#define NF_DEVELOP_TARGET_MAIN 0U
#define NF_DEVELOP_TARGET_PRINT 1U
#define NF_DEVELOP_TARGET_NORITSU 2U
#define NF_DEVELOP_TARGET_SP3000 3U
#define NF_DEVELOP_TARGET_F135 4U
#define NF_DEVELOP_TARGET_HR 5U
#define NF_DEVELOP_TARGET_RESCUE 6U

#define NF_FILM_SCAN_DENOISE_COLOR_NEGATIVE 0U
#define NF_FILM_SCAN_DENOISE_COLOR_POSITIVE 1U
#define NF_FILM_SCAN_DENOISE_BLACK_AND_WHITE_NEGATIVE 2U
#define NF_FILM_SCAN_DENOISE_BLACK_AND_WHITE_POSITIVE 3U

#define NF_FAILURE_NAME_CAPACITY 64U
#define NF_POINT_CURVE_MAX_POINTS 64U

/* Paths are UTF-16 and must stay valid for the duration of the call. The struct
   carries no ownership: the callee copies everything it needs before returning. */
typedef struct nf_develop_export_request_v1 {
    uint32_t struct_size;
    const wchar_t* source_path;
    const wchar_t* destination_path;
    uint32_t output_format;
    uint32_t film_type;
    float dmin[3];
    float exposure_stops;
    float contrast;
    float highlights;
    float lights;
    float darks;
    float shadows;
    uint32_t film_look_source_kind;
    uint32_t film_emulation;
    double film_emulation_intensity;
    uint32_t rows_per_copy;
} nf_develop_export_request_v1;

/* v1 stays frozen. v2 makes the base decision explicit so an Auto recipe never
   masquerades as a manual Dmin request. */
typedef struct nf_develop_export_request_v2 {
    uint32_t struct_size;
    const wchar_t* source_path;
    const wchar_t* destination_path;
    uint32_t output_format;
    uint32_t film_type;
    uint32_t base_estimation_mode;
    float dmin[3];
    float exposure_stops;
    float contrast;
    float highlights;
    float lights;
    float darks;
    float shadows;
    uint32_t film_look_source_kind;
    uint32_t film_emulation;
    double film_emulation_intensity;
    uint32_t rows_per_copy;
} nf_develop_export_request_v2;

/* v3 keeps the v2 prefix frozen and appends the five Basic Tone controls.  The
   existing highlights/lights/darks/shadows fields remain the parametric Tone Curve;
   Basic Tone has distinct semantic fields and must not reinterpret that prefix. */
typedef struct nf_develop_export_request_v3 {
    uint32_t struct_size;
    const wchar_t* source_path;
    const wchar_t* destination_path;
    uint32_t output_format;
    uint32_t film_type;
    uint32_t base_estimation_mode;
    float dmin[3];
    float exposure_stops;
    float contrast;
    float highlights;
    float lights;
    float darks;
    float shadows;
    uint32_t film_look_source_kind;
    uint32_t film_emulation;
    double film_emulation_intensity;
    uint32_t rows_per_copy;
    float density;
    float highlight;
    float shadow;
    float whites;
    float blacks;
} nf_develop_export_request_v3;

/* v4 preserves the v3 prefix and supplies the two Film-mode identifiers. They are
   UTF-16, must remain valid for the duration of the call, and are copied/resolved by
   the native side before it returns. A null light-source identifier means no trim. */
typedef struct nf_develop_export_request_v4 {
    uint32_t struct_size;
    const wchar_t* source_path;
    const wchar_t* destination_path;
    uint32_t output_format;
    uint32_t film_type;
    uint32_t base_estimation_mode;
    float dmin[3];
    float exposure_stops;
    float contrast;
    float highlights;
    float lights;
    float darks;
    float shadows;
    uint32_t film_look_source_kind;
    uint32_t film_emulation;
    double film_emulation_intensity;
    uint32_t rows_per_copy;
    float density;
    float highlight;
    float shadow;
    float whites;
    float blacks;
    const wchar_t* film_stock_dmin_id;
    const wchar_t* light_source_profile_id;
} nf_develop_export_request_v4;

/* Point curves are carried inline so a request has one lifetime boundary. Empty
   channels mean identity. `reserved` must be zero and makes a future extension
   explicit instead of silently reinterpreting caller bytes. */
typedef struct nf_point_curve_point_v1 {
    double x;
    double y;
} nf_point_curve_point_v1;

typedef struct nf_point_curve_v1 {
    uint32_t point_count;
    uint32_t reserved;
    nf_point_curve_point_v1 points[NF_POINT_CURVE_MAX_POINTS];
} nf_point_curve_v1;

/* v5 preserves the v4 prefix and appends the four macOS point-curve channels.
   The ABI owns no point memory outside the request, so preview and export receive
   the same immutable recipe. */
typedef struct nf_develop_export_request_v5 {
    uint32_t struct_size;
    const wchar_t* source_path;
    const wchar_t* destination_path;
    uint32_t output_format;
    uint32_t film_type;
    uint32_t base_estimation_mode;
    float dmin[3];
    float exposure_stops;
    float contrast;
    float highlights;
    float lights;
    float darks;
    float shadows;
    uint32_t film_look_source_kind;
    uint32_t film_emulation;
    double film_emulation_intensity;
    uint32_t rows_per_copy;
    float density;
    float highlight;
    float shadow;
    float whites;
    float blacks;
    const wchar_t* film_stock_dmin_id;
    const wchar_t* light_source_profile_id;
    nf_point_curve_v1 point_curve_rgb;
    nf_point_curve_v1 point_curve_red;
    nf_point_curve_v1 point_curve_green;
    nf_point_curve_v1 point_curve_blue;
} nf_develop_export_request_v5;

/* v6 preserves the v5 prefix and appends the eight HSL Color Mixer bands. */
typedef struct nf_develop_export_request_v6 {
    uint32_t struct_size;
    const wchar_t* source_path;
    const wchar_t* destination_path;
    uint32_t output_format;
    uint32_t film_type;
    uint32_t base_estimation_mode;
    float dmin[3];
    float exposure_stops;
    float contrast;
    float highlights;
    float lights;
    float darks;
    float shadows;
    uint32_t film_look_source_kind;
    uint32_t film_emulation;
    double film_emulation_intensity;
    uint32_t rows_per_copy;
    float density;
    float highlight;
    float shadow;
    float whites;
    float blacks;
    const wchar_t* film_stock_dmin_id;
    const wchar_t* light_source_profile_id;
    nf_point_curve_v1 point_curve_rgb;
    nf_point_curve_v1 point_curve_red;
    nf_point_curve_v1 point_curve_green;
    nf_point_curve_v1 point_curve_blue;
    float color_mixer_hue[8];
    float color_mixer_saturation[8];
    float color_mixer_luminance[8];
} nf_develop_export_request_v6;

/* v7 preserves the v6 prefix and appends the three Color Grading regions plus
   common blending and balance. Hue is in degrees; all remaining values are
   normalized floats. */
typedef struct nf_develop_export_request_v7 {
    uint32_t struct_size;
    const wchar_t* source_path;
    const wchar_t* destination_path;
    uint32_t output_format;
    uint32_t film_type;
    uint32_t base_estimation_mode;
    float dmin[3];
    float exposure_stops;
    float contrast;
    float highlights;
    float lights;
    float darks;
    float shadows;
    uint32_t film_look_source_kind;
    uint32_t film_emulation;
    double film_emulation_intensity;
    uint32_t rows_per_copy;
    float density;
    float highlight;
    float shadow;
    float whites;
    float blacks;
    const wchar_t* film_stock_dmin_id;
    const wchar_t* light_source_profile_id;
    nf_point_curve_v1 point_curve_rgb;
    nf_point_curve_v1 point_curve_red;
    nf_point_curve_v1 point_curve_green;
    nf_point_curve_v1 point_curve_blue;
    float color_mixer_hue[8];
    float color_mixer_saturation[8];
    float color_mixer_luminance[8];
    float color_grading_shadows_hue;
    float color_grading_shadows_saturation;
    float color_grading_shadows_luminance;
    float color_grading_midtones_hue;
    float color_grading_midtones_saturation;
    float color_grading_midtones_luminance;
    float color_grading_highlights_hue;
    float color_grading_highlights_saturation;
    float color_grading_highlights_luminance;
    float color_grading_blending;
    float color_grading_balance;
} nf_develop_export_request_v7;

/* v8 preserves the v7 prefix and appends macOS DevelopParameters.defectRemoval.
   Zero is identity; finite values from zero through one are accepted. */
typedef struct nf_develop_export_request_v8 {
    uint32_t struct_size;
    const wchar_t* source_path;
    const wchar_t* destination_path;
    uint32_t output_format;
    uint32_t film_type;
    uint32_t base_estimation_mode;
    float dmin[3];
    float exposure_stops;
    float contrast;
    float highlights;
    float lights;
    float darks;
    float shadows;
    uint32_t film_look_source_kind;
    uint32_t film_emulation;
    double film_emulation_intensity;
    uint32_t rows_per_copy;
    float density;
    float highlight;
    float shadow;
    float whites;
    float blacks;
    const wchar_t* film_stock_dmin_id;
    const wchar_t* light_source_profile_id;
    nf_point_curve_v1 point_curve_rgb;
    nf_point_curve_v1 point_curve_red;
    nf_point_curve_v1 point_curve_green;
    nf_point_curve_v1 point_curve_blue;
    float color_mixer_hue[8];
    float color_mixer_saturation[8];
    float color_mixer_luminance[8];
    float color_grading_shadows_hue;
    float color_grading_shadows_saturation;
    float color_grading_shadows_luminance;
    float color_grading_midtones_hue;
    float color_grading_midtones_saturation;
    float color_grading_midtones_luminance;
    float color_grading_highlights_hue;
    float color_grading_highlights_saturation;
    float color_grading_highlights_luminance;
    float color_grading_blending;
    float color_grading_balance;
    double defect_removal_strength;
} nf_develop_export_request_v8;

/* v9 preserves the complete v8 byte prefix and appends the macOS
   FilmScanDenoise master, five axes, and explicit four-way film profile.
   All controls are finite normalized floats. */
typedef struct nf_develop_export_request_v9 {
    nf_develop_export_request_v8 v8;
    float noise_reduction_strength;
    float noise_reduction_luma;
    float noise_reduction_chroma;
    float noise_reduction_dark_tone;
    float noise_reduction_detail;
    float noise_reduction_grain_protect;
    uint32_t noise_reduction_film_profile;
} nf_develop_export_request_v9;

/* v10 preserves the v9 prefix and appends the macOS Texture controls. Grain,
   sharpness and halation are 0...1; clarity and vignette are -1...1. */
typedef struct nf_develop_export_request_v10 {
    nf_develop_export_request_v9 v9;
    float texture_grain;
    float texture_sharpness;
    float texture_halation;
    float texture_clarity;
    float texture_vignette;
} nf_develop_export_request_v10;

/* v11 preserves the v10 prefix and appends the fixed macOS B&W toning and
   final ImageTransform recipe. Crop coordinates are normalized y-up. */
typedef struct nf_develop_export_request_v11 {
    nf_develop_export_request_v10 v10;
    uint32_t bw_toning_mode;
    double bw_toning_shadow_hue;
    double bw_toning_highlight_hue;
    double bw_toning_strength;
    uint32_t image_rotation;
    uint32_t flip_horizontal;
    uint32_t flip_vertical;
    uint32_t has_crop;
    double crop_x;
    double crop_y;
    double crop_width;
    double crop_height;
    double straighten_angle;
} nf_develop_export_request_v11;

/* Local Dodge/Burn uses a flat, caller-owned payload because masks contain
   variable-length stroke and point arrays. All pointers remain valid only for
   the synchronous call; the engine copies the recipe before processing. */
#define NF_LOCAL_DODGE_BURN_MAX_ADJUSTMENTS 64U
#define NF_LOCAL_DODGE_BURN_MAX_STROKES 8192U
#define NF_LOCAL_DODGE_BURN_MAX_POINTS 4096U

#define NF_LOCAL_DODGE_BURN_MODE_DODGE 0U
#define NF_LOCAL_DODGE_BURN_MODE_BURN 1U

#define NF_LOCAL_DODGE_BURN_MASK_BRUSH 0U
#define NF_LOCAL_DODGE_BURN_MASK_RADIAL 1U
#define NF_LOCAL_DODGE_BURN_MASK_LINEAR 2U
#define NF_LOCAL_DODGE_BURN_MASK_POLYGON 3U

typedef struct nf_local_dodge_burn_point_v1 {
    float x;
    float y;
} nf_local_dodge_burn_point_v1;

typedef struct nf_local_dodge_burn_stroke_v1 {
    uint32_t point_offset;
    uint32_t point_count;
    float thickness;
    float feather;
} nf_local_dodge_burn_stroke_v1;

typedef struct nf_local_dodge_burn_adjustment_v1 {
    uint32_t mode;
    uint32_t enabled;
    uint32_t mask_kind;
    uint32_t stroke_offset;
    uint32_t stroke_count;
    uint32_t point_offset;
    uint32_t point_count;
    float amount;
    float center_x;
    float center_y;
    float radius;
    float feather;
    float start_x;
    float start_y;
    float end_x;
    float end_y;
} nf_local_dodge_burn_adjustment_v1;

/* v12 preserves the v11 prefix and appends the variable Local Dodge/Burn
   recipe. Reserved fields must be zero. */
typedef struct nf_develop_export_request_v12 {
    nf_develop_export_request_v11 v11;
    const nf_local_dodge_burn_adjustment_v1* local_adjustments;
    uint32_t local_adjustment_count;
    uint32_t local_adjustment_reserved;
    const nf_local_dodge_burn_stroke_v1* local_strokes;
    uint32_t local_stroke_count;
    uint32_t local_stroke_reserved;
    const nf_local_dodge_burn_point_v1* local_points;
    uint32_t local_point_count;
    uint32_t local_point_reserved;
} nf_develop_export_request_v12;

/* v13 preserves the complete v12 prefix and appends the fixed macOS
   ColorModel controls in their stored -1...1 slider domain. */
typedef struct nf_develop_export_request_v13 {
    nf_develop_export_request_v12 v12;
    float warmth;
    float tint;
    float color_depth;
    float vibrance;
    float saturation;
    float red_primary;
    float green_primary;
    float blue_primary;
} nf_develop_export_request_v13;

/* v14 preserves the complete v13 prefix and appends the two opt-in macOS
   scene-adaptive correction flags. Values must be zero or one. */
typedef struct nf_develop_export_request_v14 {
    nf_develop_export_request_v13 v13;
    uint32_t auto_levels;
    uint32_t auto_neutral_balance;
} nf_develop_export_request_v14;

/* v15 preserves the complete v14 prefix and appends the macOS DevelopTarget.
   reserved must be zero. */
typedef struct nf_develop_export_request_v15 {
    nf_develop_export_request_v14 v14;
    uint32_t develop_target;
    uint32_t reserved;
} nf_develop_export_request_v15;

/* v16 preserves the complete v15 prefix and appends the optional immutable
   scanner profile identifier. UTF-16 storage remains caller-owned for the
   synchronous call. A null pointer means no scanner profile grade. */
typedef struct nf_develop_export_request_v16 {
    nf_develop_export_request_v15 v15;
    const wchar_t* scanner_profile_id;
} nf_develop_export_request_v16;

/* v17 preserves the complete v16 prefix and appends film polarity separately
   from the Color/B&W axis. reserved must be zero. */
typedef struct nf_develop_export_request_v17 {
    nf_develop_export_request_v16 v16;
    uint32_t film_polarity;
    uint32_t reserved;
} nf_develop_export_request_v17;

/* The mask bytes for each edit are ROI-local, one byte per pixel, first row at
   the top. ROI y is bottom-origin in raw-image pixels, matching the fixed macOS
   recipe. The edit list is applied in order before negative development. */
#define NF_DEFECT_REGION_MAX_EDITS 4096U
#define NF_DEFECT_REGION_MAX_MASK_BYTES (512U * 1024U * 1024U)

typedef struct nf_defect_region_edit_v1 {
    uint32_t enabled;
    uint32_t roi_x;
    uint32_t roi_y;
    uint32_t width;
    uint32_t height;
    uint32_t mask_stride_bytes;
    uint32_t mask_offset;
    uint32_t mask_byte_count;
    double strength;
    uint32_t has_preferred_angle;
    uint32_t reserved;
    double preferred_angle_degrees;
} nf_defect_region_edit_v1;

/* v18 preserves the complete v17 prefix. Descriptor and flat mask storage stay
   caller-owned for the synchronous preview/export call. Reserved fields are zero. */
typedef struct nf_develop_export_request_v18 {
    nf_develop_export_request_v17 v17;
    const nf_defect_region_edit_v1* defect_region_edits;
    uint32_t defect_region_edit_count;
    uint32_t defect_region_reserved;
    const uint8_t* defect_mask_bytes;
    uint32_t defect_mask_byte_count;
    uint32_t defect_mask_reserved;
} nf_develop_export_request_v18;

/* v19 binds a non-empty defect-region recipe to the exact source bytes. The
   digest points to exactly 32 caller-owned bytes for the synchronous call. A
   request without region edits must leave all appended fields zero/null. */
typedef struct nf_develop_export_request_v19 {
    nf_develop_export_request_v18 v18;
    uint64_t defect_source_file_bytes;
    const uint8_t* defect_source_sha256;
    uint32_t has_defect_source_identity;
    uint32_t reserved;
} nf_develop_export_request_v19;

#define NF_DEFECT_CLONE_MAX_EDITS 4096U
#define NF_DEFECT_CLONE_MAX_STROKES 100000U
#define NF_DEFECT_CLONE_MAX_POINTS 5000000U
#define NF_DEFECT_RECIPE_MAX_ORDERED_EDITS 8192U

#define NF_DEFECT_RECIPE_EDIT_REGION 0U
#define NF_DEFECT_RECIPE_EDIT_CLONE 1U
#define NF_DEFECT_RECIPE_EDIT_BRUSH 2U

typedef struct nf_defect_clone_point_v1 {
    double x;
    double y;
} nf_defect_clone_point_v1;

typedef struct nf_defect_clone_stroke_v1 {
    uint32_t point_offset;
    uint32_t point_count;
    double offset_x;
    double offset_y;
    double diameter_pixels;
    double hardness;
} nf_defect_clone_stroke_v1;

typedef struct nf_defect_clone_edit_v1 {
    uint32_t enabled;
    uint32_t stroke_offset;
    uint32_t stroke_count;
    uint32_t reserved;
    double strength;
} nf_defect_clone_edit_v1;

typedef struct nf_defect_recipe_edit_ref_v1 {
    uint32_t kind;
    uint32_t index;
} nf_defect_recipe_edit_ref_v1;

/* v20 preserves the complete v19 prefix and appends Clone Stamp layers plus
   one order list covering every region and clone descriptor exactly once.
   Points are normalized raw-image coordinates with a top-left origin. */
typedef struct nf_develop_export_request_v20 {
    nf_develop_export_request_v19 v19;
    const nf_defect_clone_edit_v1* defect_clone_edits;
    uint32_t defect_clone_edit_count;
    uint32_t defect_clone_edit_reserved;
    const nf_defect_clone_stroke_v1* defect_clone_strokes;
    uint32_t defect_clone_stroke_count;
    uint32_t defect_clone_stroke_reserved;
    const nf_defect_clone_point_v1* defect_clone_points;
    uint32_t defect_clone_point_count;
    uint32_t defect_clone_point_reserved;
    const nf_defect_recipe_edit_ref_v1* defect_edit_order;
    uint32_t defect_edit_order_count;
    uint32_t defect_edit_order_reserved;
} nf_develop_export_request_v20;

#define NF_DEFECT_BRUSH_MAX_EDITS 4096U
#define NF_DEFECT_BRUSH_MAX_STROKES 100000U
#define NF_DEFECT_BRUSH_MAX_POINTS 5000000U

typedef struct nf_defect_brush_point_v1 {
    double x;
    double y;
} nf_defect_brush_point_v1;

typedef struct nf_defect_brush_stroke_v1 {
    uint32_t point_offset;
    uint32_t point_count;
    double thickness;
} nf_defect_brush_stroke_v1;

typedef struct nf_defect_brush_edit_v1 {
    uint32_t enabled;
    uint32_t stroke_offset;
    uint32_t stroke_count;
    uint32_t reserved;
    double strength;
} nf_defect_brush_edit_v1;

/* v21 preserves the complete v20 prefix and appends raw-image Brush layers.
   Points use normalized top-left coordinates and thickness is a fraction of
   the raw image's shorter dimension. The v20 order list covers region, clone,
   and brush descriptors exactly once. */
typedef struct nf_develop_export_request_v21 {
    nf_develop_export_request_v20 v20;
    const nf_defect_brush_edit_v1* defect_brush_edits;
    uint32_t defect_brush_edit_count;
    uint32_t defect_brush_edit_reserved;
    const nf_defect_brush_stroke_v1* defect_brush_strokes;
    uint32_t defect_brush_stroke_count;
    uint32_t defect_brush_stroke_reserved;
    const nf_defect_brush_point_v1* defect_brush_points;
    uint32_t defect_brush_point_count;
    uint32_t defect_brush_point_reserved;
} nf_develop_export_request_v21;

#define NF_DEFECT_INFRARED_MAX_EDITS 4096U
#define NF_DEFECT_INFRARED_MAX_ATTENUATION_BYTES (512U * 1024U * 1024U)

/* An infrared descriptor turns one v21 region descriptor into a distinct IR
   edit. The referenced region supplies ROI, top-first one-byte core mask, and
   strength. attenuation is optional ROI-local top-first little-endian R16. */
typedef struct nf_defect_infrared_edit_v1 {
    uint32_t region_edit_index;
    uint32_t has_attenuation;
    uint32_t attenuation_stride_bytes;
    uint32_t attenuation_offset;
    uint32_t attenuation_byte_count;
    uint32_t reserved;
} nf_defect_infrared_edit_v1;

/* v24 preserves the complete v21 prefix and appends IR descriptors plus their
   caller-owned flat attenuation storage. v22/v23 changed call controls only,
   so v24 is the next request-bearing entry point. */
typedef struct nf_develop_export_request_v24 {
    nf_develop_export_request_v21 v21;
    const nf_defect_infrared_edit_v1* defect_infrared_edits;
    uint32_t defect_infrared_edit_count;
    uint32_t defect_infrared_edit_reserved;
    const uint8_t* defect_infrared_attenuation_bytes;
    uint32_t defect_infrared_attenuation_byte_count;
    uint32_t defect_infrared_attenuation_reserved;
} nf_develop_export_request_v24;

/* Groups a contiguous v24 infrared-cluster range into one ordered edit item.
   Every cluster is computed from the same item-level input image. */
typedef struct nf_defect_infrared_item_v1 {
    uint32_t cluster_offset;
    uint32_t cluster_count;
    uint32_t reserved_0;
    uint32_t reserved_1;
} nf_defect_infrared_item_v1;

typedef struct nf_develop_export_request_v25 {
    nf_develop_export_request_v24 v24;
    const nf_defect_infrared_item_v1* defect_infrared_items;
    uint32_t defect_infrared_item_count;
    uint32_t defect_infrared_item_reserved;
} nf_develop_export_request_v25;

/* Output sharpening is a final, output-space operation. It follows image transform
   and is never stored in the develop recipe. dpi 0 selects the medium reference DPI. */
typedef struct nf_develop_export_request_v26 {
    nf_develop_export_request_v25 v25;
    float output_sharpening_strength;
    uint32_t output_sharpening_medium;
    int32_t output_sharpening_dpi;
    uint32_t output_sharpening_reserved;
} nf_develop_export_request_v26;

typedef struct nf_develop_export_result_v1 {
    uint32_t struct_size;
    uint32_t succeeded;
    uint32_t failed_stage;
    /* NUL-terminated ASCII, always written. Fixed size so the caller owns no
       memory and the ABI needs no free function. */
    char failure_name[NF_FAILURE_NAME_CAPACITY];
    uint32_t native_error_code;
    uint32_t cleanup_error_code;
    uint32_t image_width;
    uint32_t image_height;
    uint32_t film_look_route;
    uint32_t film_look_color_applied;
    uint32_t film_look_acutance_applied;
    uint64_t source_file_bytes;
    uint64_t output_file_bytes;
    uint64_t film_look_workspace_bytes;
    uint64_t wall_microseconds;
} nf_develop_export_result_v1;

typedef struct nf_develop_export_result_v2 {
    uint32_t struct_size;
    uint32_t succeeded;
    uint32_t failed_stage;
    char failure_name[NF_FAILURE_NAME_CAPACITY];
    uint32_t native_error_code;
    uint32_t cleanup_error_code;
    uint32_t image_width;
    uint32_t image_height;
    uint32_t film_look_route;
    uint32_t film_look_color_applied;
    uint32_t film_look_acutance_applied;
    uint64_t source_file_bytes;
    uint64_t output_file_bytes;
    uint64_t film_look_workspace_bytes;
    uint64_t wall_microseconds;
    float applied_dmin[3];
    uint32_t base_source;
} nf_develop_export_result_v2;

/* v3 keeps every v2 field at the same offset and appends the cancellation answer.
   `cancelled` is 1 when the caller's run state ended the call; `failed_stage` then names
   the stage that was interrupted and `failure_name` is "cancelled". A cancelled call
   publishes nothing — no destination file, no preview pixels. */
typedef struct nf_develop_export_result_v3 {
    uint32_t struct_size;
    uint32_t succeeded;
    uint32_t failed_stage;
    char failure_name[NF_FAILURE_NAME_CAPACITY];
    uint32_t native_error_code;
    uint32_t cleanup_error_code;
    uint32_t image_width;
    uint32_t image_height;
    uint32_t film_look_route;
    uint32_t film_look_color_applied;
    uint32_t film_look_acutance_applied;
    uint64_t source_file_bytes;
    uint64_t output_file_bytes;
    uint64_t film_look_workspace_bytes;
    uint64_t wall_microseconds;
    float applied_dmin[3];
    uint32_t base_source;
    uint32_t cancelled;
    uint32_t reserved;
} nf_develop_export_result_v3;

#define NF_DEVELOP_PROGRESS_COMPLETE 1000U

/* Shared, caller-owned run state for one develop call.
   The caller writes `cancel_requested` (any non-zero value) at any time from any thread;
   the engine only reads it. The engine writes `stage` and `progress_permille` as the run
   advances, and the caller polls them on its own timer. Nothing crosses the boundary as a
   callback, so there is no reentrancy to reason about and nothing to keep alive but this
   struct — which must stay pinned and alive for the whole call.

   Cancellation is cooperative and checked between stages, inside the TIFF decode per row
   chunk, and inside the optional source hash. It is deliberately not checked once the
   output stage has begun, so a cancel never leaves a partly written file behind.

   The progress figure is an estimate weighted by which stages this request will actually
   run. It never moves backwards and reaches NF_DEVELOP_PROGRESS_COMPLETE only on success. */
typedef struct nf_develop_run_state_v1 {
    uint32_t struct_size;
    uint32_t cancel_requested;
    uint32_t stage;
    uint32_t progress_permille;
} nf_develop_run_state_v1;

/* Automatic develop settings for one frame.
   These are values to **assign** to the recipe, not deltas to add: running auto twice
   gives the same answer as running it once. Every field is already inside the range the
   engine accepts, so a caller never has to clamp. */
typedef struct nf_auto_adjust_result_v1 {
    uint32_t struct_size;
    uint32_t reserved;
    double exposure;
    double contrast;
    double highlights;
    double shadows;
    double whites;
    double blacks;
    double density;
    double vibrance;
    double warmth;
    double tint;
} nf_auto_adjust_result_v1;

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
} nf_flatbed_frame_detection_v1;

typedef struct nf_flatbed_frame_grid_handle_v1 nf_flatbed_frame_grid_handle_v1;

/* What a destination profile turned out to be, and the paper and ink it describes.

   Reading a profile means walking its tag table, so it happens once when the profile is
   chosen rather than once per frame: the caller keeps these ten numbers and hands them to
   every preview. `is_rgb_output_profile` is the same gate the choice itself must pass — a
   CMYK press profile or a scanner-only profile cannot be rendered into and is refused
   here, before it can reach the pixel path. */
typedef struct nf_soft_proof_media_v1 {
    uint32_t struct_size;
    uint32_t is_rgb_output_profile;
    uint32_t has_white;
    uint32_t has_black;
    float paper_white_rgb[3];
    float black_ink_rgb[3];
} nf_soft_proof_media_v1;

/* Soft proof rides alongside the preview instead of inside the develop request, because
   it is a viewing simulation and not part of the recipe. Keeping it out of the request is
   what makes it impossible for a published file to carry it: export has no field to read.

   `simulate_paper_and_black_ink` is the only mode that changes pixel values. Profile-only
   proofing changes which space the frame is shown in, which is the caller's business. */
typedef struct nf_soft_proof_v1 {
    uint32_t struct_size;
    uint32_t enabled;
    uint32_t simulate_paper_and_black_ink;
    uint32_t reserved;
    float paper_white_rgb[3];
    float black_ink_rgb[3];
} nf_soft_proof_v1;

/* The bounds the engine's own validator enforces. Exported so a UI does not have to
   duplicate them and cannot drift into offering values the engine will refuse. */
typedef struct nf_tone_limits_v1 {
    uint32_t struct_size;
    float maximum_exposure_stops;
    float maximum_tone_control;
    double minimum_film_emulation_intensity;
    double maximum_film_emulation_intensity;
} nf_tone_limits_v1;

/* The range a manual film base is clamped into. A UI that guesses these offers a value
   the engine silently moves, which is harder to notice than a refusal. */
typedef struct nf_negative_limits_v1 {
    uint32_t struct_size;
    float minimum_manual_dmin;
    float maximum_manual_dmin;
} nf_negative_limits_v1;

NF_API uint32_t NF_CALL nf_get_abi_version(void);
NF_API nf_status_t NF_CALL nf_get_build_info_v1(nf_build_info_v1* output);

/* Blocking. Safe to call from a worker thread; touches no UI and no global state.
   Returns NF_STATUS_OK when the call was well formed, which is not the same as the
   develop succeeding — read result->succeeded for that. */
NF_API nf_status_t NF_CALL nf_develop_export_v1(
    const nf_develop_export_request_v1* request,
    nf_develop_export_result_v1* result);

NF_API nf_status_t NF_CALL nf_develop_export_v2(
    const nf_develop_export_request_v2* request,
    nf_develop_export_result_v2* result);

NF_API nf_status_t NF_CALL nf_develop_export_v3(
    const nf_develop_export_request_v3* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v4(
    const nf_develop_export_request_v4* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v5(
    const nf_develop_export_request_v5* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v6(
    const nf_develop_export_request_v6* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v7(
    const nf_develop_export_request_v7* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v8(
    const nf_develop_export_request_v8* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v9(
    const nf_develop_export_request_v9* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v10(
    const nf_develop_export_request_v10* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v11(
    const nf_develop_export_request_v11* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v12(
    const nf_develop_export_request_v12* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v13(
    const nf_develop_export_request_v13* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v14(
    const nf_develop_export_request_v14* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v15(
    const nf_develop_export_request_v15* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v16(
    const nf_develop_export_request_v16* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v17(
    const nf_develop_export_request_v17* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v18(
    const nf_develop_export_request_v18* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v19(
    const nf_develop_export_request_v19* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v20(
    const nf_develop_export_request_v20* request,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_export_v21(
    const nf_develop_export_request_v21* request,
    nf_develop_export_result_v2* result);

NF_API nf_status_t NF_CALL nf_get_tone_limits_v1(nf_tone_limits_v1* output);

/* Same pipeline as nf_develop_export_v1 but stops before publishing and fills `pixels`
   with a BGRA8 display bitmap, tightly packed, opaque alpha, at most the requested size
   with aspect preserved. `destination_path` is ignored. The written size comes back as
   result->image_width and result->image_height. Blocking; safe on a worker thread. */
NF_API nf_status_t NF_CALL nf_develop_preview_v1(
    const nf_develop_export_request_v1* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v1* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v2(
    const nf_develop_export_request_v2* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v3(
    const nf_develop_export_request_v3* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v4(
    const nf_develop_export_request_v4* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v5(
    const nf_develop_export_request_v5* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v6(
    const nf_develop_export_request_v6* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v7(
    const nf_develop_export_request_v7* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v8(
    const nf_develop_export_request_v8* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v9(
    const nf_develop_export_request_v9* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v10(
    const nf_develop_export_request_v10* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v11(
    const nf_develop_export_request_v11* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v12(
    const nf_develop_export_request_v12* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v13(
    const nf_develop_export_request_v13* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v14(
    const nf_develop_export_request_v14* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v15(
    const nf_develop_export_request_v15* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v16(
    const nf_develop_export_request_v16* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v17(
    const nf_develop_export_request_v17* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v18(
    const nf_develop_export_request_v18* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v19(
    const nf_develop_export_request_v19* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v20(
    const nf_develop_export_request_v20* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v21(
    const nf_develop_export_request_v21* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* result);

/* v22 runs the same recipe as v21 — the develop request did not change, so it keeps the
   v21 struct rather than minting an identical copy. What changed is that the caller can
   now steer the call: `run_state` may be null for the old blocking behaviour, or point at
   a pinned nf_develop_run_state_v1 to cancel the run and watch it advance. The result is
   v3 so cancellation is a field rather than a string comparison. */
NF_API nf_status_t NF_CALL nf_develop_export_v22(
    const nf_develop_export_request_v21* request,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v22(
    const nf_develop_export_request_v21* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
/* Reads a neutral develop — the tone sliders at zero, the frame otherwise properly
   rendered — and returns the settings automatic adjustment would assign.

   The bitmap is BGRA8, exactly what nf_develop_preview_v22 writes, so the caller renders
   a preview it already knows how to render and hands the same buffer straight here. No
   pixels are modified and nothing is retained after the call returns.

   Feeding it a badly rendered frame is not an error and will not be reported as one: auto
   will simply propose its limits in every direction, which is the correct answer for an
   image that far from right. */
NF_API nf_status_t NF_CALL nf_auto_adjust_v1(
    const uint8_t* pixels,
    uint32_t width,
    uint32_t height,
    uint32_t stride_bytes,
    nf_auto_adjust_result_v1* result);
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
NF_API nf_status_t NF_CALL nf_flatbed_frame_grid_get_detection_v1(
    const nf_flatbed_frame_grid_handle_v1* handle,
    uint64_t index,
    nf_flatbed_frame_detection_v1* detection);
NF_API void NF_CALL nf_flatbed_frame_grid_destroy_v1(
    nf_flatbed_frame_grid_handle_v1* handle);
/* v23 is v22 plus a soft proof the caller may pass as null for an unproofed preview.
   There is no matching export entry point and there will not be one: soft proof is a
   viewing simulation, and a published artefact that carried it would be wrong.

   The develop request is still v21 — the recipe did not change, so no copy was minted. */
NF_API nf_status_t NF_CALL nf_develop_preview_v23(
    const nf_develop_export_request_v21* request,
    const nf_soft_proof_v1* soft_proof,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);

/* v24 replays optional IR attenuation before the referenced core repair. Both
   calls use the same request mapping and pre-develop native stage. */
NF_API nf_status_t NF_CALL nf_develop_export_v24(
    const nf_develop_export_request_v24* request,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v24(
    const nf_develop_export_request_v24* request,
    const nf_soft_proof_v1* soft_proof,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);

/* v25 preserves IR edit-item boundaries while retaining the v24 cluster ABI. */
NF_API nf_status_t NF_CALL nf_develop_export_v25(
    const nf_develop_export_request_v25* request,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v25(
    const nf_develop_export_request_v25* request,
    const nf_soft_proof_v1* soft_proof,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);

NF_API nf_status_t NF_CALL nf_develop_export_v26(
    const nf_develop_export_request_v26* request,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v26(
    const nf_develop_export_request_v26* request,
    const nf_soft_proof_v1* soft_proof,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);

/* Reads `wtpt` and `bkpt` out of an ICC profile and reports whether it can serve as a
   proof destination at all. The bytes are read during the call and never retained. */
NF_API nf_status_t NF_CALL nf_read_soft_proof_media_v1(
    const uint8_t* icc_bytes,
    uint32_t icc_byte_count,
    nf_soft_proof_media_v1* result);

NF_API nf_status_t NF_CALL nf_get_negative_limits_v1(nf_negative_limits_v1* output);

#ifdef __cplusplus
}
#endif
