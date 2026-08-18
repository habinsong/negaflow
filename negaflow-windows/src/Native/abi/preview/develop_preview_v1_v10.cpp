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

// 미리보기 C ABI 진입점입니다. v1–v10 은 대상 파일을 쓰지 않습니다.

nf_status_t NF_CALL nf_develop_preview_v1(
    const nf_develop_export_request_v1* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v1* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request(*request, false, pipeline_request, *result)) {
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
    write_outcome(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v2(
    const nf_develop_export_request_v2* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v2(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v2(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v3(
    const nf_develop_export_request_v3* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v3(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v3(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v4(
    const nf_develop_export_request_v4* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v4(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v4(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v5(
    const nf_develop_export_request_v5* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v5(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v5(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v6(
    const nf_develop_export_request_v6* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v6(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v6(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v7(
    const nf_develop_export_request_v7* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v7(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v7(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v8(
    const nf_develop_export_request_v8* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v8(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v8(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v9(
    const nf_develop_export_request_v9* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v9(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v9(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v10(
    const nf_develop_export_request_v10* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v10(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v10(*request, false, pipeline_request, *result)) {
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
