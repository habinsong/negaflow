#include "negaflow/pipeline/develop_export.h"

#include "export/stages/decode.h"
#include "export/stages/defect.h"
#include "export/stages/observe.h"
#include "export/stages/validate.h"
#include "export/support/outcome.h"
#include "export/support/progress.h"

#include "negaflow/output/wic_tiff_export.h"

#include <new>
#include <stop_token>

namespace negaflow::pipeline {
namespace {

using namespace develop_export_detail;

[[nodiscard]] DevelopExportOutcome run_defect_bake(
    const DevelopExportRequest& request,
    const DevelopRunControl& control) {
    if (auto failed = validate_request(request, nullptr, nullptr)) {
        return *failed;
    }
    if (request.format != DevelopExportFormat::tiff16 ||
        request.defect_recipe.order.empty()) {
        return fail(DevelopExportStage::request_validation, "invalid_defect_bake_request");
    }
    if (!request.defect_recipe.infrared.empty()) {
        return fail(DevelopExportStage::request_validation, "infrared_not_bakeable");
    }
    for (const DefectRecipeEditRef& edit : request.defect_recipe.order) {
        if (edit.kind == DefectRecipeEditKind::infrared) {
            return fail(DevelopExportStage::request_validation, "infrared_not_bakeable");
        }
    }

    constexpr std::uint32_t total_cost =
        decode_cost.active + defect_cost.active + export_output_cost.active;
    RunTracker tracker{control, total_cost};
    std::stop_source stop{};
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::request_validation);
    }

    ObservedSource observed{};
    if (auto failed = observe_source_before(request, tracker, stop, observed)) {
        return *failed;
    }

    negaflow::imaging::WorkingImage image{};
    if (auto failed = decode_source(request, tracker, stop, observed, image)) {
        return *failed;
    }

    DefectRecipeStageResult recipe{};
    if (auto failed = apply_defect_stage(
            request, control, nullptr, nullptr, tracker, image, recipe)) {
        return *failed;
    }

    tracker.begin(DevelopExportStage::output, export_output_cost.active);
    negaflow::output::WicTiffExportLimits limits{};
    const negaflow::output::WicTiffExportResult exported =
        negaflow::output::export_working_to_linear16_tiff(
            image,
            request.destination,
            limits);
    if (exported.status != negaflow::output::WicTiffExportStatus::ok) {
        const char* failure = exported.status ==
                negaflow::output::WicTiffExportStatus::working_conversion_failed
            ? negaflow::output::working_to_srgb16_status_name(exported.conversion_status)
            : negaflow::output::wic_tiff_export_status_name(exported.status);
        return fail(
            DevelopExportStage::output,
            failure,
            exported.native_error_code,
            exported.cleanup_error_code);
    }

    DevelopExportOutcome outcome{};
    outcome.succeeded = true;
    outcome.failure_name = "ok";
    outcome.image_width = image.width;
    outcome.image_height = image.height;
    outcome.source_file_bytes = observed.before.observation.file_bytes;
    outcome.defect_region_applied = recipe.info.region_applied;
    outcome.defect_region_edits_applied = recipe.info.region_applied_edit_count;
    outcome.defect_region_repaired_pixels = recipe.info.region_repaired_pixels;
    outcome.defect_clone_applied = recipe.info.clone_applied;
    outcome.defect_clone_edits_applied = recipe.info.clone_applied_edit_count;
    outcome.defect_clone_patched_pixels = recipe.info.clone_patched_pixels;
    outcome.defect_clone_peak_patch_bytes = recipe.info.clone_peak_patch_bytes;
    outcome.output_file_bytes = exported.info.artifact_bytes;
    tracker.finish();
    tracker.complete();
    return outcome;
}

}  // namespace

DevelopExportOutcome bake_defect_recipe(
    const DevelopExportRequest& request,
    const DevelopRunControl& control) noexcept {
    try {
        return run_defect_bake(request, control);
    } catch (const std::bad_alloc&) {
        return develop_export_detail::fail(DevelopExportStage::none, "out_of_memory");
    } catch (...) {
        return develop_export_detail::fail(DevelopExportStage::none, "unhandled_exception");
    }
}

}  // namespace negaflow::pipeline
