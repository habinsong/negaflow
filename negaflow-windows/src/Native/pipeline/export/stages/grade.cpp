#include "grade.h"

#include "export/support/outcome.h"

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/color_model.h"
#include "negaflow/imaging/rescue_grade.h"
#include "negaflow/imaging/scanner_profile_grade.h"
#include "negaflow/imaging/scene_correction.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace negaflow::pipeline::develop_export_detail {

std::optional<DevelopExportOutcome> apply_grade_stages(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    const GpuUsePolicy gpu_policy,
    InvertStageOutput& invert,
    const bool stop_before_color_model) noexcept {
    negaflow::imaging::WorkingImage& developed_image = invert.image;
    const bool negative_source = invert.negative_source;
    const auto& negative = invert.negative;

    tracker.begin(
        DevelopExportStage::scene_correction, cost_of(scene_correction_cost, true));
    negaflow::imaging::SceneCorrectionParameters scene_correction =
        request.scene_correction;
    scene_correction.negative_source = negative_source;
    scene_correction.analysis_region = invert.analysis_region;
    scene_correction.linear_negative_output = negative.linear_output;
    scene_correction.monochrome = negative.film_type == imaging::NegativeFilmType::black_and_white;
    const bool scene_active =
        scene_correction.auto_levels ||
        (scene_correction.auto_neutral_balance && negative_source);
    if (scene_active) {
        // **GPU 를 먼저 시도합니다.** 예전에는 여기서 무조건 `flush_resident()` 를 불러
        // 화소를 호스트로 내렸고, 그 한 번 때문에 뒤따르는 톤·필름룩·마무리·발행이
        // 전부 CPU 경로였습니다. 실측(1536x1026 슬라이더 8틱): 다운로드 1,374 MB,
        // 이 단계만 틱당 150ms.
        // 가속기는 실패할 때 화소를 손대지 않으므로, 못 하면 그대로 CPU 판으로 갑니다.
        negaflow::imaging::SceneCorrectionInfo scene_correction_info{};
        if (!GpuAccelerator::shared().apply_scene_correction(
                gpu_policy, developed_image, scene_correction, scene_correction_info)) {
            GpuAccelerator::shared().flush_resident();
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
    // 스캐너 타깃(SP·HS·F135·HR)은 여기가 아니라 톤 단계 안, 노출·기본 톤·파라메트릭 커브 뒤에
    // 겁니다(`look.cpp`, macOS `ScannerTargetGrade.applyAfterSceneAdjustments`). 레스큐·프로필
    // 그레이드는 CPU 판뿐이라 그때만 화상을 내립니다.
    const bool target_active =
        request.develop_target == DevelopTarget::rescue ||
        ((request.develop_target == DevelopTarget::main ||
          request.develop_target == DevelopTarget::print) &&
         !request.scanner_profile_id.empty());
    if (target_active) {
        GpuAccelerator::shared().flush_resident();
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
                rescue_info,
                invert.analysis_region);
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
    if (stop_before_color_model) {
        return std::nullopt;
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

} // namespace negaflow::pipeline::develop_export_detail
