#include "request/develop_request_map.h"

#include "support/abi_text.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <limits>
#include <new>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace negaflow::abi::detail {

// v18–v19: 결함 영역 편집과 마스크, 결함 원본 신원.

[[nodiscard]] bool map_request_v18(
    const nf_develop_export_request_v18& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v17(
            request.v17,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    if (request.defect_region_reserved != 0U ||
        request.defect_mask_reserved != 0U ||
        request.defect_region_edit_count >
            NF_DEFECT_RECIPE_MAX_NATIVE_REGION_DESCRIPTORS ||
        request.defect_mask_byte_count > NF_DEFECT_REGION_MAX_MASK_BYTES ||
        (request.defect_region_edit_count != 0U &&
         request.defect_region_edits == nullptr) ||
        (request.defect_mask_byte_count != 0U &&
         request.defect_mask_bytes == nullptr) ||
        (request.defect_region_edit_count == 0U &&
         request.defect_mask_byte_count != 0U)) {
        fail_defect_region_request(result, "invalid_defect_region_payload");
        return false;
    }

    try {
        std::size_t total_mask_bytes = 0U;
        pipeline_request.defect_recipe.regions.edits.reserve(
            request.defect_region_edit_count);
        pipeline_request.defect_recipe.order.reserve(
            request.defect_region_edit_count);
        for (std::uint32_t index = 0U;
             index < request.defect_region_edit_count;
             ++index) {
            const nf_defect_region_edit_v1& source =
                request.defect_region_edits[index];
            const std::uint64_t required = source.height == 0U
                ? 0U
                : static_cast<std::uint64_t>(source.height - 1U) *
                          source.mask_stride_bytes +
                      source.width;
            if (source.enabled > 1U || source.has_preferred_angle > 1U ||
                source.reserved != 0U || source.width <= 2U ||
                source.height <= 2U ||
                source.mask_stride_bytes < source.width ||
                required > source.mask_byte_count ||
                !valid_flat_range(
                    source.mask_offset,
                    source.mask_byte_count,
                    request.defect_mask_byte_count) ||
                !std::isfinite(source.strength) ||
                source.strength < 0.0 || source.strength > 1.0 ||
                !std::isfinite(source.preferred_angle_degrees) ||
                (source.has_preferred_angle == 0U &&
                 source.preferred_angle_degrees != 0.0) ||
                (source.has_preferred_angle != 0U &&
                 (source.preferred_angle_degrees < 0.0 ||
                  source.preferred_angle_degrees > 180.0)) ||
                source.mask_byte_count >
                    NF_DEFECT_REGION_MAX_MASK_BYTES - total_mask_bytes) {
                fail_defect_region_request(
                    result,
                    "invalid_defect_region_payload");
                return false;
            }
            total_mask_bytes += source.mask_byte_count;
            negaflow::pipeline::DefectRegionEdit edit{};
            edit.enabled = source.enabled != 0U;
            edit.roi_x = source.roi_x;
            edit.roi_y = source.roi_y;
            edit.width = source.width;
            edit.height = source.height;
            edit.mask = std::span<const std::uint8_t>(
                request.defect_mask_bytes + source.mask_offset,
                source.mask_byte_count);
            edit.mask_stride_bytes = source.mask_stride_bytes;
            edit.repair = {
                source.has_preferred_angle != 0U,
                source.preferred_angle_degrees,
                source.strength,
            };
            pipeline_request.defect_recipe.regions.edits.push_back(edit);
            pipeline_request.defect_recipe.order.push_back({
                negaflow::pipeline::DefectRecipeEditKind::region,
                pipeline_request.defect_recipe.regions.edits.size() - 1U,
            });
        }
    } catch (const std::bad_alloc&) {
        fail_defect_region_request(
            result,
            "defect_region_recipe_allocation_failed");
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v19(
    const nf_develop_export_request_v19& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v18(
            request.v18,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    const bool has_edits = request.v18.defect_region_edit_count != 0U;
    const bool has_identity = request.has_defect_source_identity != 0U;
    if (request.has_defect_source_identity > 1U || request.reserved != 0U ||
        has_edits != has_identity ||
        (!has_identity &&
         (request.defect_source_file_bytes != 0U ||
          request.defect_source_sha256 != nullptr)) ||
        (has_identity &&
         (request.defect_source_file_bytes == 0U ||
          request.defect_source_sha256 == nullptr))) {
        fail_defect_region_request(result, "invalid_defect_source_identity");
        return false;
    }
    if (has_identity) {
        negaflow::pipeline::ExpectedSourceIdentity identity{};
        identity.file_bytes = request.defect_source_file_bytes;
        std::memcpy(
            identity.sha256.data(),
            request.defect_source_sha256,
            identity.sha256.size());
        pipeline_request.expected_defect_source_identity = identity;
    }
    return true;
}

}  // namespace negaflow::abi::detail
