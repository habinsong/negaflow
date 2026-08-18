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

// 미리보기 C ABI 진입점입니다. v11–v21 은 대상 파일을 쓰지 않습니다.

nf_status_t NF_CALL nf_develop_preview_v11(
    const nf_develop_export_request_v11* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v11(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v11(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v12(
    const nf_develop_export_request_v12* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v12(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v12(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v13(
    const nf_develop_export_request_v13* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v13(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v13(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v14(
    const nf_develop_export_request_v14* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v14(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v14(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v15(
    const nf_develop_export_request_v15* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v15(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v15(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v16(
    const nf_develop_export_request_v16* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v16(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v16(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v17(
    const nf_develop_export_request_v17* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v17(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v17(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v18(
    const nf_develop_export_request_v18* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v18(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v18(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v19(
    const nf_develop_export_request_v19* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v19(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v19(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v20(
    const nf_develop_export_request_v20* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v20(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v20(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v21(
    const nf_develop_export_request_v21* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v21(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v21(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}
