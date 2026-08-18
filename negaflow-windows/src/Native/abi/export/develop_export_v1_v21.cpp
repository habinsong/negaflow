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

// 파일로 내보내는 C ABI 진입점입니다. v1–v21 은 실행 상태 없이 develop_and_export 만 부릅니다.

nf_status_t NF_CALL nf_develop_export_v1(
    const nf_develop_export_request_v1* const request,
    nf_develop_export_result_v1* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result(request, result, status)) {
        return status;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v2(
    const nf_develop_export_request_v2* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v2(request, result, status)) {
        return status;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v2(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v3(
    const nf_develop_export_request_v3* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v3(request, result, status)) {
        return status;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v3(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v4(
    const nf_develop_export_request_v4* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v4(request, result, status)) {
        return status;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v4(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v5(
    const nf_develop_export_request_v5* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v5(request, result, status)) {
        return status;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v5(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v6(
    const nf_develop_export_request_v6* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v6(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v6(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v7(
    const nf_develop_export_request_v7* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v7(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v7(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v8(
    const nf_develop_export_request_v8* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v8(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v8(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v9(
    const nf_develop_export_request_v9* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v9(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v9(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v10(
    const nf_develop_export_request_v10* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v10(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v10(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v11(
    const nf_develop_export_request_v11* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v11(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v11(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v12(
    const nf_develop_export_request_v12* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v12(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v12(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v13(
    const nf_develop_export_request_v13* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v13(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v13(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v14(
    const nf_develop_export_request_v14* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v14(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v14(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v15(
    const nf_develop_export_request_v15* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v15(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v15(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v16(
    const nf_develop_export_request_v16* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v16(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v16(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v17(
    const nf_develop_export_request_v17* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v17(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v17(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v18(
    const nf_develop_export_request_v18* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v18(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v18(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v19(
    const nf_develop_export_request_v19* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v19(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v19(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v20(
    const nf_develop_export_request_v20* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v20(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v20(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v21(
    const nf_develop_export_request_v21* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v21(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v21(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}
