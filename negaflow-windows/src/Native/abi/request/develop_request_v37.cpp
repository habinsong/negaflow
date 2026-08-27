#include "develop_request_map.h"

#include "negaflow/abi/develop_output.h"

#include <cstdint>

namespace negaflow::abi::detail {

bool map_request_v37(
    const nf_develop_export_request_v37& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v36(request.v36, require_destination, pipeline_request, result)) {
        return false;
    }

    const bool has_pointer = request.output_icc_profile != nullptr;
    const bool has_size = request.output_icc_profile_size != 0U;
    if (!has_pointer && !has_size) {
        return true;
    }
    // 포인터와 길이는 함께 옵니다. 하나만 오면 호출자가 무엇을 하려던 것인지 알 수 없고,
    // 조용히 sRGB 로 내면 인화 결과가 달라집니다.
    if (!has_pointer || !has_size) {
        fail_defect_region_request(result, "invalid_output_icc_profile");
        return false;
    }
    // ICC 는 128 바이트 머리말을 갖습니다. 그보다 짧은 것은 프로파일이 아닙니다.
    if (request.output_icc_profile_size < 128U) {
        fail_defect_region_request(result, "invalid_output_icc_profile");
        return false;
    }
    pipeline_request.output_icc_profile = std::span<const std::uint8_t>(
        request.output_icc_profile,
        static_cast<std::size_t>(request.output_icc_profile_size));
    return true;
}

}  // namespace negaflow::abi::detail
