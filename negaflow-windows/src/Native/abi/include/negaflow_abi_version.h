#pragma once

#include <stdint.h>

/* Minor rises when exports are added; major would rise on a breaking change.
   0.2 added nf_develop_export_v1, 0.3 nf_get_tone_limits_v1,
   0.4 nf_get_negative_limits_v1, 0.5 nf_develop_preview_v1, 0.6 base-mode v2
   preview/export, 0.8 expanded automatic base provenance, and 0.9 Basic Tone v3
   preview/export, 0.14 GrainMend strength v8 preview/export, and 0.15
   FilmScanDenoise v9 preview/export, 0.16 Texture v10 preview/export, and 0.17
   B&W toning plus ImageTransform v11 preview/export, 0.18 variable Local
   Dodge/Burn v12, ColorModel v13, scene-correction v14, 0.21 DevelopTarget v15,
   0.22 scanner profile ID v16, 0.23 explicit film polarity v17, and 0.24 bounded
   ordered defect-region edits v18, 0.25 source-bound defect recipes v19, and
   0.26 ordered Clone Stamp recipe transport v20, and 0.27 ordered Brush
   recipe transport v21, and 0.28 caller-owned run state v22 for cooperative
   cancellation and progress, and 0.29 automatic tone and white balance, and 0.30 soft
   proof on the preview only.
   The managed loader
   refuses anything below the minor it actually calls, so an older engine fails at load
   instead of at the first missing entry point. */
#define NF_ABI_VERSION_MAJOR 0U
#define NF_ABI_VERSION_MINOR 30U
#define NF_ABI_VERSION ((NF_ABI_VERSION_MAJOR << 16U) | NF_ABI_VERSION_MINOR)
