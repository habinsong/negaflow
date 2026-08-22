#pragma once

/* Develop export and preview entry points, v1 through v35. */

#include "negaflow/abi/develop_output.h"
#include "negaflow/abi/develop_result.h"
#include "negaflow/abi/soft_proof.h"

#ifdef __cplusplus
extern "C" {
#endif

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

NF_API nf_status_t NF_CALL nf_develop_export_v27(
    const nf_develop_export_request_v27* request,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v27(
    const nf_develop_export_request_v27* request,
    const nf_soft_proof_v1* soft_proof,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);

NF_API nf_status_t NF_CALL nf_develop_export_v28(
    const nf_develop_export_request_v28* request,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v28(
    const nf_develop_export_request_v28* request,
    const nf_soft_proof_v1* soft_proof,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);

NF_API nf_status_t NF_CALL nf_develop_export_v29(
    const nf_develop_export_request_v29* request,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v29(
    const nf_develop_export_request_v29* request,
    const nf_soft_proof_v1* soft_proof,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);

NF_API nf_status_t NF_CALL nf_develop_export_v30(
    const nf_develop_export_request_v30* request,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);

NF_API nf_status_t NF_CALL nf_develop_export_v31(
    const nf_develop_export_request_v31* request,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);

NF_API nf_status_t NF_CALL nf_develop_export_v32(
    const nf_develop_export_request_v32* request,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);

NF_API nf_status_t NF_CALL nf_develop_export_v33(
    const nf_develop_export_request_v33* request,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v33(
    const nf_develop_export_request_v33* request,
    const nf_soft_proof_v1* soft_proof,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_export_v34(
    const nf_develop_export_request_v34* request,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v34(
    const nf_develop_export_request_v34* request,
    const nf_soft_proof_v1* soft_proof,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_export_v35(
    const nf_develop_export_request_v35* request,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v35(
    const nf_develop_export_request_v35* request,
    const nf_soft_proof_v1* soft_proof,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
/* Builds the same BGRA preview as v35 without retaining its rebuildable Rgba32F raw
   proxy. This is for serialized background population of the persistent developed
   cache; foreground preview calls must continue to use nf_develop_preview_v35. */
NF_API nf_status_t NF_CALL nf_develop_preview_background_v1(
    const nf_develop_export_request_v35* request,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v32(
    const nf_develop_export_request_v32* request,
    const nf_soft_proof_v1* soft_proof,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v31(
    const nf_develop_export_request_v31* request,
    const nf_soft_proof_v1* soft_proof,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);
NF_API nf_status_t NF_CALL nf_develop_preview_v30(
    const nf_develop_export_request_v30* request,
    const nf_soft_proof_v1* soft_proof,
    uint32_t maximum_width,
    uint32_t maximum_height,
    uint8_t* pixels,
    uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result);

#ifdef __cplusplus
}
#endif
