#pragma once

#include "negaflow/abi/develop_output.h"
#include "negaflow/abi/develop_result.h"

#include "negaflow/pipeline/develop_export.h"

#include <chrono>
#include <cstdint>

namespace negaflow::abi::detail {

// 파이프라인 결과를 C ABI 결과 구조체에 씁니다.
// prepare_* 는 진입점이 호출하기 전에 결과 버퍼를 비웁니다.

[[nodiscard]] std::uint64_t elapsed_microseconds(
    const std::chrono::steady_clock::time_point started,
    const std::chrono::steady_clock::time_point finished) noexcept;

void write_outcome(
    const negaflow::pipeline::DevelopExportOutcome& outcome,
    const std::uint64_t wall_microseconds,
    nf_develop_export_result_v1& result) noexcept;

void write_outcome_v2(
    const negaflow::pipeline::DevelopExportOutcome& outcome,
    const std::uint64_t wall_microseconds,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool prepare_result(
    const nf_develop_export_request_v1* const request,
    nf_develop_export_result_v1* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v2(
    const nf_develop_export_request_v2* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v3(
    const nf_develop_export_request_v3* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v4(
    const nf_develop_export_request_v4* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v5(
    const nf_develop_export_request_v5* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v6(
    const nf_develop_export_request_v6* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v7(
    const nf_develop_export_request_v7* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v8(
    const nf_develop_export_request_v8* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v9(
    const nf_develop_export_request_v9* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v10(
    const nf_develop_export_request_v10* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v11(
    const nf_develop_export_request_v11* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v12(
    const nf_develop_export_request_v12* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v13(
    const nf_develop_export_request_v13* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v14(
    const nf_develop_export_request_v14* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v15(
    const nf_develop_export_request_v15* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v16(
    const nf_develop_export_request_v16* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v17(
    const nf_develop_export_request_v17* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v18(
    const nf_develop_export_request_v18* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v19(
    const nf_develop_export_request_v19* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v20(
    const nf_develop_export_request_v20* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v21(
    const nf_develop_export_request_v21* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v3(
    const nf_develop_export_request_v21* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v24(
    const nf_develop_export_request_v24* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v25(
    const nf_develop_export_request_v25* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v26(
    const nf_develop_export_request_v26* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v27(
    const nf_develop_export_request_v27* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v28(
    const nf_develop_export_request_v28* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v29(
    const nf_develop_export_request_v29* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v33(
    const nf_develop_export_request_v33* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v34(
    const nf_develop_export_request_v34* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v32(
    const nf_develop_export_request_v32* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v31(
    const nf_develop_export_request_v31* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_result_v30(
    const nf_develop_export_request_v30* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept;

[[nodiscard]] bool prepare_run_state(
    nf_develop_run_state_v1* const run_state,
    negaflow::pipeline::DevelopRunControl& control,
    nf_status_t& status) noexcept;

void write_request_rejection_v3(
    const nf_develop_export_result_v2& mapping_result,
    nf_develop_export_result_v3& result) noexcept;

void write_outcome_v3(
    const negaflow::pipeline::DevelopExportOutcome& outcome,
    const std::uint64_t wall_microseconds,
    nf_develop_export_result_v3& result) noexcept;

}  // namespace negaflow::abi::detail
