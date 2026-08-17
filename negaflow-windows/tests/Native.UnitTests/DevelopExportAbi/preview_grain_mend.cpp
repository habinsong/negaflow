#include "develop_export_abi_test_support.h"

namespace negaflow::develop_export_abi_tests {

void test_v8_grain_mend_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v8 request =
        make_request_v8(source_text.c_str(), nullptr);
    request.defect_removal_strength = 0.75;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v8(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK &&
            result.succeeded == 1U,
        "v8 nonzero GrainMend preview succeeds through the shared pipeline");
}

// v1 검출기는 기존 자동 호출을 보존하고, v2만 가이드의 raw ROI와 원본 픽셀 사각형을
// 추가한다. 실제 TIFF를 두 번 호출해 size-query와 마스크 호출의 ROI 계약이 같음을 확인한다.
void test_v2_grain_mend_detection(const std::filesystem::path& source) {
    expect(sizeof(nf_grain_mend_detect_parameters_v1) == 40U &&
            sizeof(nf_grain_mend_detection_v2) == 56U,
        "v2 GrainMend detection ABI layouts are fixed");

    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v27 request =
        make_request_v27(source_text.c_str(), nullptr);
    request.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .defect_removal_strength = 1.0;
    nf_grain_mend_detect_parameters_v1 parameters{};
    parameters.struct_size = static_cast<std::uint32_t>(sizeof(parameters));
    parameters.roi_x = 0.2;
    parameters.roi_y = 0.25;
    parameters.roi_width = 0.5;
    parameters.roi_height = 0.5;

    nf_grain_mend_detection_v2 sized{};
    sized.struct_size = static_cast<std::uint32_t>(sizeof(sized));
    nf_develop_export_result_v3 sized_result = make_result_v3();
    const nf_status_t sized_status = nf_develop_detect_grain_mend_v2(
        &request, &parameters, nullptr, 0U, nullptr, &sized, &sized_result);
    const bool sized_ok =
        sized_status == NF_STATUS_OK && sized_result.succeeded == 1U &&
        sized.source_width > 2U && sized.source_height > 2U &&
        sized.roi_width > 2U && sized.roi_height > 2U &&
        sized.roi_width < sized.source_width && sized.roi_height < sized.source_height &&
        sized.width > 0U && sized.height > 0U &&
        sized.mask_byte_count == static_cast<std::uint64_t>(sized.width) * sized.height;
    expect(sized_ok, "v2 GrainMend size query reports a bounded raw ROI");
    if (!sized_ok) {
        return;
    }

    std::vector<std::uint8_t> mask(sized.mask_byte_count, 0U);
    nf_grain_mend_detection_v2 filled{};
    filled.struct_size = static_cast<std::uint32_t>(sizeof(filled));
    nf_develop_export_result_v3 filled_result = make_result_v3();
    expect(
        nf_develop_detect_grain_mend_v2(
            &request, &parameters, mask.data(), mask.size(), nullptr, &filled, &filled_result) ==
                NF_STATUS_OK &&
            filled_result.succeeded == 1U &&
            filled.width == sized.width && filled.height == sized.height &&
            filled.mask_byte_count == sized.mask_byte_count &&
            filled.source_width == sized.source_width &&
            filled.source_height == sized.source_height &&
            filled.roi_x == sized.roi_x && filled.roi_y == sized.roi_y &&
            filled.roi_width == sized.roi_width && filled.roi_height == sized.roi_height,
        "v2 GrainMend mask call preserves the size-query raw ROI");
}

