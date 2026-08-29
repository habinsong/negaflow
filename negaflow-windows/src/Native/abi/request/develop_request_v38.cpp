#include "develop_request_map.h"

#include "negaflow/abi/develop_output.h"

#include <cstdint>

namespace negaflow::abi::detail {

bool map_request_v38(
    const nf_develop_export_request_v38& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v37(request.v37, require_destination, pipeline_request, result)) {
        return false;
    }
    // 0 은 "원본 그대로" 입니다 — 사용자에게 나가는 내보내기는 전부 이 값입니다.
    pipeline_request.proxy_input_long_edge = request.proxy_input_long_edge;
    return true;
}

}  // namespace negaflow::abi::detail
