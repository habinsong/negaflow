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

// v12–v17: 로컬 닷지/번, 색 모형, 자동 보정, 현상 타깃, 스캐너, 필름 극성.

void fail_local_dodge_burn_request(
    nf_develop_export_result_v2& result,
    const char* const failure_name) noexcept {
    result.succeeded = 0U;
    result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
    copy_failure_name(failure_name, result.failure_name);
}

[[nodiscard]] bool map_request_v12(
    const nf_develop_export_request_v12& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v11(
            request.v11,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    if (request.local_adjustment_reserved != 0U ||
        request.local_stroke_reserved != 0U ||
        request.local_point_reserved != 0U ||
        request.local_adjustment_count > NF_LOCAL_DODGE_BURN_MAX_ADJUSTMENTS ||
        request.local_stroke_count > NF_LOCAL_DODGE_BURN_MAX_STROKES ||
        request.local_point_count > NF_LOCAL_DODGE_BURN_MAX_POINTS ||
        (request.local_adjustment_count != 0U &&
         request.local_adjustments == nullptr) ||
        (request.local_stroke_count != 0U && request.local_strokes == nullptr) ||
        (request.local_point_count != 0U && request.local_points == nullptr)) {
        fail_local_dodge_burn_request(
            result,
            "invalid_local_dodge_burn_payload");
        return false;
    }

    try {
        for (std::uint32_t index = 0U; index < request.local_point_count; ++index) {
            const nf_local_dodge_burn_point_v1& point =
                request.local_points[index];
            if (!std::isfinite(point.x) || !std::isfinite(point.y)) {
                fail_local_dodge_burn_request(
                    result,
                    "invalid_local_dodge_burn_payload");
                return false;
            }
        }
        for (std::uint32_t index = 0U; index < request.local_stroke_count; ++index) {
            const nf_local_dodge_burn_stroke_v1& stroke =
                request.local_strokes[index];
            if (!valid_flat_range(
                    stroke.point_offset,
                    stroke.point_count,
                    request.local_point_count) ||
                !std::isfinite(stroke.thickness) ||
                !std::isfinite(stroke.feather)) {
                fail_local_dodge_burn_request(
                    result,
                    "invalid_local_dodge_burn_payload");
                return false;
            }
        }

        pipeline_request.local_dodge_burn.adjustments.reserve(
            request.local_adjustment_count);
        for (std::uint32_t index = 0U;
             index < request.local_adjustment_count;
             ++index) {
            const nf_local_dodge_burn_adjustment_v1& source =
                request.local_adjustments[index];
            const bool brush = source.mask_kind == NF_LOCAL_DODGE_BURN_MASK_BRUSH;
            const bool polygon = source.mask_kind == NF_LOCAL_DODGE_BURN_MASK_POLYGON;
            if (source.mode > NF_LOCAL_DODGE_BURN_MODE_BURN ||
                source.enabled > 1U ||
                source.mask_kind > NF_LOCAL_DODGE_BURN_MASK_POLYGON ||
                !std::isfinite(source.amount) ||
                !std::isfinite(source.center_x) ||
                !std::isfinite(source.center_y) ||
                !std::isfinite(source.radius) ||
                !std::isfinite(source.feather) ||
                !std::isfinite(source.start_x) ||
                !std::isfinite(source.start_y) ||
                !std::isfinite(source.end_x) ||
                !std::isfinite(source.end_y) ||
                !valid_flat_range(
                    source.stroke_offset,
                    source.stroke_count,
                    request.local_stroke_count) ||
                !valid_flat_range(
                    source.point_offset,
                    source.point_count,
                    request.local_point_count) ||
                (brush && (source.point_offset != 0U || source.point_count != 0U)) ||
                (polygon &&
                 (source.stroke_offset != 0U || source.stroke_count != 0U)) ||
                (!brush && !polygon &&
                 (source.stroke_offset != 0U || source.stroke_count != 0U ||
                  source.point_offset != 0U || source.point_count != 0U))) {
                fail_local_dodge_burn_request(
                    result,
                    "invalid_local_dodge_burn_payload");
                return false;
            }

            negaflow::imaging::LocalDodgeBurnAdjustment adjustment{};
            adjustment.mode = source.mode == NF_LOCAL_DODGE_BURN_MODE_DODGE
                ? negaflow::imaging::LocalDodgeBurnMode::dodge
                : negaflow::imaging::LocalDodgeBurnMode::burn;
            adjustment.enabled = source.enabled != 0U;
            adjustment.amount = source.amount;
            adjustment.mask.kind = static_cast<
                negaflow::imaging::LocalDodgeBurnMaskKind>(source.mask_kind);
            adjustment.mask.center = {source.center_x, source.center_y};
            adjustment.mask.radius = source.radius;
            adjustment.mask.feather = source.feather;
            adjustment.mask.start = {source.start_x, source.start_y};
            adjustment.mask.end = {source.end_x, source.end_y};

            if (brush) {
                adjustment.mask.strokes.reserve(source.stroke_count);
                for (std::uint32_t stroke_index = 0U;
                     stroke_index < source.stroke_count;
                     ++stroke_index) {
                    const nf_local_dodge_burn_stroke_v1& flat_stroke =
                        request.local_strokes[
                            source.stroke_offset + stroke_index];
                    negaflow::imaging::LocalDodgeBurnStroke stroke{};
                    stroke.thickness = flat_stroke.thickness;
                    stroke.feather = flat_stroke.feather;
                    stroke.points.reserve(flat_stroke.point_count);
                    for (std::uint32_t point_index = 0U;
                         point_index < flat_stroke.point_count;
                         ++point_index) {
                        const nf_local_dodge_burn_point_v1& point =
                            request.local_points[
                                flat_stroke.point_offset + point_index];
                        stroke.points.push_back({point.x, point.y});
                    }
                    adjustment.mask.strokes.push_back(std::move(stroke));
                }
            } else if (polygon) {
                adjustment.mask.points.reserve(source.point_count);
                for (std::uint32_t point_index = 0U;
                     point_index < source.point_count;
                     ++point_index) {
                    const nf_local_dodge_burn_point_v1& point =
                        request.local_points[source.point_offset + point_index];
                    adjustment.mask.points.push_back({point.x, point.y});
                }
            }
            pipeline_request.local_dodge_burn.adjustments.push_back(
                std::move(adjustment));
        }
    } catch (const std::bad_alloc&) {
        fail_local_dodge_burn_request(
            result,
            "local_dodge_burn_recipe_allocation_failed");
        return false;
    }

    if (!negaflow::imaging::valid_local_dodge_burn_parameters(
            pipeline_request.local_dodge_burn)) {
        fail_local_dodge_burn_request(
            result,
            "invalid_local_dodge_burn_parameters");
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v13(
    const nf_develop_export_request_v13& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v12(
            request.v12,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    pipeline_request.color_model = {
        request.warmth,
        request.tint,
        request.color_depth,
        request.vibrance,
        request.saturation,
        request.red_primary,
        request.green_primary,
        request.blue_primary,
    };
    return true;
}

[[nodiscard]] bool map_request_v14(
    const nf_develop_export_request_v14& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v13(
            request.v13,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    if (request.auto_levels > 1U || request.auto_neutral_balance > 1U) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_scene_correction_flag", result.failure_name);
        return false;
    }
    pipeline_request.scene_correction = {
        request.auto_levels == 1U,
        request.auto_neutral_balance == 1U,
        pipeline_request.film_look.source_kind ==
            negaflow::imaging::DevelopSourceKind::film_scan,
    };
    return true;
}

[[nodiscard]] bool map_request_v15(
    const nf_develop_export_request_v15& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v14(
            request.v14,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    if (request.reserved != 0U || request.develop_target > NF_DEVELOP_TARGET_RESCUE) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_develop_target", result.failure_name);
        return false;
    }
    pipeline_request.develop_target =
        static_cast<negaflow::pipeline::DevelopTarget>(request.develop_target);
    return true;
}

[[nodiscard]] bool map_request_v16(
    const nf_develop_export_request_v16& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v15(
            request.v15,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    if (request.scanner_profile_id != nullptr) {
        pipeline_request.scanner_profile_id = request.scanner_profile_id;
    }
    return true;
}

[[nodiscard]] bool map_request_v17(
    const nf_develop_export_request_v17& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v16(
            request.v16,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    if (request.reserved != 0U ||
        !map_film_polarity(request.film_polarity, pipeline_request.film_polarity)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_film_polarity", result.failure_name);
        return false;
    }
    return true;
}

}  // namespace negaflow::abi::detail
