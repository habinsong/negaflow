#pragma once

/* Local Dodge/Burn: a flat, caller-owned mask payload with its own lifetime rules. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

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

#ifdef __cplusplus
}
#endif
