#include "grade.h"

#include "export/support/outcome.h"

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/color_model.h"
#include "negaflow/imaging/rescue_grade.h"
#include "negaflow/imaging/scanner_profile_grade.h"
#include "negaflow/imaging/scanner_target_grade.h"
#include "negaflow/imaging/scene_correction.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace negaflow::pipeline::develop_export_detail {

std::optional<DevelopExportOutcome> apply_grade_stages(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    InvertStageOutput& invert) noexcept {
    negaflow::imaging::WorkingImage& developed_image = invert.image;
    const bool negative_source = invert.negative_source;
    const bool positive = invert.positive;
    const auto& negative = invert.negative;

    tracker.begin(
        DevelopExportStage::scene_correction, cost_of(scene_correction_cost, true));
    negaflow::imaging::SceneCorrectionParameters scene_correction =
        request.scene_correction;
    scene_correction.negative_source = negative_source;
    const bool scene_active =
        scene_correction.auto_levels ||
        (scene_correction.auto_neutral_balance && negative_source);
    if (scene_active) {
        GpuAccelerator::shared().flush_resident();
        negaflow::imaging::SceneCorrectionInfo scene_correction_info{};
        const negaflow::core::KernelStatus scene_correction_status =
            negaflow::imaging::apply_scene_correction(
                {
                    developed_image.pixels.data(),
                    developed_image.pixels.size(),
                    developed_image.width,
                    developed_image.height,
                    developed_image.stride_pixels,
                },
                scene_correction,
                scene_correction_info);
        if (scene_correction_status != negaflow::core::KernelStatus::ok) {
            return fail(
                DevelopExportStage::scene_correction,
                negaflow::core::kernel_status_name(scene_correction_status));
        }
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::scene_correction);
    }

    tracker.begin(
        DevelopExportStage::target_grade,
        cost_of(
            target_grade_cost,
            request.develop_target != DevelopTarget::main ||
                !request.scanner_profile_id.empty()));
    const bool target_active =
        request.develop_target == DevelopTarget::noritsu ||
        request.develop_target == DevelopTarget::sp3000 ||
        request.develop_target == DevelopTarget::f135 ||
        request.develop_target == DevelopTarget::hr ||
        request.develop_target == DevelopTarget::rescue ||
        ((request.develop_target == DevelopTarget::main ||
          request.develop_target == DevelopTarget::print) &&
         !request.scanner_profile_id.empty());
    if (target_active) {
        GpuAccelerator::shared().flush_resident();
    }
    if (request.develop_target == DevelopTarget::noritsu ||
        request.develop_target == DevelopTarget::sp3000 ||
        request.develop_target == DevelopTarget::f135 ||
        request.develop_target == DevelopTarget::hr) {
        negaflow::imaging::ScannerTargetStyle target_style =
            negaflow::imaging::ScannerTargetStyle::noritsu;
        switch (request.develop_target) {
            case DevelopTarget::sp3000:
                target_style = negaflow::imaging::ScannerTargetStyle::sp3000;
                break;
            case DevelopTarget::f135:
                target_style = negaflow::imaging::ScannerTargetStyle::f135;
                break;
            case DevelopTarget::hr:
                target_style = negaflow::imaging::ScannerTargetStyle::hr;
                break;
            default:
                break;
        }
        negaflow::imaging::ScannerTargetGradeInfo target_info{};
        const negaflow::core::KernelStatus target_status =
            negaflow::imaging::apply_scanner_target_grade(
                {
                    developed_image.pixels.data(),
                    developed_image.pixels.size(),
                    developed_image.width,
                    developed_image.height,
                    developed_image.stride_pixels,
                },
                target_style,
                negative.film_type == negaflow::imaging::NegativeFilmType::black_and_white,
                positive,
                request.scanner_profile_id,
                target_info);
        if (target_status != negaflow::core::KernelStatus::ok) {
            return fail(
                DevelopExportStage::target_grade,
                negaflow::core::kernel_status_name(target_status));
        }
    }
    if (request.develop_target == DevelopTarget::rescue) {
        negaflow::imaging::RescueGradeInfo rescue_info{};
        const negaflow::core::KernelStatus rescue_status =
            negaflow::imaging::apply_rescue_grade(
                {
                    developed_image.pixels.data(),
                    developed_image.pixels.size(),
                    developed_image.width,
                    developed_image.height,
                    developed_image.stride_pixels,
                },
                negative.film_type == negaflow::imaging::NegativeFilmType::color,
                rescue_info);
        if (rescue_status != negaflow::core::KernelStatus::ok) {
            return fail(
                DevelopExportStage::target_grade,
                negaflow::core::kernel_status_name(rescue_status));
        }
    }
    if ((request.develop_target == DevelopTarget::main ||
         request.develop_target == DevelopTarget::print) &&
        !request.scanner_profile_id.empty()) {
        negaflow::imaging::ScannerProfileGradeInfo profile_info{};
        const negaflow::core::KernelStatus profile_status =
            negaflow::imaging::apply_scanner_profile_grade(
                {
                    developed_image.pixels.data(),
                    developed_image.pixels.size(),
                    developed_image.width,
                    developed_image.height,
                    developed_image.stride_pixels,
                },
                request.scanner_profile_id,
                profile_info);
        if (profile_status != negaflow::core::KernelStatus::ok) {
            return fail(
                DevelopExportStage::target_grade,
                negaflow::core::kernel_status_name(profile_status));
        }
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::target_grade);
    }

    tracker.begin(DevelopExportStage::color_model, cost_of(color_model_cost, true));
    if (negaflow::imaging::has_color_model_change(request.color_model)) {
        const negaflow::core::KernelStatus color_model_status =
            negaflow::imaging::apply_color_model(
                {
                    developed_image.pixels.data(),
                    developed_image.pixels.size(),
                    developed_image.width,
                    developed_image.height,
                    developed_image.stride_pixels,
                },
                {
                    developed_image.pixels.data(),
                    developed_image.pixels.size(),
                    developed_image.width,
                    developed_image.height,
                    developed_image.stride_pixels,
                },
                request.color_model);
        if (color_model_status != negaflow::core::KernelStatus::ok) {
            return fail(
                DevelopExportStage::color_model,
                negaflow::core::kernel_status_name(color_model_status));
        }
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::color_model);
    }
    return std::nullopt;
}

}  // namespace negaflow::pipeline::develop_export_detail
