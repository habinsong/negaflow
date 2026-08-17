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

// v20–v21: 복제 도장과 브러시 편집, 편집 순서.

[[nodiscard]] bool map_source_identity_v20(
    const nf_develop_export_request_v19& request,
    const bool has_edits,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
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

[[nodiscard]] bool map_request_v20_core(
    const nf_develop_export_request_v20& request,
    const bool require_destination,
    const std::uint32_t brush_count,
    const bool allow_brush,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    const std::uint64_t expected_order_count =
        static_cast<std::uint64_t>(request.v19.v18.defect_region_edit_count) +
        request.defect_clone_edit_count + brush_count;
    if (request.defect_clone_edit_reserved != 0U ||
        request.defect_clone_stroke_reserved != 0U ||
        request.defect_clone_point_reserved != 0U ||
        request.defect_edit_order_reserved != 0U ||
        request.defect_clone_edit_count > NF_DEFECT_CLONE_MAX_EDITS ||
        request.defect_clone_stroke_count > NF_DEFECT_CLONE_MAX_STROKES ||
        request.defect_clone_point_count > NF_DEFECT_CLONE_MAX_POINTS ||
        request.defect_edit_order_count >
            NF_DEFECT_RECIPE_MAX_ORDERED_EDITS ||
        request.defect_edit_order_count != expected_order_count ||
        (request.defect_clone_edit_count != 0U &&
         request.defect_clone_edits == nullptr) ||
        (request.defect_clone_stroke_count != 0U &&
         request.defect_clone_strokes == nullptr) ||
        (request.defect_clone_point_count != 0U &&
         request.defect_clone_points == nullptr) ||
        (request.defect_edit_order_count != 0U &&
         request.defect_edit_order == nullptr) ||
        (request.defect_clone_edit_count == 0U &&
         (request.defect_clone_stroke_count != 0U ||
          request.defect_clone_point_count != 0U))) {
        fail_defect_region_request(result, "invalid_defect_clone_payload");
        return false;
    }
    if (!map_request_v18(
            request.v19.v18,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }

    try {
        std::vector<std::uint8_t> referenced_strokes(
            request.defect_clone_stroke_count, 0U);
        std::vector<std::uint8_t> referenced_points(
            request.defect_clone_point_count, 0U);
        auto& recipe = pipeline_request.defect_recipe;
        recipe.order.clear();
        recipe.clone_points_storage.reserve(request.defect_clone_point_count);
        for (std::uint32_t index = 0U;
             index < request.defect_clone_point_count;
             ++index) {
            const nf_defect_clone_point_v1 source =
                request.defect_clone_points[index];
            if (!std::isfinite(source.x) || !std::isfinite(source.y)) {
                fail_defect_region_request(
                    result, "invalid_defect_clone_payload");
                return false;
            }
            recipe.clone_points_storage.push_back({source.x, source.y});
        }

        recipe.clone_strokes_storage.reserve(
            request.defect_clone_stroke_count);
        for (std::uint32_t index = 0U;
             index < request.defect_clone_stroke_count;
             ++index) {
            const nf_defect_clone_stroke_v1& source =
                request.defect_clone_strokes[index];
            if (!valid_flat_range(
                    source.point_offset,
                    source.point_count,
                    request.defect_clone_point_count) ||
                !std::isfinite(source.offset_x) ||
                !std::isfinite(source.offset_y) ||
                !std::isfinite(source.diameter_pixels) ||
                source.diameter_pixels <= 0.0 ||
                !std::isfinite(source.hardness) ||
                source.hardness < 0.0 || source.hardness > 1.0) {
                fail_defect_region_request(
                    result, "invalid_defect_clone_payload");
                return false;
            }
            for (std::uint32_t point = 0U; point < source.point_count; ++point) {
                std::uint8_t& marker = referenced_points[
                    static_cast<std::size_t>(source.point_offset) + point];
                if (marker != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_clone_payload");
                    return false;
                }
                marker = 1U;
            }
            const negaflow::imaging::DefectClonePoint* stroke_points =
                source.point_count == 0U
                ? nullptr
                : recipe.clone_points_storage.data() + source.point_offset;
            recipe.clone_strokes_storage.push_back({
                std::span<const negaflow::imaging::DefectClonePoint>(
                    stroke_points,
                    source.point_count),
                source.offset_x,
                source.offset_y,
                source.diameter_pixels,
                source.hardness,
            });
        }
        if (!std::all_of(
                referenced_points.begin(),
                referenced_points.end(),
                [](const std::uint8_t value) { return value != 0U; })) {
            fail_defect_region_request(
                result, "invalid_defect_clone_payload");
            return false;
        }

        recipe.clones.reserve(request.defect_clone_edit_count);
        for (std::uint32_t index = 0U;
             index < request.defect_clone_edit_count;
             ++index) {
            const nf_defect_clone_edit_v1& source =
                request.defect_clone_edits[index];
            if (source.enabled > 1U || source.reserved != 0U ||
                !valid_flat_range(
                    source.stroke_offset,
                    source.stroke_count,
                    request.defect_clone_stroke_count) ||
                !std::isfinite(source.strength) || source.strength < 0.0 ||
                source.strength > 1.0) {
                fail_defect_region_request(
                    result, "invalid_defect_clone_payload");
                return false;
            }
            for (std::uint32_t stroke = 0U;
                 stroke < source.stroke_count;
                 ++stroke) {
                std::uint8_t& marker = referenced_strokes[
                    static_cast<std::size_t>(source.stroke_offset) + stroke];
                if (marker != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_clone_payload");
                    return false;
                }
                marker = 1U;
            }
            const negaflow::imaging::DefectCloneStroke* edit_strokes =
                source.stroke_count == 0U
                ? nullptr
                : recipe.clone_strokes_storage.data() + source.stroke_offset;
            recipe.clones.push_back({
                source.enabled != 0U,
                {
                    std::span<const negaflow::imaging::DefectCloneStroke>(
                        edit_strokes,
                        source.stroke_count),
                    source.strength,
                },
            });
        }
        if (!std::all_of(
                referenced_strokes.begin(),
                referenced_strokes.end(),
                [](const std::uint8_t value) { return value != 0U; })) {
            fail_defect_region_request(
                result, "invalid_defect_clone_payload");
            return false;
        }

        std::vector<std::uint8_t> referenced_regions(
            request.v19.v18.defect_region_edit_count, 0U);
        std::vector<std::uint8_t> referenced_clones(
            request.defect_clone_edit_count, 0U);
        std::vector<std::uint8_t> referenced_brushes(brush_count, 0U);
        recipe.order.reserve(request.defect_edit_order_count);
        for (std::uint32_t position = 0U;
             position < request.defect_edit_order_count;
             ++position) {
            const nf_defect_recipe_edit_ref_v1 source =
                request.defect_edit_order[position];
            if (source.kind == NF_DEFECT_RECIPE_EDIT_REGION) {
                if (source.index >= referenced_regions.size() ||
                    referenced_regions[source.index] != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_edit_order");
                    return false;
                }
                referenced_regions[source.index] = 1U;
                recipe.order.push_back({
                    negaflow::pipeline::DefectRecipeEditKind::region,
                    source.index,
                });
            } else if (source.kind == NF_DEFECT_RECIPE_EDIT_CLONE) {
                if (source.index >= referenced_clones.size() ||
                    referenced_clones[source.index] != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_edit_order");
                    return false;
                }
                referenced_clones[source.index] = 1U;
                recipe.order.push_back({
                    negaflow::pipeline::DefectRecipeEditKind::clone,
                    source.index,
                });
            } else if (allow_brush &&
                       source.kind == NF_DEFECT_RECIPE_EDIT_BRUSH) {
                if (source.index >= referenced_brushes.size() ||
                    referenced_brushes[source.index] != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_edit_order");
                    return false;
                }
                referenced_brushes[source.index] = 1U;
                recipe.order.push_back({
                    negaflow::pipeline::DefectRecipeEditKind::brush,
                    source.index,
                });
            } else {
                fail_defect_region_request(
                    result, "invalid_defect_edit_order");
                return false;
            }
        }
        if (!std::all_of(
                referenced_regions.begin(),
                referenced_regions.end(),
                [](const std::uint8_t value) { return value != 0U; }) ||
            !std::all_of(
                referenced_clones.begin(),
                referenced_clones.end(),
                [](const std::uint8_t value) { return value != 0U; }) ||
            !std::all_of(
                referenced_brushes.begin(),
                referenced_brushes.end(),
                [](const std::uint8_t value) { return value != 0U; })) {
            fail_defect_region_request(result, "invalid_defect_edit_order");
            return false;
        }
    } catch (const std::bad_alloc&) {
        fail_defect_region_request(
        result, "defect_clone_recipe_allocation_failed");
        return false;
    }

    const bool has_edits = expected_order_count != 0U;
    return map_source_identity_v20(
        request.v19,
        has_edits,
        pipeline_request,
        result);
}

[[nodiscard]] bool map_request_v20(
    const nf_develop_export_request_v20& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    return map_request_v20_core(
        request,
        require_destination,
        0U,
        false,
        pipeline_request,
        result);
}

[[nodiscard]] bool map_request_v21(
    const nf_develop_export_request_v21& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.defect_brush_edit_reserved != 0U ||
        request.defect_brush_stroke_reserved != 0U ||
        request.defect_brush_point_reserved != 0U ||
        request.defect_brush_edit_count > NF_DEFECT_BRUSH_MAX_EDITS ||
        request.defect_brush_stroke_count > NF_DEFECT_BRUSH_MAX_STROKES ||
        request.defect_brush_point_count > NF_DEFECT_BRUSH_MAX_POINTS ||
        (request.defect_brush_edit_count != 0U &&
         request.defect_brush_edits == nullptr) ||
        (request.defect_brush_stroke_count != 0U &&
         request.defect_brush_strokes == nullptr) ||
        (request.defect_brush_point_count != 0U &&
         request.defect_brush_points == nullptr) ||
        (request.defect_brush_edit_count == 0U &&
         (request.defect_brush_stroke_count != 0U ||
          request.defect_brush_point_count != 0U))) {
        fail_defect_region_request(result, "invalid_defect_brush_payload");
        return false;
    }
    try {
        auto& recipe = pipeline_request.defect_recipe;
        std::vector<std::uint8_t> referenced_strokes(
            request.defect_brush_stroke_count, 0U);
        std::vector<std::uint8_t> referenced_points(
            request.defect_brush_point_count, 0U);
        recipe.brush_points_storage.reserve(request.defect_brush_point_count);
        for (std::uint32_t index = 0U;
             index < request.defect_brush_point_count;
             ++index) {
            const nf_defect_brush_point_v1 source =
                request.defect_brush_points[index];
            if (!std::isfinite(source.x) || !std::isfinite(source.y) ||
                source.x < 0.0 || source.x > 1.0 ||
                source.y < 0.0 || source.y > 1.0) {
                fail_defect_region_request(
                    result, "invalid_defect_brush_payload");
                return false;
            }
            recipe.brush_points_storage.push_back({source.x, source.y});
        }
        recipe.brush_strokes_storage.reserve(
            request.defect_brush_stroke_count);
        for (std::uint32_t index = 0U;
             index < request.defect_brush_stroke_count;
             ++index) {
            const nf_defect_brush_stroke_v1& source =
                request.defect_brush_strokes[index];
            if (!valid_flat_range(
                    source.point_offset,
                    source.point_count,
                    request.defect_brush_point_count) ||
                !std::isfinite(source.thickness) || source.thickness < 0.0 ||
                source.thickness > 1.0) {
                fail_defect_region_request(
                    result, "invalid_defect_brush_payload");
                return false;
            }
            for (std::uint32_t point = 0U; point < source.point_count; ++point) {
                std::uint8_t& marker = referenced_points[
                    static_cast<std::size_t>(source.point_offset) + point];
                if (marker != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_brush_payload");
                    return false;
                }
                marker = 1U;
            }
            const negaflow::imaging::DefectBrushPoint* points =
                source.point_count == 0U
                ? nullptr
                : recipe.brush_points_storage.data() + source.point_offset;
            recipe.brush_strokes_storage.push_back({
                std::span<const negaflow::imaging::DefectBrushPoint>(
                    points, source.point_count),
                source.thickness,
            });
        }
        if (!std::all_of(
                referenced_points.begin(),
                referenced_points.end(),
                [](const std::uint8_t value) { return value != 0U; })) {
            fail_defect_region_request(
                result, "invalid_defect_brush_payload");
            return false;
        }
        recipe.brushes.reserve(request.defect_brush_edit_count);
        for (std::uint32_t index = 0U;
             index < request.defect_brush_edit_count;
             ++index) {
            const nf_defect_brush_edit_v1& source =
                request.defect_brush_edits[index];
            if (source.enabled > 1U || source.reserved != 0U ||
                !valid_flat_range(
                    source.stroke_offset,
                    source.stroke_count,
                    request.defect_brush_stroke_count) ||
                !std::isfinite(source.strength) || source.strength < 0.0 ||
                source.strength > 1.0) {
                fail_defect_region_request(
                    result, "invalid_defect_brush_payload");
                return false;
            }
            for (std::uint32_t stroke = 0U;
                 stroke < source.stroke_count;
                 ++stroke) {
                std::uint8_t& marker = referenced_strokes[
                    static_cast<std::size_t>(source.stroke_offset) + stroke];
                if (marker != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_brush_payload");
                    return false;
                }
                marker = 1U;
            }
            const negaflow::imaging::DefectBrushStroke* strokes =
                source.stroke_count == 0U
                ? nullptr
                : recipe.brush_strokes_storage.data() + source.stroke_offset;
            recipe.brushes.push_back({
                source.enabled != 0U,
                {
                    std::span<const negaflow::imaging::DefectBrushStroke>(
                        strokes, source.stroke_count),
                    source.strength,
                },
            });
        }
        if (!std::all_of(
                referenced_strokes.begin(),
                referenced_strokes.end(),
                [](const std::uint8_t value) { return value != 0U; })) {
            fail_defect_region_request(
                result, "invalid_defect_brush_payload");
            return false;
        }
    } catch (const std::bad_alloc&) {
        fail_defect_region_request(
            result, "defect_brush_recipe_allocation_failed");
        return false;
    }
    return map_request_v20_core(
        request.v20,
        require_destination,
        request.defect_brush_edit_count,
        true,
        pipeline_request,
        result);
}

}  // namespace negaflow::abi::detail
