#pragma once

#include "negaflow/imaging/defect_clone_stamp.h"
#include "negaflow/imaging/defect_heal_brush.h"
#include "negaflow/pipeline/defect_region_stage.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::pipeline {

enum class DefectRecipeEditKind : std::uint8_t {
    region = 0,
    clone,
    brush,
};

struct DefectRecipeEditRef final {
    DefectRecipeEditKind kind{DefectRecipeEditKind::region};
    std::size_t index{0U};
};

struct DefectCloneEdit final {
    bool enabled{true};
    negaflow::imaging::DefectCloneParameters parameters{};
};

struct DefectBrushEdit final {
    bool enabled{true};
    negaflow::imaging::DefectHealBrushParameters parameters{};
};

struct DefectRecipeParameters final {
    DefectRegionParameters regions{};
    // ABI-owned flat storage. Spans in clone_strokes_storage and clones are
    // bound only after these vectors have reached their final size.
    std::vector<negaflow::imaging::DefectClonePoint> clone_points_storage{};
    std::vector<negaflow::imaging::DefectCloneStroke> clone_strokes_storage{};
    std::vector<DefectCloneEdit> clones{};
    std::vector<negaflow::imaging::DefectBrushPoint> brush_points_storage{};
    std::vector<negaflow::imaging::DefectBrushStroke> brush_strokes_storage{};
    std::vector<DefectBrushEdit> brushes{};
    // Covers every region/clone/brush descriptor exactly once. This preserves
    // the sidecar layer order when unlike edit kinds are interleaved.
    std::vector<DefectRecipeEditRef> order{};
};

enum class DefectRecipeStageStatus : std::uint8_t {
    ok = 0,
    invalid_argument,
    region_failed,
    clone_failed,
    brush_failed,
    allocation_failed,
};

struct DefectRecipeStageInfo final {
    bool region_applied{false};
    std::size_t region_applied_edit_count{0U};
    std::size_t region_repaired_pixels{0U};
    bool clone_applied{false};
    std::size_t clone_applied_edit_count{0U};
    std::size_t clone_patched_pixels{0U};
    std::size_t clone_peak_patch_bytes{0U};
    bool brush_applied{false};
    std::size_t brush_applied_edit_count{0U};
    std::size_t brush_healed_pixels{0U};
    std::size_t brush_peak_patch_bytes{0U};
    DefectRegionStageStatus region_status{DefectRegionStageStatus::ok};
    negaflow::imaging::DefectCloneStatus clone_status{
        negaflow::imaging::DefectCloneStatus::ok};
    negaflow::imaging::DefectHealBrushStatus brush_status{
        negaflow::imaging::DefectHealBrushStatus::ok};
};

struct DefectRecipeStageResult final {
    DefectRecipeStageStatus status{DefectRecipeStageStatus::invalid_argument};
    DefectRecipeStageInfo info{};
    negaflow::imaging::WorkingImage image{};
};

[[nodiscard]] DefectRecipeStageResult apply_defect_recipe(
    negaflow::imaging::WorkingImage image,
    const DefectRecipeParameters& parameters) noexcept;

[[nodiscard]] const char* defect_recipe_stage_status_name(
    const DefectRecipeStageResult& result) noexcept;

}  // namespace negaflow::pipeline
