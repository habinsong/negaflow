#include <cstring>
#include "develop_export_abi_test_support.h"

namespace negaflow::develop_export_abi_tests {

void test_v26_contract() {
    expect(sizeof(nf_develop_export_request_v26) == 4896U,
           "v26 request layout is fixed");
    expect(offsetof(nf_develop_export_request_v26, output_sharpening_strength) ==
               4880U,
           "v26 output sharpening offset is fixed");

    nf_develop_export_request_v26 request = make_request_v26(L"a.tif", L"b.png");
    request.output_sharpening_strength = 0.80F;
    request.output_sharpening_medium = NF_OUTPUT_SHARPENING_MATTE_PAPER;
    request.output_sharpening_dpi = 300;
    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_export_v26(&request, nullptr, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v26 output sharpening request reaches source observation");

    request.output_sharpening_strength = 1.1F;
    result = make_result_v3();
    expect(
        nf_develop_export_v26(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(
                result.failure_name,
                "invalid_output_sharpening_parameters") == 0,
        "v26 rejects output sharpening outside its supported range");
}

void test_v27_contract() {
    expect(sizeof(nf_develop_export_request_v27) == 4928U,
           "v27 request layout is fixed");
    expect(offsetof(nf_develop_export_request_v27, primary_calibration_red_hue) == 4896U,
           "v27 primary calibration offset is fixed");

    nf_develop_export_request_v27 request = make_request_v27(L"a.tif", L"b.png");
    request.primary_calibration_red_hue = 0.8F;
    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_export_v27(&request, nullptr, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v27 primary calibration request reaches source observation");

    request.primary_calibration_blue_saturation = 1.1F;
    result = make_result_v3();
    expect(
        nf_develop_export_v27(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_primary_calibration_parameters") == 0,
        "v27 rejects primary calibration outside its supported range");
}

void test_v28_contract() {
    expect(sizeof(nf_develop_export_request_v28) == 4944U,
           "v28 request layout is fixed");
    expect(offsetof(nf_develop_export_request_v28, jpeg_quality) == 4928U,
           "v28 JPEG quality offset is fixed");

    nf_develop_export_request_v28 request = make_request_v28(L"a.tif", L"b.jpg");
    request.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .output_format = NF_EXPORT_FORMAT_JPEG8;
    request.jpeg_quality = 0.96F;
    request.output_dpi = 300U;
    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_export_v28(&request, nullptr, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v28 JPEG output request reaches source observation");

    request.jpeg_quality = 1.01F;
    result = make_result_v3();
    expect(
        nf_develop_export_v28(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_output_options") == 0,
        "v28 rejects JPEG quality outside its supported range");
}

void test_v29_contract() {
    expect(sizeof(nf_develop_export_request_v29) == 4960U,
           "v29 request layout is fixed");
    expect(offsetof(nf_develop_export_request_v29, output_long_edge) == 4944U,
           "v29 output long-edge offset is fixed");

    nf_develop_export_request_v29 request = make_request_v29(L"a.tif", L"b.png");
    request.output_long_edge = 2048U;
    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_export_v29(&request, nullptr, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v29 long-edge request reaches source observation");

    request.output_geometry_reserved0 = 1U;
    result = make_result_v3();
    expect(
        nf_develop_export_v29(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_output_geometry") == 0,
        "v29 rejects nonzero output geometry reserved fields");
}

void test_v30_contract() {
    expect(sizeof(nf_develop_export_request_v30) == 4976U,
           "v30 request layout is fixed");
    expect(offsetof(nf_develop_export_request_v30, tiff_compression) == 4960U,
           "v30 TIFF compression offset is fixed");

    nf_develop_export_request_v30 request = make_request_v30(L"a.tif", L"b.tif");
    request.v29.v28.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .output_format = NF_EXPORT_FORMAT_TIFF16;
    request.v29.v28.output_dpi = 300U;
    request.tiff_compression = NF_TIFF_COMPRESSION_DEFLATE;
    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_export_v30(&request, nullptr, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v30 TIFF encoding request reaches source observation");

    request.tiff_compression = NF_TIFF_COMPRESSION_DEFLATE + 1U;
    result = make_result_v3();
    expect(
        nf_develop_export_v30(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_output_encoding") == 0,
        "v30 rejects unknown TIFF compression");
}

void test_v32_contract() {
    expect(sizeof(nf_develop_export_request_v32) == 5008U,
           "v32 request layout is fixed");
    expect(offsetof(nf_develop_export_request_v32, output_color_space) == 4992U,
           "v32 colour space offset is fixed");

    nf_develop_export_request_v32 request;
    std::memset(&request, 0, sizeof(request));
    request.v31.v30 = make_request_v30(L"a.tif", L"b.tif");
    request.v31.output_bit_depth = 16U;
    auto& base = request.v31.v30.v29.v28.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13
                     .v12.v11.v10.v9.v8;
    base.struct_size = static_cast<std::uint32_t>(sizeof(request));
    base.output_format = NF_EXPORT_FORMAT_TIFF16;

    request.output_color_space = 1U;  // Display P3
    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_export_v32(&request, nullptr, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v32 wide-gamut TIFF request reaches source observation");

    // JPEG carries no colour context here, so a wide-gamut JPEG would be pixels in one
    // space labelled as another. Refusing beats publishing a file that reads wrong.
    base.output_format = NF_EXPORT_FORMAT_JPEG8;
    result = make_result_v3();
    expect(
        nf_develop_export_v32(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "jpeg_requires_srgb") == 0,
        "v32 refuses a wide-gamut JPEG rather than mislabelling it");

    request.output_color_space = 0U;
    result = make_result_v3();
    expect(
        nf_develop_export_v32(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v32 sRGB JPEG is allowed");

    base.output_format = NF_EXPORT_FORMAT_TIFF16;
    request.output_color_space = 3U;
    result = make_result_v3();
    expect(
        nf_develop_export_v32(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_output_color_space") == 0,
        "v32 rejects an unknown colour space");

    request.output_color_space = 0U;
    request.output_space_reserved1 = 7U;
    result = make_result_v3();
    expect(
        nf_develop_export_v32(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_output_color_space") == 0,
        "v32 rejects a dirty reserved field");
}

void test_v34_contract() {
    expect(sizeof(nf_develop_export_request_v34) == 5104U,
           "v34 request layout is fixed");
    expect(offsetof(nf_develop_export_request_v34, preserve_alpha) == 5088U,
           "v34 preserve-alpha offset is fixed");

    nf_develop_export_request_v34 request;
    std::memset(&request, 0, sizeof(request));
    request.v33.v32.v31.v30 = make_request_v30(L"a.tif", L"b.tif");
    request.v33.v32.v31.output_bit_depth = 16U;
    auto& base = request.v33.v32.v31.v30.v29.v28.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16
                     .v15.v14.v13.v12.v11.v10.v9.v8;
    base.struct_size = static_cast<std::uint32_t>(sizeof(request));
    base.output_format = NF_EXPORT_FORMAT_TIFF16;
    request.preserve_alpha = 1U;
    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_export_v34(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v34 TIFF alpha request reaches source observation");

    base.output_format = NF_EXPORT_FORMAT_JPEG8;
    result = make_result_v3();
    expect(
        nf_develop_export_v34(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "jpeg_does_not_support_alpha") == 0,
        "v34 refuses alpha JPEG before source observation");

    request.preserve_alpha = 2U;
    result = make_result_v3();
    expect(
        nf_develop_export_v34(&request, nullptr, &result) == NF_STATUS_OK &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_preserve_alpha") == 0,
        "v34 rejects an invalid alpha flag");
}

}  // namespace negaflow::develop_export_abi_tests
