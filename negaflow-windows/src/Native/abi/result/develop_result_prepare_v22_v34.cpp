#include "result/develop_result_write.h"

#include "support/abi_text.h"

#include <chrono>
#include <cstdint>
#include <cstring>

namespace negaflow::abi::detail {

// v22 이후(결과 v3) 버퍼를 비우고 크기 계약을 검사합니다.

[[nodiscard]] bool prepare_result_v3(
    const nf_develop_export_request_v21* const request,
    nf_develop_export_result_v3* const result,
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

[[nodiscard]] bool prepare_result_v24(
    const nf_develop_export_request_v24* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
                .struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v25(
    const nf_develop_export_request_v25* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
                .struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v26(
    const nf_develop_export_request_v26* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
                .struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v27(
    const nf_develop_export_request_v27* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
                .struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v28(
    const nf_develop_export_request_v28* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9
                .v8.struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v29(
    const nf_develop_export_request_v29* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v28.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11
                .v10.v9.v8.struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v33(
    const nf_develop_export_request_v33* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v32.v31.v30.v29.v28.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12
                .v11.v10.v9.v8.struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    return true;
}

[[nodiscard]] bool prepare_result_v34(
    const nf_develop_export_request_v34* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v33.v32.v31.v30.v29.v28.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14
                .v13.v12.v11.v10.v9.v8.struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    return true;
}

[[nodiscard]] bool prepare_result_v35(
    const nf_develop_export_request_v35* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v34.v33.v32.v31.v30.v29.v28.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15
                .v14.v13.v12.v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    return true;
}

[[nodiscard]] bool prepare_result_v32(
    const nf_develop_export_request_v32* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v31.v30.v29.v28.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11
                .v10.v9.v8.struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    return true;
}

[[nodiscard]] bool prepare_result_v31(
    const nf_develop_export_request_v31* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v30.v29.v28.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11
                .v10.v9.v8.struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    return true;
}

[[nodiscard]] bool prepare_result_v30(
    const nf_develop_export_request_v30* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v29.v28.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11
                .v10.v9.v8.struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
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