// v3 adds only transient review tuning. It must leave the v2 ROI/result shape intact
// while refusing unknown nonzero reserved fields at the ABI boundary.
void test_v3_grain_mend_detection_tuning(const std::filesystem::path& source) {
    expect(sizeof(nf_grain_mend_detect_parameters_v2) == 72U &&
            offsetof(nf_grain_mend_detect_parameters_v2, dust_sensitivity) == 40U,
        "v3 GrainMend detection tuning ABI layout is fixed");

    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v27 request =
        make_request_v27(source_text.c_str(), nullptr);
    request.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .defect_removal_strength = 1.0;
    nf_grain_mend_detect_parameters_v2 parameters{};
    parameters.v1.struct_size = static_cast<std::uint32_t>(sizeof(parameters));
    parameters.v1.roi_x = 0.2;
    parameters.v1.roi_y = 0.25;
    parameters.v1.roi_width = 0.5;
    parameters.v1.roi_height = 0.5;
    parameters.dust_sensitivity = 1.0;
    parameters.scratch_sensitivity = 1.0;
    parameters.protect_detail = 0.6;
    parameters.reject_structure_lines = 0U;

    nf_grain_mend_detection_v2 detection{};
    detection.struct_size = static_cast<std::uint32_t>(sizeof(detection));
    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_detect_grain_mend_v3(
            &request, &parameters, nullptr, 0U, nullptr, &detection, &result) ==
                NF_STATUS_OK &&
            result.succeeded == 1U && detection.width > 0U && detection.height > 0U &&
            detection.mask_byte_count ==
                static_cast<std::uint64_t>(detection.width) * detection.height,
        "v3 GrainMend detection accepts explicit transient tuning");

    parameters.reserved = 1U;
    detection = {};
    detection.struct_size = static_cast<std::uint32_t>(sizeof(detection));
    result = make_result_v3();
    expect(
        nf_develop_detect_grain_mend_v3(
            &request, &parameters, nullptr, 0U, nullptr, &detection, &result) ==
            NF_STATUS_INVALID_ARGUMENT,
        "v3 GrainMend detection rejects nonzero tuning reserved field");
}

// v4 appends only the optional macOS micro-speck bit. It keeps the v3 review
// tuning and ROI prefix frozen, and rejects a caller that tries to smuggle future
// fields through the reserved tail.
void test_v4_grain_mend_micro_speck_detection(const std::filesystem::path& source) {
    expect(sizeof(nf_grain_mend_detect_parameters_v3) == 80U &&
            offsetof(nf_grain_mend_detect_parameters_v3, detect_micro_specks) == 72U,
        "v4 GrainMend micro-speck ABI layout is fixed");

    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v27 request =
        make_request_v27(source_text.c_str(), nullptr);
    request.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .defect_removal_strength = 1.0;
    nf_grain_mend_detect_parameters_v3 parameters{};
    parameters.v2.v1.struct_size = static_cast<std::uint32_t>(sizeof(parameters));
    parameters.v2.v1.roi_x = 0.2;
    parameters.v2.v1.roi_y = 0.25;
    parameters.v2.v1.roi_width = 0.5;
    parameters.v2.v1.roi_height = 0.5;
    parameters.v2.dust_sensitivity = 1.0;
    parameters.v2.scratch_sensitivity = 1.0;
    parameters.v2.protect_detail = 0.6;
    parameters.detect_micro_specks = 1U;

    nf_grain_mend_detection_v2 detection{};
    detection.struct_size = static_cast<std::uint32_t>(sizeof(detection));
    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_detect_grain_mend_v4(
            &request, &parameters, nullptr, 0U, nullptr, &detection, &result) ==
                NF_STATUS_OK &&
            result.succeeded == 1U && detection.width > 0U && detection.height > 0U &&
            detection.mask_byte_count ==
                static_cast<std::uint64_t>(detection.width) * detection.height,
        "v4 GrainMend detection accepts the optional micro-speck setting");

    parameters.reserved = 1U;
    detection = {};
    detection.struct_size = static_cast<std::uint32_t>(sizeof(detection));
    result = make_result_v3();
    expect(
        nf_develop_detect_grain_mend_v4(
            &request, &parameters, nullptr, 0U, nullptr, &detection, &result) ==
            NF_STATUS_INVALID_ARGUMENT,
        "v4 GrainMend detection rejects nonzero micro-speck reserved field");
}

}  // namespace negaflow::develop_export_abi_tests
