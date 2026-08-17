#include "result/develop_result_write.h"

#include "support/abi_text.h"

#include <chrono>
#include <cstdint>
#include <cstring>

namespace negaflow::abi::detail {

// v1–v12 결과 버퍼를 비우고 크기 계약을 검사합니다.

[[nodiscard]] bool prepare_result(
    const nf_develop_export_request_v1* const request,
    nf_develop_export_result_v1* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v2(
    const nf_develop_export_request_v2* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v3(
    const nf_develop_export_request_v3* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v4(
    const nf_develop_export_request_v4* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v5(
    const nf_develop_export_request_v5* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v6(
    const nf_develop_export_request_v6* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v7(
    const nf_develop_export_request_v7* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v8(
    const nf_develop_export_request_v8* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v9(
    const nf_develop_export_request_v9* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v10(
    const nf_develop_export_request_v10* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v11(
    const nf_develop_export_request_v11* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v12(
    const nf_develop_export_request_v12* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

}  // namespace negaflow::abi::detail
