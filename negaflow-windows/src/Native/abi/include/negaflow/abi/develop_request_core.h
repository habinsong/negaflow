#pragma once

/* The develop recipe as first frozen - request v1 through v11, with point curves. */

#include "negaflow/abi/develop_enums.h"

#ifdef __cplusplus
extern "C" {
#endif

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

#ifdef __cplusplus
}
#endif
