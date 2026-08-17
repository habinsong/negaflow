#include <cstring>
#include "develop_export_abi_test_support.h"

namespace negaflow::develop_export_abi_tests {

void test_v2_contract() {
    expect(sizeof(nf_develop_export_request_v2) == 96U, "v2 request layout is fixed");
    expect(sizeof(nf_develop_export_result_v2) == 152U, "v2 result layout is fixed");

    nf_develop_export_request_v2 request = make_request_v2(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v2(nullptr, &result) == NF_STATUS_INVALID_ARGUMENT,
        "v2 null request is rejected");
    expect(
        nf_develop_export_v2(&request, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "v2 null result is rejected");

    nf_develop_export_request_v2 small = request;
    small.struct_size = 4U;
    expect(
        nf_develop_export_v2(&small, &result) == NF_STATUS_STRUCT_TOO_SMALL,
        "v2 undersized request is rejected");

    nf_develop_export_request_v2 unknown = request;
    unknown.base_estimation_mode = 99U;
    expect(
        nf_develop_export_v2(&unknown, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "unknown_base_estimation_mode") == 0,
        "v2 unknown base mode is refused");

    nf_develop_export_request_v2 preset = request;
    preset.base_estimation_mode = NF_BASE_ESTIMATION_PRESET;
    expect(
        nf_develop_export_v2(&preset, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "unsupported_base_estimation_mode") == 0,
        "v2 preset is not silently treated as auto");
}

void test_v3_contract() {
    expect(sizeof(nf_develop_export_request_v3) == 112U, "v3 request layout is fixed");

    nf_develop_export_request_v3 request = make_request_v3(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v3(nullptr, &result) == NF_STATUS_INVALID_ARGUMENT,
        "v3 null request is rejected");
    expect(
        nf_develop_export_v3(&request, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "v3 null result is rejected");

    nf_develop_export_request_v3 small = request;
    small.struct_size = 4U;
    expect(
        nf_develop_export_v3(&small, &result) == NF_STATUS_STRUCT_TOO_SMALL,
        "v3 undersized request is rejected");

    request.density = 1.0F;
    request.highlight = -1.0F;
    request.shadow = 1.0F;
    request.whites = -1.0F;
    request.blacks = 1.0F;
    expect(
        nf_develop_export_v3(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v3 Basic Tone values reach source observation");
}

void test_v4_contract() {
    expect(sizeof(nf_develop_export_request_v4) == 128U, "v4 request layout is fixed");
    nf_develop_export_request_v4 request = make_request_v4(
        L"a.tif", L"b.png", NF_BASE_ESTIMATION_PRESET);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v4(nullptr, &result) == NF_STATUS_INVALID_ARGUMENT,
        "v4 null request is rejected");
    expect(
        nf_develop_export_v4(&request, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "v4 null result is rejected");

    nf_develop_export_request_v4 small = request;
    small.struct_size = 4U;
    expect(
        nf_develop_export_v4(&small, &result) == NF_STATUS_STRUCT_TOO_SMALL,
        "v4 undersized request is rejected");

    expect(
        nf_develop_export_v4(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "missing_film_stock") == 0,
        "v4 Film mode requires a stock identifier");

    request.film_stock_dmin_id = L"not-a-stock";
    expect(
        nf_develop_export_v4(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "unknown_film_stock_or_light") == 0,
        "v4 unknown stock fails closed");

    request.film_stock_dmin_id = L"kodak-portra-400";
    request.light_source_profile_id = L"warm-led";
    expect(
        nf_develop_export_v4(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v4 known Film identifiers reach source observation");
}

void test_v5_contract() {
    expect(sizeof(nf_point_curve_v1) == 1032U, "v5 point curve layout is fixed");
    expect(sizeof(nf_develop_export_request_v5) == 4256U, "v5 request layout is fixed");
    nf_develop_export_request_v5 request = make_request_v5(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v5(nullptr, &result) == NF_STATUS_INVALID_ARGUMENT,
        "v5 null request is rejected");
    expect(
        nf_develop_export_v5(&request, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "v5 null result is rejected");

    nf_develop_export_request_v5 small = request;
    small.struct_size = 4U;
    expect(
        nf_develop_export_v5(&small, &result) == NF_STATUS_STRUCT_TOO_SMALL,
        "v5 undersized request is rejected");

    request.point_curve_rgb.reserved = 1U;
    expect(
        nf_develop_export_v5(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_point_curves") == 0,
        "v5 reserved Point Curve bytes are rejected");

    request = make_request_v5(L"a.tif", L"b.png");
    request.point_curve_rgb.point_count = NF_POINT_CURVE_MAX_POINTS + 1U;
    expect(
        nf_develop_export_v5(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_point_curves") == 0,
        "v5 oversized Point Curve is rejected");

    request = make_request_v5(L"a.tif", L"b.png");
    request.point_curve_rgb.point_count = 2U;
    request.point_curve_rgb.points[0U] = {0.5, 0.4};
    request.point_curve_rgb.points[1U] = {0.5, 0.6};
    expect(
        nf_develop_export_v5(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_point_curves") == 0,
        "v5 duplicate Point Curve coordinate is rejected");

    request = make_request_v5(L"a.tif", L"b.png");
    request.point_curve_rgb.point_count = 3U;
    request.point_curve_rgb.points[0U] = {0.0, 0.0};
    request.point_curve_rgb.points[1U] = {0.5, 0.6};
    request.point_curve_rgb.points[2U] = {1.0, 1.0};
    expect(
        nf_develop_export_v5(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v5 Point Curves reach source observation");
}

void test_v6_contract() {
    expect(sizeof(nf_develop_export_request_v6) == 4352U, "v6 request layout is fixed");
    nf_develop_export_request_v6 request = make_request_v6(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v6(nullptr, &result) == NF_STATUS_INVALID_ARGUMENT,
        "v6 null request is rejected");
    expect(
        nf_develop_export_v6(&request, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "v6 null result is rejected");

    nf_develop_export_request_v6 small = request;
    small.struct_size = 4U;
    expect(
        nf_develop_export_v6(&small, &result) == NF_STATUS_STRUCT_TOO_SMALL,
        "v6 undersized request is rejected");

    request.color_mixer_hue[0U] = 1.01F;
    expect(
        nf_develop_export_v6(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_color_mixer") == 0,
        "v6 out-of-range Color Mixer is rejected");

    request = make_request_v6(L"a.tif", L"b.png");
    request.color_mixer_saturation[1U] = 0.5F;
    expect(
        nf_develop_export_v6(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v6 Color Mixer reaches source observation");
}

void test_v7_contract() {
    expect(sizeof(nf_develop_export_request_v7) == 4400U, "v7 request layout is fixed");
    nf_develop_export_request_v7 request = make_request_v7(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v7(nullptr, &result) == NF_STATUS_INVALID_ARGUMENT,
        "v7 null request is rejected");
    request.color_grading_midtones_saturation = 1.01F;
    expect(
        nf_develop_export_v7(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_color_grading") == 0,
        "v7 out-of-range Color Grading is rejected");
    request = make_request_v7(L"a.tif", L"b.png");
    request.color_grading_highlights_luminance = 0.25F;
    expect(
        nf_develop_export_v7(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v7 Color Grading reaches source observation");
}

void test_v8_contract() {
    expect(sizeof(nf_develop_export_request_v8) == 4408U,
           "v8 request layout is fixed");
    nf_develop_export_request_v8 request = make_request_v8(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    request.defect_removal_strength = 1.01;
    expect(
        nf_develop_export_v8(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_grain_mend_parameters") == 0,
        "v8 out-of-range GrainMend strength is rejected");
    request = make_request_v8(L"a.tif", L"b.png");
    request.defect_removal_strength = 0.75;
    expect(
        nf_develop_export_v8(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v8 GrainMend strength reaches source observation");
}

void test_v9_contract() {
    expect(sizeof(nf_develop_export_request_v9) == 4440U,
           "v9 request layout is fixed");
    nf_develop_export_request_v9 request = make_request_v9(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    request.noise_reduction_strength = 1.01F;
    expect(
        nf_develop_export_v9(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(
                result.failure_name,
                "invalid_film_scan_denoise_parameters") == 0,
        "v9 out-of-range FilmScanDenoise strength is rejected");
    request = make_request_v9(L"a.tif", L"b.png");
    request.noise_reduction_strength = 0.75F;
    request.noise_reduction_film_profile =
        NF_FILM_SCAN_DENOISE_COLOR_POSITIVE;
    expect(
        nf_develop_export_v9(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v9 FilmScanDenoise controls reach source observation");
}

void test_v10_contract() {
    expect(sizeof(nf_develop_export_request_v10) == 4464U,
           "v10 request layout is fixed");
    nf_develop_export_request_v10 request =
        make_request_v10(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    request.texture_clarity = 1.01F;
    expect(
        nf_develop_export_v10(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_texture_parameters") == 0,
        "v10 out-of-range Texture control is rejected");
    request = make_request_v10(L"a.tif", L"b.png");
    request.texture_sharpness = 0.75F;
    expect(
        nf_develop_export_v10(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v10 Texture controls reach source observation");
}

void test_v11_contract() {
    expect(sizeof(nf_develop_export_request_v11) == 4552U,
           "v11 request layout is fixed");
    nf_develop_export_request_v11 request =
        make_request_v11(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    request.image_rotation = 4U;
    expect(
        nf_develop_export_v11(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name,
                        "invalid_post_pipeline_parameters") == 0,
        "v11 invalid ImageTransform is rejected");
    request = make_request_v11(L"a.tif", L"b.png");
    request.bw_toning_mode = 1U;
    request.bw_toning_shadow_hue = 285.0;
    request.bw_toning_highlight_hue = 34.0;
    request.bw_toning_strength = 0.5;
    expect(
        nf_develop_export_v11(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v11 B&W toning and transform controls reach source observation");
}

void test_v12_contract() {
    expect(sizeof(nf_develop_export_request_v12) == 4600U,
           "v12 request layout is fixed");
    nf_local_dodge_burn_stroke_v1 stroke{};
    stroke.point_offset = 1U;
    stroke.point_count = 1U;
    stroke.thickness = 0.04F;
    stroke.feather = 0.02F;
    nf_local_dodge_burn_adjustment_v1 adjustment{};
    adjustment.mode = NF_LOCAL_DODGE_BURN_MODE_DODGE;
    adjustment.enabled = 1U;
    adjustment.mask_kind = NF_LOCAL_DODGE_BURN_MASK_BRUSH;
    adjustment.stroke_count = 1U;
    adjustment.amount = 0.5F;
    adjustment.center_x = 0.5F;
    adjustment.center_y = 0.5F;
    adjustment.radius = 0.25F;
    adjustment.feather = 0.25F;
    adjustment.start_x = 0.5F;
    adjustment.end_x = 0.5F;
    adjustment.end_y = 1.0F;
    nf_local_dodge_burn_point_v1 point{0.5F, 0.5F};
    nf_develop_export_request_v12 request =
        make_request_v12(L"a.tif", L"b.png");
    request.local_adjustments = &adjustment;
    request.local_adjustment_count = 1U;
    request.local_strokes = &stroke;
    request.local_stroke_count = 1U;
    request.local_points = &point;
    request.local_point_count = 1U;
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v12(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(
                result.failure_name,
                "invalid_local_dodge_burn_payload") == 0,
        "v12 rejects a stroke point range outside the flat payload");
}

}  // namespace negaflow::develop_export_abi_tests
