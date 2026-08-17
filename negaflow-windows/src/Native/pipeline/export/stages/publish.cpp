#include "publish.h"

#include "export/support/outcome.h"
#include "export/support/preview.h"

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
    outcome.base_source = invert.base_source;

    if (preview != nullptr) {
        DevelopExportOutcome preview_outcome =
            write_preview(output_sharpening.image, *preview, outcome);
        if (preview_outcome.succeeded) {
            tracker.finish();
            tracker.complete();
        }
        return preview_outcome;
    }

    if (request.format == DevelopExportFormat::png16) {
        negaflow::output::WicPngExportLimits output_limits{};
        output_limits.output_dpi = request.output_dpi;
        output_limits.bits_per_sample = request.output_bit_depth;
        output_limits.color_space = request.output_color_space;
        output_limits.conversion.preserve_alpha = request.preserve_alpha;
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
