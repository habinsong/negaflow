#pragma once

/* Scene and target additions to the recipe - request v12 through v17. */

#include "negaflow/abi/develop_request_core.h"
#include "negaflow/abi/local_dodge_burn.h"

#ifdef __cplusplus
extern "C" {
#endif

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

#ifdef __cplusplus
}
#endif
