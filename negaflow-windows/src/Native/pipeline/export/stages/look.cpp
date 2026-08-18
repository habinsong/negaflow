#include "look.h"

#include "export/support/outcome.h"

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "negaflow/pipeline/gpu_accelerator.h"

#include <utility>

namespace negaflow::pipeline::develop_export_detail {

std::optional<DevelopExportOutcome> prepare_look_workspace(
    const DevelopExportRequest& request,
    const std::uint32_t decoded_width,
    LookWorkspaceOutput& out) noexcept {
    out.parameters = request.film_look;
    out.parameters.monochrome =
        request.negative.film_type ==
        negaflow::imaging::NegativeFilmType::black_and_white;

    const FilmLookWorkspacePrepareStatus workspace_status =
        prepare_film_look_workspace(out.parameters, decoded_width, out.workspace);
    if (workspace_status != FilmLookWorkspacePrepareStatus::ok) {
        return fail(
            DevelopExportStage::film_look_workspace,
            film_look_workspace_prepare_status_name(workspace_status));
    }
    out.workspace_bytes = film_look_workspace_bytes(out.workspace);
    return std::nullopt;
}

std::optional<DevelopExportOutcome> apply_look_stages(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    LookWorkspaceOutput& workspace,
    negaflow::imaging::WorkingImage developed_image,
    const GpuUsePolicy gpu_policy,
    LookStageOutput& out) noexcept {
    tracker.begin(DevelopExportStage::tone_adjust, cost_of(tone_cost, true));

    // ☠️ **GPU 를 먼저 시도하고, 처리하지 못했으면 CPU 로 갑니다.**
    //    가속기는 실패할 때 이미지를 손대지 않으므로(`gpu_accelerator.h`) 그대로 이어서
    //    CPU 판을 부르면 됩니다. 두 경로의 화소는 동치 시험이 `1e-5` 로 묶습니다.
    negaflow::imaging::WorkingToneAdjustResult adjusted{};
    const GpuToneOutcome accelerated =
        GpuAccelerator::shared().apply_working_tone_adjustments(
            gpu_policy, developed_image, request.tone, {});
    if (accelerated.handled) {
        adjusted.status = negaflow::imaging::WorkingToneAdjustStatus::ok;
        adjusted.info = accelerated.info;
        adjusted.image = std::move(developed_image);
    } else {
        adjusted = negaflow::imaging::apply_working_tone_adjustments(
            std::move(developed_image),
            request.tone);
    }
    if (adjusted.status != negaflow::imaging::WorkingToneAdjustStatus::ok) {
        if (adjusted.status ==
            negaflow::imaging::WorkingToneAdjustStatus::kernel_failed) {
            return fail(
                DevelopExportStage::tone_adjust,
                negaflow::core::kernel_status_name(adjusted.info.kernel_status));
        }
        if (adjusted.status ==
            negaflow::imaging::WorkingToneAdjustStatus::measurement_failed) {
            return fail(
                DevelopExportStage::tone_adjust,
                negaflow::imaging::tone_curve_measurement_status_name(
                    adjusted.info.measurement.status));
        }
        return fail(
            DevelopExportStage::tone_adjust,
            negaflow::imaging::working_tone_adjust_status_name(adjusted.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::tone_adjust);
    }

    tracker.begin(
        DevelopExportStage::film_look,
        cost_of(
            film_look_cost,
            request.film_look.source_kind !=
                negaflow::imaging::DevelopSourceKind::film_scan));
    auto film_look = negaflow::imaging::apply_working_film_look(
        std::move(adjusted.image),
        workspace.parameters,
        film_look_workspace_view(workspace.workspace));
    if (film_look.status != negaflow::imaging::WorkingFilmLookStatus::ok) {
        if (film_look.status ==
            negaflow::imaging::WorkingFilmLookStatus::kernel_failed) {
            return fail(
                DevelopExportStage::film_look,
                negaflow::core::kernel_status_name(film_look.info.kernel_status));
        }
        return fail(
            DevelopExportStage::film_look,
            negaflow::imaging::working_film_look_status_name(film_look.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::film_look);
    }

    out.image = std::move(film_look.image);
    out.workspace_bytes = workspace.workspace_bytes;
    out.info = film_look.info;
    return std::nullopt;
}

}  // namespace negaflow::pipeline::develop_export_detail
