#include "negaflow/pipeline/defect_recipe_stage.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::pipeline {
namespace {

using negaflow::imaging::WorkingImage;

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] bool valid_order(
    const DefectRecipeParameters& parameters) {
    if (parameters.order.size() !=
        parameters.regions.edits.size() + parameters.clones.size() +
            parameters.brushes.size() + parameters.infrared.size()) {
        return false;
    }
    std::vector<std::uint8_t> regions(
        parameters.regions.edits.size(), 0U);
    std::vector<std::uint8_t> clones(parameters.clones.size(), 0U);
    std::vector<std::uint8_t> brushes(parameters.brushes.size(), 0U);
    std::vector<std::uint8_t> infrared(parameters.infrared.size(), 0U);
    for (const DefectRecipeEditRef reference : parameters.order) {
        switch (reference.kind) {
            case DefectRecipeEditKind::region:
                if (reference.index >= regions.size() ||
                    regions[reference.index] != 0U) {
                    return false;
                }
                regions[reference.index] = 1U;
                break;
            case DefectRecipeEditKind::clone:
                if (reference.index >= clones.size() ||
                    clones[reference.index] != 0U) {
                    return false;
                }
                clones[reference.index] = 1U;
                break;
            case DefectRecipeEditKind::brush:
                if (reference.index >= brushes.size() ||
                    brushes[reference.index] != 0U) {
                    return false;
                }
                brushes[reference.index] = 1U;
                break;
            case DefectRecipeEditKind::infrared:
                if (reference.index >= infrared.size() ||
                    infrared[reference.index] != 0U) {
                    return false;
                }
                infrared[reference.index] = 1U;
                break;
            default:
                return false;
        }
    }
    return true;
}

}  // namespace

DefectRecipeStageResult apply_defect_recipe(
    WorkingImage image,
    const DefectRecipeParameters& parameters) noexcept {
    DefectRecipeStageResult result{};
    result.image = std::move(image);
    try {
        if (!valid_order(parameters)) {
            discard_pixels(result.image);
            return result;
        }
        for (const DefectRecipeEditRef reference : parameters.order) {
            if (reference.kind == DefectRecipeEditKind::region) {
                DefectRegionParameters one{};
                one.edits.push_back(parameters.regions.edits[reference.index]);
                auto applied = apply_defect_region_edits(
                    std::move(result.image), one);
                result.info.region_status = applied.status;
                if (applied.status != DefectRegionStageStatus::ok) {
                    result.status = DefectRecipeStageStatus::region_failed;
                    discard_pixels(applied.image);
                    return result;
                }
                result.image = std::move(applied.image);
                if (applied.info.applied) {
                    result.info.region_applied = true;
                    result.info.region_applied_edit_count +=
                        applied.info.applied_edit_count;
                    result.info.region_repaired_pixels +=
                        applied.info.repaired_pixels;
                }
                continue;
            }

            if (reference.kind == DefectRecipeEditKind::clone) {
                const DefectCloneEdit& edit =
                    parameters.clones[reference.index];
                if (!edit.enabled || edit.parameters.strength <= 1.0e-3) {
                    continue;
                }
                auto applied = negaflow::imaging::apply_defect_clone_stamps(
                    std::move(result.image), edit.parameters);
                result.info.clone_status = applied.status;
                if (applied.status != negaflow::imaging::DefectCloneStatus::ok) {
                    result.status = DefectRecipeStageStatus::clone_failed;
                    discard_pixels(applied.image);
                    return result;
                }
                result.image = std::move(applied.image);
                if (applied.info.applied) {
                    result.info.clone_applied = true;
                    ++result.info.clone_applied_edit_count;
                    result.info.clone_patched_pixels +=
                        applied.info.patched_pixels;
                    result.info.clone_peak_patch_bytes = std::max(
                        result.info.clone_peak_patch_bytes,
                        applied.info.peak_patch_bytes);
                }
                continue;
            }

            if (reference.kind == DefectRecipeEditKind::infrared) {
                const DefectInfraredItem& item =
                    parameters.infrared[reference.index];
                auto applied = apply_defect_infrared_item(
                    std::move(result.image), item);
                result.info.infrared_status = applied.status;
                if (applied.status != DefectInfraredStageStatus::ok) {
                    result.status = DefectRecipeStageStatus::infrared_failed;
                    discard_pixels(applied.image);
                    return result;
                }
                result.image = std::move(applied.image);
                continue;
            }

            const DefectBrushEdit& edit =
                parameters.brushes[reference.index];
            if (!edit.enabled || edit.parameters.strength <= 1.0e-3) {
                continue;
            }
            auto applied = negaflow::imaging::apply_defect_heal_brush(
                std::move(result.image), edit.parameters);
            result.info.brush_status = applied.status;
            if (applied.status !=
                negaflow::imaging::DefectHealBrushStatus::ok) {
                result.status = DefectRecipeStageStatus::brush_failed;
                discard_pixels(applied.image);
                return result;
            }
            result.image = std::move(applied.image);
            if (applied.info.applied) {
                result.info.brush_applied = true;
                ++result.info.brush_applied_edit_count;
                result.info.brush_healed_pixels +=
                    applied.info.healed_pixels;
                result.info.brush_peak_patch_bytes = std::max(
                    result.info.brush_peak_patch_bytes,
                    applied.info.peak_patch_bytes);
            }
        }
        result.status = DefectRecipeStageStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = DefectRecipeStageStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = DefectRecipeStageStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* defect_recipe_stage_status_name(
    const DefectRecipeStageResult& result) noexcept {
    switch (result.status) {
        case DefectRecipeStageStatus::ok:
            return "ok";
        case DefectRecipeStageStatus::invalid_argument:
            return "invalid_argument";
        case DefectRecipeStageStatus::region_failed:
            return defect_region_stage_status_name(result.info.region_status);
        case DefectRecipeStageStatus::clone_failed:
            return negaflow::imaging::defect_clone_status_name(
                result.info.clone_status);
        case DefectRecipeStageStatus::brush_failed:
            return negaflow::imaging::defect_heal_brush_status_name(
                result.info.brush_status);
        case DefectRecipeStageStatus::infrared_failed: {
            DefectInfraredStageResult infrared{};
            infrared.status = result.info.infrared_status;
            return defect_infrared_stage_status_name(infrared);
        }
        case DefectRecipeStageStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::pipeline
