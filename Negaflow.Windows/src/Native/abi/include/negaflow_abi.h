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

NF_API uint32_t NF_CALL nf_get_abi_version(void);
NF_API nf_status_t NF_CALL nf_get_build_info_v1(nf_build_info_v1* output);

/* Blocking. Safe to call from a worker thread; touches no UI and no global state.
   Returns NF_STATUS_OK when the call was well formed, which is not the same as the
   develop succeeding — read result->succeeded for that. */
NF_API nf_status_t NF_CALL nf_develop_export_v1(
    const nf_develop_export_request_v1* request,
    nf_develop_export_result_v1* result);

#ifdef __cplusplus
}
#endif
