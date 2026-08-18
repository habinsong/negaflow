#pragma once

/* What a develop call answers with, and the caller-owned run state that steers it. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

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

#ifdef __cplusplus
}
#endif
