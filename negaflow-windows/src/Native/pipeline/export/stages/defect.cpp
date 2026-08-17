#include "defect.h"

#include "export/support/outcome.h"

#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <utility>

namespace negaflow::pipeline::develop_export_detail {
namespace {

// 다른 단계의 NEGA_DEBUG 줄과 같은 방식으로 켜집니다.
[[nodiscard]] bool debug_enabled() noexcept {
    std::size_t length = 0U;
    return getenv_s(&length, nullptr, 0U, "NEGA_DEBUG") == 0 && length > 0U;
}

}  // namespace

std::optional<DevelopExportOutcome> apply_defect_stage(
    const DevelopExportRequest& request,
    const PreviewTarget* const preview,
    const DetectTarget* const detect,
    RunTracker& tracker,
    negaflow::imaging::WorkingImage& decoded_image,
    DefectRecipeStageResult& defect_recipe) noexcept {
    tracker.begin(
        DevelopExportStage::defect_component_repair,
        cost_of(defect_cost, !request.defect_recipe.order.empty()));
    defect_recipe = apply_defect_recipe(
        std::move(decoded_image),
        request.defect_recipe);
    if (defect_recipe.status != DefectRecipeStageStatus::ok) {
        const DevelopExportStage stage = [&]() {
            if (defect_recipe.status == DefectRecipeStageStatus::clone_failed) {
                return DevelopExportStage::defect_clone_stamp;
            }
            if (defect_recipe.status == DefectRecipeStageStatus::brush_failed) {
                return DevelopExportStage::defect_brush;
            }
            return DevelopExportStage::defect_component_repair;
        }();
        return fail(
            stage,
            defect_recipe_stage_status_name(defect_recipe));
    }
    decoded_image = std::move(defect_recipe.image);
    // 결함 수리가 실제로 일어났는지 물어볼 방법이 여태 없었습니다 — 파이프라인은 세어 두지만
    // ABI 로 내보내지 않아, preview 와 export 중 어느 쪽이 recipe 를 흘리는지 코드 밖에서
    // 가릴 수 없었습니다. NEGA_DEBUG 로만 켜지므로 평시 비용은 없습니다.
    if (debug_enabled()) {
        std::size_t length = 0U;
        std::fprintf(
            stderr,
            "[nega-defect] target=%s order=%zu region_applied=%d region_edits=%zu "
            "region_repaired_px=%zu\n",
            preview != nullptr ? "preview" : (detect != nullptr ? "detect" : "export"),
            request.defect_recipe.order.size(),
            defect_recipe.info.region_applied ? 1 : 0,
            static_cast<std::size_t>(defect_recipe.info.region_applied_edit_count),
            static_cast<std::size_t>(defect_recipe.info.region_repaired_pixels));
        (void)length;
        std::fflush(stderr);
    }
    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::defect_component_repair);
    }
    return std::nullopt;
}

}  // namespace negaflow::pipeline::develop_export_detail
