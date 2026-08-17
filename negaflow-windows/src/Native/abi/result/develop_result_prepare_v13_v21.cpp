#include "result/develop_result_write.h"

#include "support/abi_text.h"

#include <chrono>
#include <cstdint>
#include <cstring>

namespace negaflow::abi::detail {

// v13–v21 결과 버퍼를 비우고 크기 계약을 검사합니다.

[[nodiscard]] bool prepare_result_v13(
    const nf_develop_export_request_v13* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v12.v11.v10.v9.v8.struct_size <
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

[[nodiscard]] bool prepare_result_v14(
    const nf_develop_export_request_v14* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v13.v12.v11.v10.v9.v8.struct_size <
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

[[nodiscard]] bool prepare_result_v15(
    const nf_develop_export_request_v15* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v14.v13.v12.v11.v10.v9.v8.struct_size <
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

[[nodiscard]] bool prepare_result_v16(
    const nf_develop_export_request_v16* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
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

[[nodiscard]] bool prepare_result_v17(
    const nf_develop_export_request_v17* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
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

[[nodiscard]] bool prepare_result_v18(
    const nf_develop_export_request_v18* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
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

[[nodiscard]] bool prepare_result_v19(
    const nf_develop_export_request_v19* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
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

[[nodiscard]] bool prepare_result_v20(
    const nf_develop_export_request_v20* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
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

[[nodiscard]] bool prepare_result_v21(
    const nf_develop_export_request_v21* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
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
