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

// v24–v25: 적외선 편집과 적외선 항목.

[[nodiscard]] bool map_request_v24(
    const nf_develop_export_request_v24& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.defect_infrared_edit_reserved != 0U ||
        request.defect_infrared_attenuation_reserved != 0U ||
        request.defect_infrared_edit_count >
            NF_DEFECT_INFRARED_MAX_CLUSTERS ||
        request.defect_infrared_attenuation_byte_count >
            NF_DEFECT_INFRARED_MAX_ATTENUATION_BYTES ||
        (request.defect_infrared_edit_count != 0U &&
         request.defect_infrared_edits == nullptr) ||
        (request.defect_infrared_attenuation_byte_count != 0U &&
         request.defect_infrared_attenuation_bytes == nullptr) ||
        (request.defect_infrared_edit_count == 0U &&
         request.defect_infrared_attenuation_byte_count != 0U)) {
        fail_defect_region_request(result, "invalid_defect_infrared_payload");
        return false;
    }
    if (!map_request_v21(
            request.v21,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }

    try {
        auto& recipe = pipeline_request.defect_recipe;
        if (request.defect_infrared_edit_count > recipe.regions.edits.size()) {
            fail_defect_region_request(
                result, "invalid_defect_infrared_payload");
            return false;
        }
        const std::size_t absent = std::numeric_limits<std::size_t>::max();
        std::vector<std::size_t> region_to_infrared(
            recipe.regions.edits.size(), absent);
        recipe.infrared.reserve(request.defect_infrared_edit_count);
        std::uint64_t consumed_attenuation_bytes = 0U;
        for (std::uint32_t index = 0U;
             index < request.defect_infrared_edit_count;
             ++index) {
            const nf_defect_infrared_edit_v1& source =
                request.defect_infrared_edits[index];
            if (source.region_edit_index >= recipe.regions.edits.size() ||
                source.has_attenuation > 1U || source.reserved != 0U ||
                region_to_infrared[source.region_edit_index] != absent) {
                fail_defect_region_request(
                    result, "invalid_defect_infrared_payload");
                return false;
            }
            const negaflow::pipeline::DefectRegionEdit& region =
                recipe.regions.edits[source.region_edit_index];
            const std::uint64_t exact_core_bytes =
                static_cast<std::uint64_t>(region.width) * region.height;
            if (region.repair.has_preferred_angle ||
                region.mask_stride_bytes != region.width ||
                region.mask.size() != exact_core_bytes) {
                fail_defect_region_request(
                    result, "invalid_defect_infrared_payload");
                return false;
            }

            std::span<const std::uint8_t> attenuation{};
            std::size_t attenuation_stride = 0U;
            if (source.has_attenuation == 0U) {
                if (source.attenuation_stride_bytes != 0U ||
                    source.attenuation_offset != 0U ||
                    source.attenuation_byte_count != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_infrared_payload");
                    return false;
                }
            } else {
                const std::uint64_t row_bytes =
                    static_cast<std::uint64_t>(region.width) * 2U;
                const std::uint64_t required = region.height == 0U
                    ? 0U
                    : static_cast<std::uint64_t>(region.height - 1U) *
                              source.attenuation_stride_bytes +
                          row_bytes;
                if (source.attenuation_stride_bytes < row_bytes ||
                    required != source.attenuation_byte_count ||
                    source.attenuation_offset != consumed_attenuation_bytes ||
                    !valid_flat_range(
                        source.attenuation_offset,
                        source.attenuation_byte_count,
                        request.defect_infrared_attenuation_byte_count)) {
                    fail_defect_region_request(
                        result, "invalid_defect_infrared_payload");
                    return false;
                }
                consumed_attenuation_bytes += source.attenuation_byte_count;
                attenuation = std::span<const std::uint8_t>(
                    request.defect_infrared_attenuation_bytes +
                        source.attenuation_offset,
                    source.attenuation_byte_count);
                attenuation_stride = source.attenuation_stride_bytes;
            }
            region_to_infrared[source.region_edit_index] = index;
            negaflow::pipeline::DefectInfraredEdit cluster{
                true,
                region.roi_x,
                region.roi_y,
                region.width,
                region.height,
                region.mask,
                region.mask_stride_bytes,
                attenuation,
                attenuation_stride,
                1.0,
            };
            negaflow::pipeline::DefectInfraredItem item{};
            item.enabled = region.enabled;
            item.strength = region.repair.strength;
            item.clusters.push_back(std::move(cluster));
            recipe.infrared.push_back(std::move(item));
        }
        if (consumed_attenuation_bytes !=
            request.defect_infrared_attenuation_byte_count) {
            fail_defect_region_request(
                result, "invalid_defect_infrared_payload");
            return false;
        }

        std::vector<std::size_t> compact_region_index(
            recipe.regions.edits.size(), absent);
        std::vector<negaflow::pipeline::DefectRegionEdit> compact_regions;
        compact_regions.reserve(
            recipe.regions.edits.size() - request.defect_infrared_edit_count);
        for (std::size_t index = 0U;
             index < recipe.regions.edits.size();
             ++index) {
            if (region_to_infrared[index] != absent) {
                continue;
            }
            compact_region_index[index] = compact_regions.size();
            compact_regions.push_back(recipe.regions.edits[index]);
        }
        for (negaflow::pipeline::DefectRecipeEditRef& reference : recipe.order) {
            if (reference.kind !=
                negaflow::pipeline::DefectRecipeEditKind::region) {
                continue;
            }
            const std::size_t infrared_index =
                region_to_infrared[reference.index];
            if (infrared_index != absent) {
                reference.kind =
                    negaflow::pipeline::DefectRecipeEditKind::infrared;
                reference.index = infrared_index;
            } else {
                reference.index = compact_region_index[reference.index];
            }
        }
        recipe.regions.edits = std::move(compact_regions);
        return true;
    } catch (const std::bad_alloc&) {
        fail_defect_region_request(
            result, "defect_infrared_recipe_allocation_failed");
        return false;
    }
}

