#include "request/develop_request_map.h"

#include "support/abi_text.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <limits>
#include <new>
#include <string>
#include <string_view>
#include <vector>

namespace negaflow::abi::detail {

// 여러 요청 버전이 같이 쓰는 범위 검사와 결함 거부 기록입니다.

[[nodiscard]] bool valid_flat_range(
    const std::uint32_t offset,
    const std::uint32_t count,
    const std::uint32_t total) noexcept {
    return offset <= total && count <= total - offset;
}

void fail_defect_region_request(
    nf_develop_export_result_v2& result,
    const char* const failure_name) noexcept {
    result.succeeded = 0U;
    result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
    copy_failure_name(failure_name, result.failure_name);
}

}  // namespace negaflow::abi::detail
