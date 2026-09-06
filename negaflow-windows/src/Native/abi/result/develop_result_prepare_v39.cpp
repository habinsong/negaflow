#include "result/develop_result_write.h"
#include <cstring>

namespace negaflow::abi::detail {
bool prepare_result_v39(const nf_develop_export_request_v39* request,
                        nf_develop_export_result_v3* result, nf_status_t& status) noexcept {
    if (result == nullptr) { status = NF_STATUS_INVALID_ARGUMENT; return false; }
    const auto capacity = result->struct_size;
    if (capacity < sizeof(*result)) { status = NF_STATUS_STRUCT_TOO_SMALL; return false; }
    const auto known_size = capacity >= sizeof(nf_develop_export_result_v6) ? sizeof(nf_develop_export_result_v6)
        : capacity >= sizeof(nf_develop_export_result_v5) ? sizeof(nf_develop_export_result_v5)
        : capacity >= sizeof(nf_develop_export_result_v4) ? sizeof(nf_develop_export_result_v4) : sizeof(*result);
    std::memset(result, 0, known_size);
    result->struct_size = capacity;
    if (request == nullptr) { status = NF_STATUS_INVALID_ARGUMENT; return false; }
    std::uint32_t request_size = 0U;
    std::memcpy(&request_size, request, sizeof(request_size));
    if (request_size < sizeof(*request)) { status = NF_STATUS_STRUCT_TOO_SMALL; return false; }
    return true;
}
}  // namespace negaflow::abi::detail