[[nodiscard]] bool map_request_v25(
    const nf_develop_export_request_v25& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.defect_infrared_item_reserved != 0U ||
        request.defect_infrared_item_count > NF_DEFECT_INFRARED_MAX_ITEMS ||
        (request.defect_infrared_item_count != 0U) !=
            (request.defect_infrared_items != nullptr)) {
        fail_defect_region_request(
            result, "invalid_defect_infrared_item_payload");
        return false;
    }
    const std::size_t flat_cluster_count =
        request.v24.defect_infrared_edit_count;
    if ((flat_cluster_count == 0U) !=
        (request.defect_infrared_item_count == 0U)) {
        fail_defect_region_request(
            result, "invalid_defect_infrared_item_payload");
        return false;
    }
    std::size_t preflight_clusters = 0U;
    for (std::uint32_t item_index = 0U;
         item_index < request.defect_infrared_item_count;
         ++item_index) {
        const nf_defect_infrared_item_v1& source =
            request.defect_infrared_items[item_index];
        if (source.reserved_0 != 0U || source.reserved_1 != 0U ||
            source.cluster_count == 0U ||
            source.cluster_offset != preflight_clusters ||
            source.cluster_count > flat_cluster_count - preflight_clusters) {
            fail_defect_region_request(
                result, "invalid_defect_infrared_item_payload");
            return false;
        }
        preflight_clusters += source.cluster_count;
    }
    if (preflight_clusters != flat_cluster_count) {
        fail_defect_region_request(
            result, "invalid_defect_infrared_item_payload");
        return false;
    }
    if (!map_request_v24(
            request.v24,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }

    try {
        auto& recipe = pipeline_request.defect_recipe;
        if (recipe.infrared.size() != flat_cluster_count) {
            fail_defect_region_request(
                result, "invalid_defect_infrared_item_payload");
            return false;
        }

        const std::size_t absent = std::numeric_limits<std::size_t>::max();
        std::vector<std::size_t> cluster_to_item(flat_cluster_count, absent);
        std::vector<std::size_t> cluster_ordinal(flat_cluster_count, absent);
        std::vector<negaflow::pipeline::DefectInfraredItem> grouped{};
        grouped.reserve(request.defect_infrared_item_count);
        std::size_t consumed_clusters = 0U;
        for (std::uint32_t item_index = 0U;
             item_index < request.defect_infrared_item_count;
             ++item_index) {
            const nf_defect_infrared_item_v1& source =
                request.defect_infrared_items[item_index];
            if (source.reserved_0 != 0U || source.reserved_1 != 0U ||
                source.cluster_count == 0U ||
                source.cluster_offset != consumed_clusters ||
                source.cluster_count > flat_cluster_count - consumed_clusters) {
                fail_defect_region_request(
                    result, "invalid_defect_infrared_item_payload");
                return false;
            }

            negaflow::pipeline::DefectInfraredItem item{};
            const auto& first = recipe.infrared[consumed_clusters];
            if (first.clusters.size() != 1U) {
                fail_defect_region_request(
                    result, "invalid_defect_infrared_item_payload");
                return false;
            }
            item.enabled = first.enabled;
            item.strength = first.strength;
            item.clusters.reserve(source.cluster_count);
            for (std::uint32_t ordinal = 0U;
                 ordinal < source.cluster_count;
                 ++ordinal) {
                const std::size_t flat_index = consumed_clusters + ordinal;
                auto& singleton = recipe.infrared[flat_index];
                if (singleton.clusters.size() != 1U ||
                    singleton.enabled != item.enabled ||
                    singleton.strength != item.strength) {
                    fail_defect_region_request(
                        result, "invalid_defect_infrared_item_payload");
                    return false;
                }
                cluster_to_item[flat_index] = item_index;
                cluster_ordinal[flat_index] = ordinal;
                item.clusters.push_back(std::move(singleton.clusters.front()));
            }
            consumed_clusters += source.cluster_count;
            grouped.push_back(std::move(item));
        }
        if (consumed_clusters != flat_cluster_count) {
            fail_defect_region_request(
                result, "invalid_defect_infrared_item_payload");
            return false;
        }

        std::vector<negaflow::pipeline::DefectRecipeEditRef> collapsed_order{};
        collapsed_order.reserve(
            recipe.order.size() - flat_cluster_count + grouped.size());
        std::vector<std::uint8_t> referenced_items(grouped.size(), 0U);
        std::size_t active_item = absent;
        std::size_t expected_ordinal = 0U;
        for (const auto reference : recipe.order) {
            if (reference.kind !=
                negaflow::pipeline::DefectRecipeEditKind::infrared) {
                if (active_item != absent) {
                    fail_defect_region_request(
                        result, "invalid_defect_infrared_item_payload");
                    return false;
                }
                collapsed_order.push_back(reference);
                continue;
            }
            if (reference.index >= flat_cluster_count) {
                fail_defect_region_request(
                    result, "invalid_defect_infrared_item_payload");
                return false;
            }
            const std::size_t item_index = cluster_to_item[reference.index];
            const std::size_t ordinal = cluster_ordinal[reference.index];
            if (item_index == absent || ordinal == absent) {
                fail_defect_region_request(
                    result, "invalid_defect_infrared_item_payload");
                return false;
            }
            if (ordinal == 0U) {
                if (active_item != absent || referenced_items[item_index] != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_infrared_item_payload");
                    return false;
                }
                referenced_items[item_index] = 1U;
                collapsed_order.push_back({
                    negaflow::pipeline::DefectRecipeEditKind::infrared,
                    item_index,
                });
                active_item = grouped[item_index].clusters.size() == 1U
                    ? absent
                    : item_index;
                expected_ordinal = 1U;
            } else {
                if (active_item != item_index || ordinal != expected_ordinal) {
                    fail_defect_region_request(
                        result, "invalid_defect_infrared_item_payload");
                    return false;
                }
                ++expected_ordinal;
                if (expected_ordinal == grouped[item_index].clusters.size()) {
                    active_item = absent;
                }
            }
        }
        if (active_item != absent ||
            !std::all_of(
                referenced_items.begin(),
                referenced_items.end(),
                [](const std::uint8_t value) { return value != 0U; })) {
            fail_defect_region_request(
                result, "invalid_defect_infrared_item_payload");
            return false;
        }

        recipe.infrared = std::move(grouped);
        recipe.order = std::move(collapsed_order);
        return true;
    } catch (const std::bad_alloc&) {
        fail_defect_region_request(
            result, "defect_infrared_recipe_allocation_failed");
        return false;
    }
}

}  // namespace negaflow::abi::detail
