#include "publish.h"

#include "export/support/outcome.h"
#include "export/support/preview.h"
#include "export/support/stage_trace.h"

#include "negaflow/pipeline/gpu_accelerator.h"

#include "negaflow/output/wic_jpeg_export.h"
#include "negaflow/output/wic_png_export.h"
#include "negaflow/output/wic_tiff_export.h"

namespace negaflow::pipeline::develop_export_detail {

DevelopExportOutcome publish_developed(
    const DevelopExportRequest& request,
    const PreviewTarget* const preview,
    RunTracker& tracker,
    const ObservedSource& observed,
    const DefectRecipeStageResult& defect_recipe,
    const InvertStageOutput& invert,
    const LookStageOutput& look,
    const GrainStageOutput& grain,
    const FinishStageOutput& finish) noexcept {
    const auto& output_sharpening = finish.sharpening;
    const auto& film_look_info = look.info;
    const auto& grain_mend_info = grain.applied.info;

    // The last poll before anything is published. From here the run either produces the
    // whole artifact or fails, so a cancel arriving now is not honoured rather than
    // leaving a half-written file behind.
    tracker.begin(
        DevelopExportStage::output,
        cost_of(preview != nullptr ? preview_output_cost : export_output_cost, true));
    DevelopExportOutcome outcome{};
    outcome.image_width = output_sharpening.image.width;
    outcome.image_height = output_sharpening.image.height;
    outcome.source_file_bytes = observed.before.observation.file_bytes;
    outcome.film_look_workspace_bytes = look.workspace_bytes;
    outcome.film_look_route = film_look_info.route;
    outcome.film_look_color_applied = film_look_info.color_applied;
    outcome.film_look_acutance_applied = film_look_info.acutance_applied;
    outcome.defect_region_applied = defect_recipe.info.region_applied;
    outcome.defect_region_edits_applied =
        defect_recipe.info.region_applied_edit_count;
    outcome.defect_region_repaired_pixels =
        defect_recipe.info.region_repaired_pixels;
    outcome.defect_clone_applied = defect_recipe.info.clone_applied;
    outcome.defect_clone_edits_applied =
        defect_recipe.info.clone_applied_edit_count;
    outcome.defect_clone_patched_pixels =
        defect_recipe.info.clone_patched_pixels;
    outcome.defect_clone_peak_patch_bytes =
        defect_recipe.info.clone_peak_patch_bytes;
    outcome.grain_mend_applied = grain_mend_info.applied;
    outcome.grain_mend_candidate_pixels = grain_mend_info.candidate_pixels;
    outcome.grain_mend_repaired_pixels = grain_mend_info.repaired_pixels;
    outcome.film_scan_denoise_applied = finish.denoise.applied;
    outcome.film_scan_denoise_tiles =
        finish.denoise.tiles_processed;
    outcome.local_dodge_burn_adjustments_applied =
        finish.dodge.adjustments_applied;
    outcome.texture_applied = finish.texture.applied;
    outcome.black_and_white_neutralized =
        finish.bw.neutralized;
    outcome.bw_toning_applied = finish.bw.toned;
    outcome.image_transform_applied = finish.transform.applied || finish.output_resized;
    outcome.output_sharpening_applied = output_sharpening.info.applied;
    outcome.applied_dmin = invert.developed_info.applied_dmin;
    outcome.dmax_normalized = invert.developed_info.dmax_normalized;
    outcome.black_input = invert.developed_info.black_input;
    outcome.debug_metrics_present =
        invert.developed_info.kernel_status == negaflow::core::KernelStatus::ok;
    outcome.base_source = invert.base_source;
    outcome.measurement_method = invert.measurement_method;
    outcome.measurement_diagnostics = invert.diagnostics;

    if (preview != nullptr) {
        // 기하 변환을 미뤘으면 보고하는 치수도 **변환 뒤** 치수입니다.
        if (finish.transform_deferred) {
            outcome.image_width = finish.deferred_transform.output_width;
            outcome.image_height = finish.deferred_transform.output_height;
        }
        DevelopExportOutcome preview_outcome = write_preview(
            output_sharpening.image,
            *preview,
            outcome,
            finish.transform_deferred ? &finish.deferred_transform : nullptr);
        if (preview_outcome.succeeded) {
            tracker.finish();
            tracker.complete();
        }
        return preview_outcome;
    }

    // **인코더는 호스트 버퍼를 읽습니다.** 여기까지 오는 화소는 GPU 에 머물러 있을 수
    // 있고, 그러면 `image.pixels` 는 상주로 묶이기 **전** 내용 — 곧 반전 전 네거티브 —
    // 그대로입니다. 미리보기 갈래는 `write_preview` 가 스스로 내리므로 무사했지만,
    // 내보내기 갈래에는 내리는 자리가 없었습니다.
    //
    // 그래서 현상 타깃에 따라 되고 안 되고가 갈렸습니다: `grade.cpp` 가 `target_active`
    // 일 때만 `flush_resident()` 를 부르므로 노리츠·SP3000·F135·HR·복원은 우연히
    // 살아났고, 스캐너 프로파일 없는 MAIN·PRINT 는 **원본 네거티브를 그대로 내보냈습니다.**
    // 실측(GT-X900_frame_15, MAIN): 내보낸 파일 평균 (74,49,40)/원본과 상관 +0.97 →
    // 내린 뒤 (189,196,197)/상관 -0.99, 미리보기 (189,195,196) 와 일치.
    //
    // 버퍼를 **소비하는 자리**에서만 내린다는 `outcome.h` 규칙 그대로, 이 이미지 하나만
    // 내리고 묶음을 풉니다.
    GpuAccelerator::shared().flush_resident_if(output_sharpening.image.pixels.data());

    stage_trace_image("publish.encode_in", output_sharpening.image);

    if (request.format == DevelopExportFormat::png16) {
        negaflow::output::WicPngExportLimits output_limits{};
        output_limits.output_dpi = request.output_dpi;
        output_limits.bits_per_sample = request.output_bit_depth;
        output_limits.color_space = request.output_color_space;
        output_limits.conversion.preserve_alpha = request.preserve_alpha;
        output_limits.conversion.output_icc_profile = request.output_icc_profile;
        // PNG 는 EXIF 를 담지 않는다. 정책은 파일에 아무 흔적도 남기지 않는다.
        const negaflow::output::WicPngExportResult exported =
            negaflow::output::export_working_to_srgb16_png(
                output_sharpening.image,
                request.destination,
                output_limits);
        if (exported.status != negaflow::output::WicPngExportStatus::ok) {
            if (exported.status ==
                negaflow::output::WicPngExportStatus::working_conversion_failed) {
                return fail(
                    DevelopExportStage::output,
                    negaflow::output::working_to_srgb16_status_name(
                        exported.conversion_status),
                    exported.native_error_code,
                    exported.cleanup_error_code);
            }
            return fail(
                DevelopExportStage::output,
                negaflow::output::wic_png_export_status_name(exported.status),
                exported.native_error_code,
                exported.cleanup_error_code);
        }
        outcome.output_file_bytes = exported.info.artifact_bytes;
        outcome.succeeded = true;
        outcome.failure_name = "ok";
        tracker.finish();
        tracker.complete();
        return outcome;
    }

    if (request.format == DevelopExportFormat::jpeg8) {
        negaflow::output::WicJpegExportLimits jpeg_limits{};
        jpeg_limits.metadata_policy = request.metadata_policy;
        jpeg_limits.metadata = request.metadata;
        jpeg_limits.conversion.output_icc_profile = request.output_icc_profile;
        const negaflow::output::WicJpegExportResult exported =
            negaflow::output::export_working_to_srgb8_jpeg(
                output_sharpening.image,
                request.destination,
                request.jpeg_quality,
                request.output_dpi,
                jpeg_limits);
        if (exported.status != negaflow::output::WicJpegExportStatus::ok) {
            if (exported.status ==
                negaflow::output::WicJpegExportStatus::working_conversion_failed) {
                return fail(
                    DevelopExportStage::output,
                    negaflow::output::working_to_srgb16_status_name(
                        exported.conversion_status),
                    exported.native_error_code,
                    exported.cleanup_error_code);
            }
            return fail(
                DevelopExportStage::output,
                negaflow::output::wic_jpeg_export_status_name(exported.status),
                exported.native_error_code,
                exported.cleanup_error_code);
        }
        outcome.output_file_bytes = exported.info.artifact_bytes;
        outcome.succeeded = true;
        outcome.failure_name = "ok";
        tracker.finish();
        tracker.complete();
        return outcome;
    }

    negaflow::output::WicTiffExportLimits output_limits{};
    output_limits.compression = request.tiff_compression;
    output_limits.output_dpi = request.output_dpi;
    output_limits.bits_per_sample = request.output_bit_depth;
    output_limits.color_space = request.output_color_space;
    output_limits.conversion.preserve_alpha = request.preserve_alpha;
    output_limits.conversion.output_icc_profile = request.output_icc_profile;
    output_limits.metadata_policy = request.metadata_policy;
    output_limits.metadata = request.metadata;
    const negaflow::output::WicTiffExportResult exported =
        negaflow::output::export_working_to_srgb16_tiff(
        output_sharpening.image,
            request.destination,
            output_limits);
    if (exported.status != negaflow::output::WicTiffExportStatus::ok) {
        if (exported.status ==
            negaflow::output::WicTiffExportStatus::working_conversion_failed) {
            return fail(
                DevelopExportStage::output,
                negaflow::output::working_to_srgb16_status_name(
                    exported.conversion_status),
                exported.native_error_code,
                exported.cleanup_error_code);
        }
        return fail(
            DevelopExportStage::output,
            negaflow::output::wic_tiff_export_status_name(exported.status),
            exported.native_error_code,
            exported.cleanup_error_code);
    }
    outcome.output_file_bytes = exported.info.artifact_bytes;
    outcome.succeeded = true;
    outcome.failure_name = "ok";
    tracker.finish();
    tracker.complete();
    return outcome;
}

}  // namespace negaflow::pipeline::develop_export_detail
