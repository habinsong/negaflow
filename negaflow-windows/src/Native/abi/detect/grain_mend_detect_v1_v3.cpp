#include "negaflow/abi/grain_mend_detect.h"

#include "support/abi_text.h"
#include "request/develop_request_map.h"
#include "result/develop_result_write.h"

#include "negaflow/pipeline/develop_export.h"

#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>

using namespace negaflow::abi::detail;

// GrainMend 자동 검출 C ABI v1-v3 입니다. 공유 몸통이 생기기 전의 고정 진입점이라
// 각자 자기 검출을 부릅니다. 새 버전은 grain_mend_detect_abi.cpp 로 갑니다.

nf_status_t NF_CALL nf_develop_detect_grain_mend_v1(
    const nf_develop_export_request_v27* const request,
    uint8_t* const mask,
    const uint64_t mask_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_grain_mend_detection_v1* const detection,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v27(request, result, status)) {
        return status;
    }
    if (detection == nullptr ||
        detection->struct_size < static_cast<std::uint32_t>(sizeof(*detection))) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    detection->width = 0U;
    detection->height = 0U;
    detection->accepted_pixels = 0U;
    detection->mask_byte_count = 0U;
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v27(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::GrainMendDetectionOutcome detected =
        negaflow::pipeline::develop_detect_grain_mend(
            pipeline_request,
            mask,
            static_cast<std::size_t>(mask_capacity_bytes),
            control);
    const auto finished = std::chrono::steady_clock::now();
    // 버퍼가 모자라 실패한 경우에도 필요한 크기는 알려 줍니다 — 그래야 한 번 더 부르면 됩니다.
    detection->width = detected.width;
    detection->height = detected.height;
    detection->accepted_pixels = detected.accepted_pixels;
    detection->mask_byte_count = detected.mask_byte_count;
    write_outcome_v3(
        detected.outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_detect_grain_mend_v2(
    const nf_develop_export_request_v27* const request,
    const nf_grain_mend_detect_parameters_v1* const parameters,
    uint8_t* const mask,
    const uint64_t mask_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_grain_mend_detection_v2* const detection,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v27(request, result, status)) {
        return status;
    }
    if (parameters == nullptr ||
        parameters->struct_size < static_cast<std::uint32_t>(sizeof(*parameters)) ||
        parameters->reserved != 0U || detection == nullptr ||
        detection->struct_size < static_cast<std::uint32_t>(sizeof(*detection))) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    detection->width = 0U;
    detection->height = 0U;
    detection->accepted_pixels = 0U;
    detection->mask_byte_count = 0U;
    detection->source_width = 0U;
    detection->source_height = 0U;
    detection->roi_x = 0U;
    detection->roi_y = 0U;
    detection->roi_width = 0U;
    detection->roi_height = 0U;
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v27(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const negaflow::imaging::GrainMendRoi roi{
        parameters->roi_x,
        parameters->roi_y,
        parameters->roi_width,
        parameters->roi_height,
    };
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::GrainMendDetectionOutcome detected =
        negaflow::pipeline::develop_detect_grain_mend(
            pipeline_request,
            mask,
            static_cast<std::size_t>(mask_capacity_bytes),
            control,
            roi);
    const auto finished = std::chrono::steady_clock::now();
    detection->width = detected.width;
    detection->height = detected.height;
    detection->accepted_pixels = detected.accepted_pixels;
    detection->mask_byte_count = detected.mask_byte_count;
    detection->source_width = detected.source_width;
    detection->source_height = detected.source_height;
    detection->roi_x = detected.roi_x;
    detection->roi_y = detected.roi_y;
    detection->roi_width = detected.roi_width;
    detection->roi_height = detected.roi_height;
    write_outcome_v3(
        detected.outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_detect_grain_mend_v3(
    const nf_develop_export_request_v27* const request,
    const nf_grain_mend_detect_parameters_v2* const parameters,
    uint8_t* const mask,
    const uint64_t mask_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_grain_mend_detection_v2* const detection,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v27(request, result, status)) {
        return status;
    }
    if (parameters == nullptr ||
        parameters->v1.struct_size < static_cast<std::uint32_t>(sizeof(*parameters)) ||
        parameters->v1.reserved != 0U || parameters->reserved != 0U ||
        !std::isfinite(parameters->dust_sensitivity) ||
        !std::isfinite(parameters->scratch_sensitivity) ||
        !std::isfinite(parameters->protect_detail) ||
        parameters->dust_sensitivity < negaflow::imaging::minimum_grain_mend_sensitivity ||
        parameters->dust_sensitivity > negaflow::imaging::maximum_grain_mend_sensitivity ||
        parameters->scratch_sensitivity < negaflow::imaging::minimum_grain_mend_sensitivity ||
        parameters->scratch_sensitivity > negaflow::imaging::maximum_grain_mend_sensitivity ||
        parameters->protect_detail < negaflow::imaging::minimum_grain_mend_sensitivity ||
        parameters->protect_detail > negaflow::imaging::maximum_grain_mend_sensitivity ||
        detection == nullptr ||
        detection->struct_size < static_cast<std::uint32_t>(sizeof(*detection))) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    detection->width = 0U;
    detection->height = 0U;
    detection->accepted_pixels = 0U;
    detection->mask_byte_count = 0U;
    detection->source_width = 0U;
    detection->source_height = 0U;
    detection->roi_x = 0U;
    detection->roi_y = 0U;
    detection->roi_width = 0U;
    detection->roi_height = 0U;
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v27(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    pipeline_request.grain_mend.dust_sensitivity = parameters->dust_sensitivity;
    pipeline_request.grain_mend.scratch_sensitivity = parameters->scratch_sensitivity;
    pipeline_request.grain_mend.protect_detail = parameters->protect_detail;
    pipeline_request.grain_mend.reject_structure_lines =
        parameters->reject_structure_lines != 0U;
    pipeline_request.grain_mend.detect_micro_specks = false;
    const negaflow::imaging::GrainMendRoi roi{
        parameters->v1.roi_x,
        parameters->v1.roi_y,
        parameters->v1.roi_width,
        parameters->v1.roi_height,
    };
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::GrainMendDetectionOutcome detected =
        negaflow::pipeline::develop_detect_grain_mend(
            pipeline_request,
            mask,
            static_cast<std::size_t>(mask_capacity_bytes),
            control,
            roi);
    const auto finished = std::chrono::steady_clock::now();
    detection->width = detected.width;
    detection->height = detected.height;
    detection->accepted_pixels = detected.accepted_pixels;
    detection->mask_byte_count = detected.mask_byte_count;
    detection->source_width = detected.source_width;
    detection->source_height = detected.source_height;
    detection->roi_x = detected.roi_x;
    detection->roi_y = detected.roi_y;
    detection->roi_width = detected.roi_width;
    detection->roi_height = detected.roi_height;
    write_outcome_v3(
        detected.outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}
