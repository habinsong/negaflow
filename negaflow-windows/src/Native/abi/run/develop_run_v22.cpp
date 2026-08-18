#include "negaflow/abi/develop_entry.h"

#include "support/abi_text.h"
#include "request/develop_request_map.h"
#include "result/develop_result_write.h"

#include "negaflow/pipeline/develop_export.h"

#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>

using namespace negaflow::abi::detail;

// v22: 실행 상태(취소·진행)를 받는 첫 export/preview 진입점입니다.

nf_status_t NF_CALL nf_develop_export_v22(
    const nf_develop_export_request_v21* const request,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v3(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v21(*request, true, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request, control);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v22(
    const nf_develop_export_request_v21* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v3(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v21(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes),
            control);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}
