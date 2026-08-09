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

#define NF_FAILURE_NAME_CAPACITY 64U

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
NF_API nf_status_t NF_CALL nf_get_negative_limits_v1(nf_negative_limits_v1* output);

#ifdef __cplusplus
}
#endif
