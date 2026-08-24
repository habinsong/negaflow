#include "request/develop_request_map.h"

#include "result/develop_result_write.h"

#include <array>
#include <cstdint>
#include <cstring>

namespace negaflow::abi::detail {

bool map_request_v36(
    const nf_develop_export_request_v36& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v35(request.v35, require_destination, pipeline_request, result)) {
        return false;
    }

    const bool has_prefix_pointer =
        request.defect_recipe_append_prefix_sha256 != nullptr;
    const bool has_prefix_size =
        request.defect_recipe_append_prefix_sha256_size != 0U;
    const bool has_prefix_count =
        request.defect_recipe_append_prefix_edit_count != 0U;
    if (!has_prefix_pointer && !has_prefix_size && !has_prefix_count) {
        return true;
    }
    if (!has_prefix_pointer ||
        request.defect_recipe_append_prefix_sha256_size != 32U ||
        request.defect_recipe_append_prefix_edit_count == 0U ||
        request.defect_recipe_append_prefix_edit_count >=
            pipeline_request.defect_recipe.order.size()) {
        fail_defect_region_request(result, "invalid_defect_recipe_append_prefix");
        return false;
    }

    std::array<std::uint8_t, 32U> digest{};
    std::memcpy(
        digest.data(),
        request.defect_recipe_append_prefix_sha256,
        digest.size());
    pipeline_request.defect_recipe_append_prefix_sha256 = digest;
    pipeline_request.defect_recipe_append_prefix_edit_count =
        request.defect_recipe_append_prefix_edit_count;
    return true;
}

}  // namespace negaflow::abi::detail
