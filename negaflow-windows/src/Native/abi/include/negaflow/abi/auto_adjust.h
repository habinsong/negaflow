#pragma once

/* Automatic tone and white balance read off a rendered preview. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

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

#ifdef __cplusplus
}
#endif
