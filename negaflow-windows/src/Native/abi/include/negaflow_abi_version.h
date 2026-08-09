#pragma once

#include <stdint.h>

/* Minor rises when exports are added; major would rise on a breaking change.
   0.2 added nf_develop_export_v1, 0.3 nf_get_tone_limits_v1,
   0.4 nf_get_negative_limits_v1, 0.5 nf_develop_preview_v1, 0.6 base-mode v2
   preview/export, 0.8 expanded automatic base provenance, and 0.9 Basic Tone v3
   preview/export. The managed loader
   refuses anything below the minor it actually calls, so an older engine fails at load
   instead of at the first missing entry point. */
#define NF_ABI_VERSION_MAJOR 0U
#define NF_ABI_VERSION_MINOR 13U
#define NF_ABI_VERSION ((NF_ABI_VERSION_MAJOR << 16U) | NF_ABI_VERSION_MINOR)
