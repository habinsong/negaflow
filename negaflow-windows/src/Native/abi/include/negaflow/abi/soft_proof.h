#pragma once

/* Soft proof media reading and the gamut-warning capability question. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

/* What a destination profile turned out to be, and the paper and ink it describes.

   Reading a profile means walking its tag table, so it happens once when the profile is
   chosen rather than once per frame: the caller keeps these ten numbers and hands them to
   every preview. `is_rgb_output_profile` is the same gate the choice itself must pass — a
   CMYK press profile or a scanner-only profile cannot be rendered into and is refused
   here, before it can reach the pixel path. */
typedef struct nf_soft_proof_media_v1 {
    uint32_t struct_size;
    uint32_t is_rgb_output_profile;
    uint32_t has_white;
    uint32_t has_black;
    float paper_white_rgb[3];
    float black_ink_rgb[3];
} nf_soft_proof_media_v1;

/* Soft proof rides alongside the preview instead of inside the develop request, because
   it is a viewing simulation and not part of the recipe. Keeping it out of the request is
   what makes it impossible for a published file to carry it: export has no field to read.

   `simulate_paper_and_black_ink` is the only mode that changes pixel values. Profile-only
   proofing changes which space the frame is shown in, which is the caller's business. */
typedef struct nf_soft_proof_v1 {
    uint32_t struct_size;
    uint32_t enabled;
    uint32_t simulate_paper_and_black_ink;
    /* Mark pixels the output space cannot reproduce. Judged by ICM; when ICM cannot build
       the transform nothing is marked, because an approximation would mark different
       pixels than macOS marks on the same picture. Took the reserved slot, so the layout
       is unchanged and an older caller that zeroed it simply gets no marking. */
    uint32_t warn_out_of_gamut;
    float paper_white_rgb[3];
    float black_ink_rgb[3];
    /* Preview-only clipping overlay (macOS clippingOverlayEnabled). Older callers
       that send the original 40-byte layout leave this off. */
    uint32_t clipping_overlay;
} nf_soft_proof_v1;

/* Reads `wtpt` and `bkpt` out of an ICC profile and reports whether it can serve as a
   proof destination at all. The bytes are read during the call and never retained. */
NF_API nf_status_t NF_CALL nf_read_soft_proof_media_v1(
    const uint8_t* icc_bytes,
    uint32_t icc_byte_count,
    nf_soft_proof_media_v1* result);

/* Can ICM judge out-of-gamut pixels for this output space? 0 sRGB, 1 Display P3,
   2 Adobe RGB. Writes 1 when it can and 0 when it cannot - the settings screen asks this
   before offering the gamut warning, because a warning that cannot be computed must not
   be offered. */
/* Marks which pixels the given ICC profile cannot reproduce.

   `pixels` is 8-bit BGRA in sRGB, `mask` is one byte per pixel: 0 inside the destination
   gamut, non-zero outside. Judged by ICM's real gamut-check transform, never approximated -
   an approximation would mark different pixels than macOS marks on the same picture.

   The destination has to be the lab's profile. Judging sRGB pixels against sRGB (or any
   wider space) can never find anything, so the warning would draw nothing at all. */
/* Runs the picture through the lab profile and back so the screen shows what that paper can
   reproduce. This is what profile-only proofing means: macOS changes the rendering colour
   space instead of the pixels, and on an sRGB screen the equivalent is a round trip.
   Leaves the pixels untouched when ICM cannot build the transform. */
NF_API nf_status_t NF_CALL nf_soft_proof_convert_bgra_icc_v1(
    uint8_t* pixels,
    uint32_t width,
    uint32_t height,
    uint32_t stride_bytes,
    const uint8_t* destination_icc,
    uint32_t destination_icc_size);

NF_API nf_status_t NF_CALL nf_gamut_check_mask_icc_v1(
    const uint8_t* pixels,
    uint32_t width,
    uint32_t height,
    uint32_t stride_bytes,
    const uint8_t* destination_icc,
    uint32_t destination_icc_size,
    uint8_t* mask,
    uint32_t mask_size);

NF_API nf_status_t NF_CALL nf_gamut_check_supported_v1(
    uint32_t output_color_space,
    uint32_t* supported);

#ifdef __cplusplus
}
#endif
