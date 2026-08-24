#include <cstring>
#include "develop_export_abi_test_support.h"

namespace negaflow::develop_export_abi_tests {

void test_v18_contract() {
    nf_develop_export_request_v18 request =
        make_request_v18(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();

    request.defect_region_reserved = 1U;
    expect(
        nf_develop_export_v18(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_region_payload") == 0,
        "v18 rejects a nonzero defect payload reserved field");

    request = make_request_v18(L"a.tif", L"b.png");
    nf_defect_region_edit_v1 edit{};
    edit.enabled = 1U;
    edit.width = 8U;
    edit.height = 8U;
    edit.mask_stride_bytes = 8U;
    edit.mask_byte_count = 64U;
    edit.strength = 1.0;
    std::vector<std::uint8_t> truncated_mask(32U, 0xffU);
    request.defect_region_edits = &edit;
    request.defect_region_edit_count = 1U;
    request.defect_mask_bytes = truncated_mask.data();
    request.defect_mask_byte_count =
        static_cast<std::uint32_t>(truncated_mask.size());
    result = make_result_v2();
    expect(
        nf_develop_export_v18(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_region_payload") == 0,
        "v18 rejects a defect mask range outside the flat payload");
}

void test_v19_contract() {
    nf_develop_export_request_v19 request =
        make_request_v19(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    request.reserved = 1U;
    expect(
        nf_develop_export_v19(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(
                result.failure_name,
                "invalid_defect_source_identity") == 0,
        "v19 rejects a nonzero source-identity reserved field");

    request = make_request_v19(L"a.tif", L"b.png");
    nf_defect_region_edit_v1 edit{};
    edit.enabled = 1U;
    edit.width = 8U;
    edit.height = 8U;
    edit.mask_stride_bytes = 8U;
    edit.mask_byte_count = 64U;
    edit.strength = 1.0;
    std::vector<std::uint8_t> mask(64U, 0xffU);
    request.v18.defect_region_edits = &edit;
    request.v18.defect_region_edit_count = 1U;
    request.v18.defect_mask_bytes = mask.data();
    request.v18.defect_mask_byte_count = static_cast<std::uint32_t>(mask.size());
    result = make_result_v2();
    expect(
        nf_develop_export_v19(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(
                result.failure_name,
                "invalid_defect_source_identity") == 0,
        "v19 rejects an unbound defect recipe before source I/O");
}

void test_v20_contract() {
    expect(sizeof(nf_defect_clone_point_v1) == 16U,
           "v20 clone point layout is fixed");
    expect(sizeof(nf_defect_clone_stroke_v1) == 40U,
           "v20 clone stroke layout is fixed");
    expect(sizeof(nf_defect_clone_edit_v1) == 24U,
           "v20 clone edit layout is fixed");
    expect(sizeof(nf_develop_export_request_v20) == 4784U,
           "v20 request layout is fixed");

    nf_defect_clone_point_v1 point{0.5, 0.5};
    nf_defect_clone_stroke_v1 stroke{};
    stroke.point_count = 1U;
    stroke.offset_x = 0.1;
    stroke.diameter_pixels = 9.0;
    stroke.hardness = 1.0;
    nf_defect_clone_edit_v1 edit{};
    edit.enabled = 1U;
    edit.stroke_count = 1U;
    edit.strength = 1.0;
    nf_defect_recipe_edit_ref_v1 order{
        NF_DEFECT_RECIPE_EDIT_CLONE, 0U};
    std::array<std::uint8_t, 32U> digest{};

    nf_develop_export_request_v20 request =
        make_request_v20(L"a.tif", L"b.png");
    request.v19.defect_source_file_bytes = 1U;
    request.v19.defect_source_sha256 = digest.data();
    request.v19.has_defect_source_identity = 1U;
    request.defect_clone_edits = &edit;
    request.defect_clone_edit_count = 1U;
    request.defect_clone_strokes = &stroke;
    request.defect_clone_stroke_count = 1U;
    request.defect_clone_points = &point;
    request.defect_clone_point_count = 1U;
    request.defect_edit_order = &order;
    request.defect_edit_order_count = 1U;
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v20(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v20 complete clone payload reaches source observation");

    request.defect_edit_order_count = 0U;
    result = make_result_v2();
    expect(
        nf_develop_export_v20(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_clone_payload") == 0,
        "v20 rejects a clone descriptor omitted from recipe order");
}

void test_v21_contract() {
    expect(sizeof(nf_defect_brush_point_v1) == 16U,
           "v21 brush point layout is fixed");
    expect(sizeof(nf_defect_brush_stroke_v1) == 16U,
           "v21 brush stroke layout is fixed");
    expect(sizeof(nf_defect_brush_edit_v1) == 24U,
           "v21 brush edit layout is fixed");
    expect(sizeof(nf_develop_export_request_v21) == 4832U,
           "v21 request layout is fixed");

    nf_defect_brush_point_v1 point{0.5, 0.5};
    nf_defect_brush_stroke_v1 stroke{};
    stroke.point_count = 1U;
    stroke.thickness = 0.02;
    nf_defect_brush_edit_v1 edit{};
    edit.enabled = 1U;
    edit.stroke_count = 1U;
    edit.strength = 1.0;
    nf_defect_recipe_edit_ref_v1 order{
        NF_DEFECT_RECIPE_EDIT_BRUSH, 0U};
    std::array<std::uint8_t, 32U> digest{};

    nf_develop_export_request_v21 request =
        make_request_v21(L"a.tif", L"b.png");
    request.v20.v19.defect_source_file_bytes = 1U;
    request.v20.v19.defect_source_sha256 = digest.data();
    request.v20.v19.has_defect_source_identity = 1U;
    request.v20.defect_edit_order = &order;
    request.v20.defect_edit_order_count = 1U;
    request.defect_brush_edits = &edit;
    request.defect_brush_edit_count = 1U;
    request.defect_brush_strokes = &stroke;
    request.defect_brush_stroke_count = 1U;
    request.defect_brush_points = &point;
    request.defect_brush_point_count = 1U;
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v21(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v21 complete brush payload reaches source observation");

    request.v20.defect_edit_order_count = 0U;
    result = make_result_v2();
    expect(
        nf_develop_export_v21(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_clone_payload") == 0,
        "v21 rejects a brush descriptor omitted from recipe order");

    request.v20.defect_edit_order_count = 1U;
    point.x = 2.0;
    result = make_result_v2();
    expect(
        nf_develop_export_v21(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_brush_payload") == 0,
        "v21 rejects out-of-range normalized brush geometry");
}

void test_v24_contract() {
    expect(sizeof(nf_defect_infrared_edit_v1) == 24U,
           "v24 infrared descriptor layout is fixed");
    expect(sizeof(nf_develop_export_request_v24) == 4864U,
           "v24 request layout is fixed");
    expect(offsetof(nf_develop_export_request_v24, defect_infrared_edits) == 4832U,
           "v24 infrared descriptor offset is fixed");
    expect(offsetof(nf_develop_export_request_v24,
                    defect_infrared_attenuation_bytes) == 4848U,
           "v24 attenuation payload offset is fixed");

    std::array<std::uint8_t, 64U> core{};
    std::array<std::uint8_t, 128U> attenuation{};
    std::array<std::uint8_t, 32U> digest{};
    nf_defect_region_edit_v1 region{};
    region.enabled = 1U;
    region.width = 8U;
    region.height = 8U;
    region.mask_stride_bytes = 8U;
    region.mask_byte_count = static_cast<std::uint32_t>(core.size());
    region.strength = 1.0;
    nf_defect_recipe_edit_ref_v1 order{NF_DEFECT_RECIPE_EDIT_REGION, 0U};
    nf_defect_infrared_edit_v1 infrared{};
    infrared.has_attenuation = 1U;
    infrared.attenuation_stride_bytes = 16U;
    infrared.attenuation_byte_count =
        static_cast<std::uint32_t>(attenuation.size());

    nf_develop_export_request_v24 request = make_request_v24(L"a.tif", L"b.png");
    request.v21.v20.v19.defect_source_file_bytes = 1U;
    request.v21.v20.v19.defect_source_sha256 = digest.data();
    request.v21.v20.v19.has_defect_source_identity = 1U;
    request.v21.v20.v19.v18.defect_region_edits = &region;
    request.v21.v20.v19.v18.defect_region_edit_count = 1U;
    request.v21.v20.v19.v18.defect_mask_bytes = core.data();
    request.v21.v20.v19.v18.defect_mask_byte_count =
        static_cast<std::uint32_t>(core.size());
    request.v21.v20.defect_edit_order = &order;
    request.v21.v20.defect_edit_order_count = 1U;
    request.defect_infrared_edits = &infrared;
    request.defect_infrared_edit_count = 1U;
    request.defect_infrared_attenuation_bytes = attenuation.data();
    request.defect_infrared_attenuation_byte_count =
        static_cast<std::uint32_t>(attenuation.size());
    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_export_v24(&request, nullptr, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v24 complete infrared payload reaches source observation");

    infrared.attenuation_byte_count--;
    result = make_result_v3();
    expect(
        nf_develop_export_v24(&request, nullptr, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_infrared_payload") == 0,
        "v24 rejects an infrared attenuation size mismatch");
}

void test_v25_contract() {
    expect(sizeof(nf_defect_infrared_item_v1) == 16U,
           "v25 infrared item layout is fixed");
    expect(sizeof(nf_develop_export_request_v25) == 4880U,
           "v25 request layout is fixed");
    expect(offsetof(nf_develop_export_request_v25, defect_infrared_items) ==
               4864U,
           "v25 infrared item offset is fixed");

    std::array<std::uint8_t, 128U> core{};
    std::array<std::uint8_t, 256U> attenuation{};
    std::array<std::uint8_t, 32U> digest{};
    std::array<nf_defect_region_edit_v1, 2U> regions{};
    std::array<nf_defect_infrared_edit_v1, 2U> infrared{};
    std::array<nf_defect_recipe_edit_ref_v1, 2U> order{};
    for (std::uint32_t index = 0U; index < 2U; ++index) {
        regions[index].enabled = 1U;
        regions[index].width = 8U;
        regions[index].height = 8U;
        regions[index].mask_stride_bytes = 8U;
        regions[index].mask_offset = index * 64U;
        regions[index].mask_byte_count = 64U;
        regions[index].strength = 0.75;
        infrared[index].region_edit_index = index;
        infrared[index].has_attenuation = 1U;
        infrared[index].attenuation_stride_bytes = 16U;
        infrared[index].attenuation_offset = index * 128U;
        infrared[index].attenuation_byte_count = 128U;
        order[index] = {NF_DEFECT_RECIPE_EDIT_REGION, index};
    }
    nf_defect_infrared_item_v1 item{0U, 2U, 0U, 0U};
    nf_develop_export_request_v25 request = make_request_v25(L"a.tif", L"b.png");
    request.v24.v21.v20.v19.defect_source_file_bytes = 1U;
    request.v24.v21.v20.v19.defect_source_sha256 = digest.data();
    request.v24.v21.v20.v19.has_defect_source_identity = 1U;
    request.v24.v21.v20.v19.v18.defect_region_edits = regions.data();
    request.v24.v21.v20.v19.v18.defect_region_edit_count = 2U;
    request.v24.v21.v20.v19.v18.defect_mask_bytes = core.data();
    request.v24.v21.v20.v19.v18.defect_mask_byte_count =
        static_cast<std::uint32_t>(core.size());
    request.v24.v21.v20.defect_edit_order = order.data();
    request.v24.v21.v20.defect_edit_order_count = 2U;
    request.v24.defect_infrared_edits = infrared.data();
    request.v24.defect_infrared_edit_count = 2U;
    request.v24.defect_infrared_attenuation_bytes = attenuation.data();
    request.v24.defect_infrared_attenuation_byte_count =
        static_cast<std::uint32_t>(attenuation.size());
    request.defect_infrared_items = &item;
    request.defect_infrared_item_count = 1U;

    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_export_v25(&request, nullptr, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v25 contiguous item range reaches source observation");

    std::array<nf_defect_infrared_item_v1, 2U> singleton_items{
        nf_defect_infrared_item_v1{0U, 1U, 0U, 0U},
        nf_defect_infrared_item_v1{1U, 1U, 0U, 0U},
    };
    request.defect_infrared_items = singleton_items.data();
    request.defect_infrared_item_count = 2U;
    result = make_result_v3();
    expect(
        nf_develop_export_v25(&request, nullptr, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v25 order references each singleton item exactly once");
    singleton_items[1U].cluster_offset = 0U;
    result = make_result_v3();
    expect(
        nf_develop_export_v25(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(
                result.failure_name,
                "invalid_defect_infrared_item_payload") == 0,
        "v25 rejects overlapping item ranges before flat mapping");
    request.defect_infrared_items = &item;
    request.defect_infrared_item_count = 1U;

    item.cluster_offset = 1U;
    result = make_result_v3();
    expect(
        nf_develop_export_v25(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(
                result.failure_name,
                "invalid_defect_infrared_item_payload") == 0,
        "v25 rejects an item range gap before mapping flat clusters");

    item.cluster_offset = 0U;
    item.cluster_count = 1U;
    result = make_result_v3();
    expect(
        nf_develop_export_v25(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(
                result.failure_name,
                "invalid_defect_infrared_item_payload") == 0,
        "v25 rejects an item range that does not consume every cluster");

    item.cluster_count = 2U;
    std::swap(order[0U], order[1U]);
    result = make_result_v3();
    expect(
        nf_develop_export_v25(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(
                result.failure_name,
                "invalid_defect_infrared_item_payload") == 0,
        "v25 requires each item reference once in cluster order");
    std::swap(order[0U], order[1U]);

    item.cluster_count = NF_DEFECT_INFRARED_MAX_EDITS + 1U;
    request.v24.defect_infrared_edit_count = item.cluster_count;
    result = make_result_v3();
    expect(
        nf_develop_export_v25(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_infrared_payload") == 0,
        "v25 rejects excess flat infrared clusters before region mapping");

    item.cluster_count = 2U;
    request.v24.defect_infrared_edit_count = 2U;
    nf_defect_clone_edit_v1 clone{};
    nf_defect_brush_edit_v1 brush{};
    request.v24.v21.v20.v19.v18.defect_region_edit_count =
        NF_DEFECT_REGION_MAX_EDITS;
    request.v24.v21.v20.defect_clone_edits = &clone;
    request.v24.v21.v20.defect_clone_edit_count = NF_DEFECT_CLONE_MAX_EDITS;
    request.v24.v21.defect_brush_edits = &brush;
    request.v24.v21.defect_brush_edit_count = 1U;
    request.v24.v21.v20.defect_edit_order_count =
        NF_DEFECT_RECIPE_MAX_ORDERED_EDITS + 1U;
    result = make_result_v3();
    expect(
        nf_develop_export_v25(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_clone_payload") == 0,
        "v25 rejects an expanded native order above the transport limit");
}

}  // namespace negaflow::develop_export_abi_tests
