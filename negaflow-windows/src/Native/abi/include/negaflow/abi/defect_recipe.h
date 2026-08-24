#pragma once

/* Defect edits carried with the recipe - region, Clone Stamp, Brush, infrared - v18 through v25. */

#include "negaflow/abi/develop_request_scene.h"

#ifdef __cplusplus
extern "C" {
#endif

/* The mask bytes for each edit are ROI-local, one byte per pixel, first row at
   the top. ROI y is bottom-origin in raw-image pixels, matching the fixed macOS
   recipe. The edit list is applied in order before negative development. */
#define NF_DEFECT_REGION_MAX_EDITS 4096U
#define NF_DEFECT_INFRARED_MAX_CLUSTERS 100000U
#define NF_DEFECT_RECIPE_MAX_NATIVE_REGION_DESCRIPTORS \
    (NF_DEFECT_REGION_MAX_EDITS + NF_DEFECT_INFRARED_MAX_CLUSTERS)
#define NF_DEFECT_REGION_MAX_MASK_BYTES (512U * 1024U * 1024U)

typedef struct nf_defect_region_edit_v1 {
    uint32_t enabled;
    uint32_t roi_x;
    uint32_t roi_y;
    uint32_t width;
    uint32_t height;
    uint32_t mask_stride_bytes;
    uint32_t mask_offset;
    uint32_t mask_byte_count;
    double strength;
    uint32_t has_preferred_angle;
    uint32_t reserved;
    double preferred_angle_degrees;
} nf_defect_region_edit_v1;

/* v18 preserves the complete v17 prefix. Descriptor and flat mask storage stay
   caller-owned for the synchronous preview/export call. Reserved fields are zero. */
typedef struct nf_develop_export_request_v18 {
    nf_develop_export_request_v17 v17;
    const nf_defect_region_edit_v1* defect_region_edits;
    uint32_t defect_region_edit_count;
    uint32_t defect_region_reserved;
    const uint8_t* defect_mask_bytes;
    uint32_t defect_mask_byte_count;
    uint32_t defect_mask_reserved;
} nf_develop_export_request_v18;

/* v19 binds a non-empty defect-region recipe to the exact source bytes. The
   digest points to exactly 32 caller-owned bytes for the synchronous call. A
   request without region edits must leave all appended fields zero/null. */
typedef struct nf_develop_export_request_v19 {
    nf_develop_export_request_v18 v18;
    uint64_t defect_source_file_bytes;
    const uint8_t* defect_source_sha256;
    uint32_t has_defect_source_identity;
    uint32_t reserved;
} nf_develop_export_request_v19;

#define NF_DEFECT_CLONE_MAX_EDITS 4096U
#define NF_DEFECT_CLONE_MAX_STROKES 100000U
#define NF_DEFECT_CLONE_MAX_POINTS 5000000U
#define NF_DEFECT_RECIPE_MAX_ORDERED_EDITS \
    (NF_DEFECT_REGION_MAX_EDITS + NF_DEFECT_INFRARED_MAX_CLUSTERS)

#define NF_DEFECT_RECIPE_EDIT_REGION 0U
#define NF_DEFECT_RECIPE_EDIT_CLONE 1U
#define NF_DEFECT_RECIPE_EDIT_BRUSH 2U

typedef struct nf_defect_clone_point_v1 {
    double x;
    double y;
} nf_defect_clone_point_v1;

typedef struct nf_defect_clone_stroke_v1 {
    uint32_t point_offset;
    uint32_t point_count;
    double offset_x;
    double offset_y;
    double diameter_pixels;
    double hardness;
} nf_defect_clone_stroke_v1;

typedef struct nf_defect_clone_edit_v1 {
    uint32_t enabled;
    uint32_t stroke_offset;
    uint32_t stroke_count;
    uint32_t reserved;
    double strength;
} nf_defect_clone_edit_v1;

typedef struct nf_defect_recipe_edit_ref_v1 {
    uint32_t kind;
    uint32_t index;
} nf_defect_recipe_edit_ref_v1;

/* v20 preserves the complete v19 prefix and appends Clone Stamp layers plus
   one order list covering every region and clone descriptor exactly once.
   Points are normalized raw-image coordinates with a top-left origin. */
typedef struct nf_develop_export_request_v20 {
    nf_develop_export_request_v19 v19;
    const nf_defect_clone_edit_v1* defect_clone_edits;
    uint32_t defect_clone_edit_count;
    uint32_t defect_clone_edit_reserved;
    const nf_defect_clone_stroke_v1* defect_clone_strokes;
    uint32_t defect_clone_stroke_count;
    uint32_t defect_clone_stroke_reserved;
    const nf_defect_clone_point_v1* defect_clone_points;
    uint32_t defect_clone_point_count;
    uint32_t defect_clone_point_reserved;
    const nf_defect_recipe_edit_ref_v1* defect_edit_order;
    uint32_t defect_edit_order_count;
    uint32_t defect_edit_order_reserved;
} nf_develop_export_request_v20;

#define NF_DEFECT_BRUSH_MAX_EDITS 4096U
#define NF_DEFECT_BRUSH_MAX_STROKES 100000U
#define NF_DEFECT_BRUSH_MAX_POINTS 5000000U

typedef struct nf_defect_brush_point_v1 {
    double x;
    double y;
} nf_defect_brush_point_v1;

typedef struct nf_defect_brush_stroke_v1 {
    uint32_t point_offset;
    uint32_t point_count;
    double thickness;
} nf_defect_brush_stroke_v1;

typedef struct nf_defect_brush_edit_v1 {
    uint32_t enabled;
    uint32_t stroke_offset;
    uint32_t stroke_count;
    uint32_t reserved;
    double strength;
} nf_defect_brush_edit_v1;

/* v21 preserves the complete v20 prefix and appends raw-image Brush layers.
   Points use normalized top-left coordinates and thickness is a fraction of
   the raw image's shorter dimension. The v20 order list covers region, clone,
   and brush descriptors exactly once. */
typedef struct nf_develop_export_request_v21 {
    nf_develop_export_request_v20 v20;
    const nf_defect_brush_edit_v1* defect_brush_edits;
    uint32_t defect_brush_edit_count;
    uint32_t defect_brush_edit_reserved;
    const nf_defect_brush_stroke_v1* defect_brush_strokes;
    uint32_t defect_brush_stroke_count;
    uint32_t defect_brush_stroke_reserved;
    const nf_defect_brush_point_v1* defect_brush_points;
    uint32_t defect_brush_point_count;
    uint32_t defect_brush_point_reserved;
} nf_develop_export_request_v21;

#define NF_DEFECT_INFRARED_MAX_ITEMS 4096U
#define NF_DEFECT_INFRARED_MAX_EDITS NF_DEFECT_INFRARED_MAX_CLUSTERS
#define NF_DEFECT_INFRARED_MAX_ATTENUATION_BYTES (512U * 1024U * 1024U)

/* An infrared descriptor turns one v21 region descriptor into a distinct IR
   edit. The referenced region supplies ROI, top-first one-byte core mask, and
   strength. attenuation is optional ROI-local top-first little-endian R16. */
typedef struct nf_defect_infrared_edit_v1 {
    uint32_t region_edit_index;
    uint32_t has_attenuation;
    uint32_t attenuation_stride_bytes;
    uint32_t attenuation_offset;
    uint32_t attenuation_byte_count;
    uint32_t reserved;
} nf_defect_infrared_edit_v1;

/* v24 preserves the complete v21 prefix and appends IR descriptors plus their
   caller-owned flat attenuation storage. v22/v23 changed call controls only,
   so v24 is the next request-bearing entry point. */
typedef struct nf_develop_export_request_v24 {
    nf_develop_export_request_v21 v21;
    const nf_defect_infrared_edit_v1* defect_infrared_edits;
    uint32_t defect_infrared_edit_count;
    uint32_t defect_infrared_edit_reserved;
    const uint8_t* defect_infrared_attenuation_bytes;
    uint32_t defect_infrared_attenuation_byte_count;
    uint32_t defect_infrared_attenuation_reserved;
} nf_develop_export_request_v24;

/* Groups a contiguous v24 infrared-cluster range into one ordered edit item.
   Every cluster is computed from the same item-level input image. */
typedef struct nf_defect_infrared_item_v1 {
    uint32_t cluster_offset;
    uint32_t cluster_count;
    uint32_t reserved_0;
    uint32_t reserved_1;
} nf_defect_infrared_item_v1;

typedef struct nf_develop_export_request_v25 {
    nf_develop_export_request_v24 v24;
    const nf_defect_infrared_item_v1* defect_infrared_items;
    uint32_t defect_infrared_item_count;
    uint32_t defect_infrared_item_reserved;
} nf_develop_export_request_v25;

#ifdef __cplusplus
}
#endif
