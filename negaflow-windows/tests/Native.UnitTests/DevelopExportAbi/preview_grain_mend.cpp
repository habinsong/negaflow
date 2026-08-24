#include "develop_export_abi_test_support.h"
#include "synthetic_wic_tiff.h"

#include <algorithm>

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

void test_v7_grain_mend_review_handle() {
    expect(
        sizeof(nf_grain_mend_review_hit_v1) == 16U &&
            sizeof(nf_grain_mend_accepted_region_v1) == 40U,
        "v7 GrainMend review ABI layouts are fixed");

    constexpr std::uint32_t width = 320U;
    constexpr std::uint32_t height = 320U;
    const std::filesystem::path source =
        std::filesystem::temp_directory_path() / "negaflow-abi-grain-mend-v7.tif";
    std::error_code ignored{};
    std::filesystem::remove(source, ignored);
    const auto source_bytes =
        negaflow::test_fixtures::make_uncompressed_rgb16_defect_tiff(width, height);
    const bool fixture_ready = !source_bytes.empty() && write_file(source, source_bytes);
    expect(fixture_ready, "v7 GrainMend synthetic defect TIFF is written");
    if (!fixture_ready) return;

    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v27 request =
        make_request_v27(source_text.c_str(), nullptr);
    request.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .defect_removal_strength = 1.0;
    nf_grain_mend_detect_parameters_v3 parameters{};
    parameters.v2.v1.struct_size = static_cast<std::uint32_t>(sizeof(parameters));
    parameters.v2.v1.roi_width = 1.0;
    parameters.v2.v1.roi_height = 1.0;
    parameters.v2.dust_sensitivity = 1.0;
    parameters.v2.scratch_sensitivity = 1.0;
    parameters.v2.protect_detail = 0.0;
    parameters.detect_micro_specks = 0U;
    nf_grain_mend_detection_v4 detection{};
    detection.v3.v2.struct_size = static_cast<std::uint32_t>(sizeof(detection));
    nf_develop_export_result_v3 result = make_result_v3();
    nf_grain_mend_review_handle_v1* review = nullptr;
    nf_grain_mend_detection_v4 short_detection{};
    short_detection.v3.v2.struct_size =
        static_cast<std::uint32_t>(sizeof(short_detection) - 1U);
    nf_develop_export_result_v3 short_result = make_result_v3();
    auto* short_review = reinterpret_cast<nf_grain_mend_review_handle_v1*>(
        static_cast<std::uintptr_t>(1U));
    expect(
        nf_develop_detect_grain_mend_v7(
            &request,
            &parameters,
            nullptr,
            &short_detection,
            &short_result,
            &short_review) == NF_STATUS_INVALID_ARGUMENT &&
            short_review == nullptr &&
        nf_develop_detect_grain_mend_v7(
            &request, &parameters, nullptr, &detection, &result, nullptr) ==
            NF_STATUS_INVALID_ARGUMENT,
        "v7 rejects a short result or missing review output and clears ownership");

    detection = {};
    detection.v3.v2.struct_size = static_cast<std::uint32_t>(sizeof(detection));
    result = make_result_v3();
    const nf_status_t detect_status = nf_develop_detect_grain_mend_v7(
        &request, &parameters, nullptr, &detection, &result, &review);
    const bool detected =
        detect_status == NF_STATUS_OK && result.succeeded == 1U && review != nullptr &&
        detection.v3.component_count > 0U &&
        detection.v3.preview_point_count >= detection.v3.component_count &&
        detection.v3.v2.width == width && detection.v3.v2.height == height &&
        detection.v3.v2.mask_byte_count == static_cast<std::uint64_t>(width) * height;
    expect(detected, "v7 detects once and returns an exact transient review handle");
    if (!detected) {
        nf_grain_mend_review_destroy_v1(review);
        std::filesystem::remove(source, ignored);
        return;
    }

    std::vector<nf_grain_mend_component_v1> components(
        static_cast<std::size_t>(detection.v3.component_count));
    std::vector<nf_grain_mend_preview_point_v1> points(
        static_cast<std::size_t>(detection.v3.preview_point_count));
    const bool copied = nf_grain_mend_review_copy_components_v1(
        review,
        components.data(),
        components.size(),
        points.data(),
        points.size()) == NF_STATUS_OK;
    expect(
        copied && components.front().struct_size == sizeof(nf_grain_mend_component_v1) &&
            components.front().preview_point_count > 0U &&
            nf_grain_mend_review_copy_components_v1(
                nullptr,
                components.data(),
                components.size(),
                points.data(),
                points.size()) == NF_STATUS_INVALID_ARGUMENT &&
            nf_grain_mend_review_copy_components_v1(
                review,
                nullptr,
                components.size(),
                nullptr,
                0U) == NF_STATUS_INVALID_ARGUMENT &&
            nf_grain_mend_review_copy_components_v1(
                review,
                components.data(),
                components.size() - 1U,
                points.data(),
                points.size()) == NF_STATUS_INVALID_ARGUMENT,
        "v7 copies exact-sized metadata once and rejects a short component buffer");

    const auto first_point = points[components.front().preview_point_offset];
    nf_grain_mend_review_hit_v1 hit{};
    hit.struct_size = static_cast<std::uint32_t>(sizeof(hit));
    nf_grain_mend_review_hit_v1 short_hit{};
    short_hit.struct_size =
        static_cast<std::uint32_t>(sizeof(short_hit) - 1U);
    const bool hit_ok = nf_grain_mend_review_hit_test_v1(
        review,
        static_cast<std::int32_t>(first_point.x),
        static_cast<std::int32_t>(first_point.y),
        3U,
        &hit) == NF_STATUS_OK && hit.found == 1U &&
        hit.component_index < components.size();
    expect(hit_ok, "v7 hit-test returns an exact native component owner");
    expect(
        nf_grain_mend_review_hit_test_v1(review, 0, 0, 0U, &short_hit) ==
            NF_STATUS_STRUCT_TOO_SMALL &&
        nf_grain_mend_review_hit_test_v1(nullptr, 0, 0, 0U, &hit) ==
            NF_STATUS_INVALID_ARGUMENT,
        "v7 hit-test rejects short output and missing ownership");

    std::vector<std::uint8_t> excluded(components.size(), 0U);
    nf_grain_mend_accepted_region_v1 accepted{};
    accepted.struct_size = static_cast<std::uint32_t>(sizeof(accepted));
    nf_grain_mend_accepted_region_handle_v1* accepted_handle = nullptr;
    nf_grain_mend_accepted_region_v1 invalid_accepted{};
    invalid_accepted.struct_size =
        static_cast<std::uint32_t>(sizeof(invalid_accepted));
    auto* invalid_accepted_handle =
        reinterpret_cast<nf_grain_mend_accepted_region_handle_v1*>(
            static_cast<std::uintptr_t>(1U));
    expect(
        nf_grain_mend_review_build_accepted_v1(
            review,
            excluded.data(),
            excluded.size() - 1U,
            &invalid_accepted,
            &invalid_accepted_handle) == NF_STATUS_INVALID_ARGUMENT &&
            invalid_accepted_handle == nullptr,
        "v7 accepted-region build rejects a mismatched exclusion array and clears ownership");
    const bool accepted_ok = nf_grain_mend_review_build_accepted_v1(
        review,
        excluded.data(),
        excluded.size(),
        &accepted,
        &accepted_handle) == NF_STATUS_OK &&
        accepted.status == NF_GRAIN_MEND_ACCEPTED_OK && accepted_handle != nullptr &&
        accepted.width > 0U && accepted.height > 0U &&
        accepted.roi_x <= width && accepted.roi_y <= height &&
        accepted.width <= width - accepted.roi_x &&
        accepted.height <= height - accepted.roi_y &&
        accepted.mask_byte_count ==
            static_cast<std::uint64_t>(accepted.width) * accepted.height * 4U &&
        accepted.included_component_count == components.size();
    std::vector<std::uint8_t> rgba(
        accepted_ok ? static_cast<std::size_t>(accepted.mask_byte_count) : 0U);
    const bool mask_ok = accepted_ok &&
        nf_grain_mend_accepted_region_copy_mask_v1(
            accepted_handle, rgba.data(), rgba.size()) == NF_STATUS_OK &&
        std::any_of(rgba.begin(), rgba.end(), [](const std::uint8_t value) {
            return value != 0U;
        }) &&
        nf_grain_mend_accepted_region_copy_mask_v1(
            accepted_handle, rgba.data(), rgba.size() - 1U) ==
            NF_STATUS_INVALID_ARGUMENT;
    expect(
        accepted_ok && mask_ok,
        "v7 builds and copies one cropped RGBA8 accepted region without re-detection");
    expect(
        nf_grain_mend_accepted_region_copy_mask_v1(
            nullptr, rgba.data(), rgba.size()) == NF_STATUS_INVALID_ARGUMENT,
        "v7 accepted-region copy rejects missing ownership");

    std::fill(
        excluded.begin(), excluded.end(), static_cast<std::uint8_t>(1U));
    nf_grain_mend_accepted_region_v1 empty{};
    empty.struct_size = static_cast<std::uint32_t>(sizeof(empty));
    nf_grain_mend_accepted_region_handle_v1* empty_handle = nullptr;
    expect(
        nf_grain_mend_review_build_accepted_v1(
            review,
            excluded.data(),
            excluded.size(),
            &empty,
            &empty_handle) == NF_STATUS_OK &&
            empty.status == NF_GRAIN_MEND_ACCEPTED_EMPTY && empty_handle == nullptr &&
            empty.mask_byte_count == 0U,
        "v7 returns an explicit empty acceptance without allocating a handle");

    nf_grain_mend_accepted_region_destroy_v1(accepted_handle);
    nf_grain_mend_review_destroy_v1(review);

    nf_develop_run_state_v1 cancelled = make_run_state();
    cancelled.cancel_requested = 1U;
    nf_grain_mend_detection_v4 cancelled_detection{};
    cancelled_detection.v3.v2.struct_size =
        static_cast<std::uint32_t>(sizeof(cancelled_detection));
    nf_develop_export_result_v3 cancelled_result = make_result_v3();
    auto* cancelled_review =
        reinterpret_cast<nf_grain_mend_review_handle_v1*>(
            static_cast<std::uintptr_t>(1U));
    expect(
        nf_develop_detect_grain_mend_v7(
            &request,
            &parameters,
            &cancelled,
            &cancelled_detection,
            &cancelled_result,
            &cancelled_review) == NF_STATUS_OK &&
            cancelled_result.succeeded == 0U && cancelled_result.cancelled == 1U &&
            cancelled_review == nullptr,
        "v7 cancellation returns no transient review ownership");
    nf_grain_mend_accepted_region_destroy_v1(nullptr);
    nf_grain_mend_review_destroy_v1(nullptr);
    std::filesystem::remove(source, ignored);
}

}  // namespace negaflow::develop_export_abi_tests
