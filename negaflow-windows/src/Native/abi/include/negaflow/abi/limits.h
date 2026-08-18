#pragma once

/* The bounds the engine validator enforces, exported so a UI cannot drift out of them. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

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

NF_API nf_status_t NF_CALL nf_get_tone_limits_v1(nf_tone_limits_v1* output);

NF_API nf_status_t NF_CALL nf_get_negative_limits_v1(nf_negative_limits_v1* output);

#ifdef __cplusplus
}
#endif
