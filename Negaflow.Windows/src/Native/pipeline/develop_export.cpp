#include "negaflow/pipeline/develop_export.h"

#include "negaflow/core/pixel.h"
#include "negaflow/pipeline/film_look_workspace.h"

#include <utility>

namespace negaflow::pipeline {
namespace {

[[nodiscard]] DevelopExportOutcome fail(
    const DevelopExportStage stage,
    const char* const name,
    const std::uint32_t native_error_code = 0U,
    const std::uint32_t cleanup_error_code = 0U) noexcept {
    DevelopExportOutcome outcome{};
    outcome.succeeded = false;
    outcome.failed_stage = stage;
    outcome.failure_name = name;
    outcome.native_error_code = native_error_code;
    outcome.cleanup_error_code = cleanup_error_code;
    return outcome;
}

}  // namespace

const char* develop_export_stage_name(const DevelopExportStage stage) noexcept {
    switch (stage) {
        case DevelopExportStage::none:
            return "none";
        case DevelopExportStage::request_validation:
            return "request_validation";
        case DevelopExportStage::observe_source_before:
            return "observe_source_before";
        case DevelopExportStage::decode:
            return "decode";
        case DevelopExportStage::observe_source_after:
            return "observe_source_after";
        case DevelopExportStage::film_look_workspace:
            return "film_look_workspace";
        case DevelopExportStage::develop:
            return "develop";
        case DevelopExportStage::tone_adjust:
            return "tone_adjust";
        case DevelopExportStage::film_look:
            return "film_look";
        case DevelopExportStage::output:
            return "output";
    }
    return "unknown_stage";
}

DevelopExportOutcome develop_and_export(
    const DevelopExportRequest& request) noexcept {
    if (request.source.empty() || request.destination.empty()) {
        return fail(DevelopExportStage::request_validation, "missing_path");
    }
    if (request.format != DevelopExportFormat::png16 &&
        request.format != DevelopExportFormat::tiff16) {
        return fail(DevelopExportStage::request_validation, "unknown_export_format");
    }
    if (request.rows_per_copy == 0U) {
        return fail(DevelopExportStage::request_validation, "invalid_rows_per_copy");
    }
    if (!negaflow::imaging::valid_working_tone_adjust_parameters(request.tone)) {
        return fail(
            DevelopExportStage::request_validation,
            "invalid_tone_adjustment_parameter");
    }
    if (!negaflow::imaging::valid_working_film_look_parameters(request.film_look)) {
        return fail(
            DevelopExportStage::request_validation, "invalid_film_look_parameters");
    }
    // The rendered-digital graph is not implemented, and a negative develop is not a
    // meaningful thing to ask of it. Refuse rather than silently developing anyway.
    if (request.film_look.source_kind !=
        negaflow::imaging::DevelopSourceKind::film_scan) {
        return fail(
            DevelopExportStage::request_validation,
            "negative_develop_requires_film_scan_source");
    }

    const negaflow::imageio::ImageFileObservationResult before =
        negaflow::imageio::observe_image_file(request.source);
    if (before.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return fail(
            DevelopExportStage::observe_source_before,
            negaflow::imageio::image_file_observation_status_name(before.status),
            before.native_error_code);
    }

    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = request.rows_per_copy;
    auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        request.source,
        {},
        {},
        decode_control);
    if (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok) {
        if (prepared.decode.status ==
                negaflow::imageio::WicTiffDecodeStatus::row_sink_failed &&
            prepared.working.status !=
                negaflow::imaging::ScannerToWorkingStatus::invalid_argument) {
            return fail(
                DevelopExportStage::decode,
                negaflow::imaging::scanner_to_working_status_name(
                    prepared.working.status),
                prepared.working.info.native_error_code);
        }
        return fail(
            DevelopExportStage::decode,
            negaflow::imageio::wic_tiff_decode_status_name(prepared.decode.status));
    }
    if (prepared.working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
        return fail(
            DevelopExportStage::decode,
            negaflow::imaging::scanner_to_working_status_name(
                prepared.working.status),
            prepared.working.info.native_error_code);
    }

    const negaflow::imageio::ImageFileObservationResult after =
        negaflow::imageio::observe_image_file(request.source);
    if (after.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return fail(
            DevelopExportStage::observe_source_after,
            negaflow::imageio::image_file_observation_status_name(after.status),
            after.native_error_code);
    }
    if (!negaflow::imageio::same_image_file_observation(
            before.observation,
            after.observation)) {
        return fail(
            DevelopExportStage::observe_source_after, "source_changed_during_decode");
    }

    const std::uint32_t decoded_width = prepared.working.image.width;
    const std::uint32_t decoded_height = prepared.working.image.height;

    FilmLookWorkspaceStorage workspace{};
    const FilmLookWorkspacePrepareStatus workspace_status =
        prepare_film_look_workspace(request.film_look, decoded_width, workspace);
    if (workspace_status != FilmLookWorkspacePrepareStatus::ok) {
        return fail(
            DevelopExportStage::film_look_workspace,
            film_look_workspace_prepare_status_name(workspace_status));
    }
    const std::size_t workspace_bytes = film_look_workspace_bytes(workspace);

    auto developed = negaflow::imaging::develop_manual_negative(
        std::move(prepared.working.image),
        request.negative);
    if (developed.status != negaflow::imaging::ManualNegativeDevelopStatus::ok) {
        if (developed.status ==
            negaflow::imaging::ManualNegativeDevelopStatus::kernel_failed) {
            return fail(
                DevelopExportStage::develop,
                negaflow::core::kernel_status_name(developed.info.kernel_status));
        }
        return fail(
            DevelopExportStage::develop,
            negaflow::imaging::manual_negative_develop_status_name(developed.status));
    }

    auto adjusted = negaflow::imaging::apply_working_tone_adjustments(
        std::move(developed.image),
        request.tone);
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

    auto film_look = negaflow::imaging::apply_working_film_look(
        std::move(adjusted.image),
        request.film_look,
        film_look_workspace_view(workspace));
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

    DevelopExportOutcome outcome{};
    outcome.image_width = decoded_width;
    outcome.image_height = decoded_height;
    outcome.source_file_bytes = before.observation.file_bytes;
    outcome.film_look_workspace_bytes = workspace_bytes;
    outcome.film_look_route = film_look.info.route;
    outcome.film_look_color_applied = film_look.info.color_applied;
    outcome.film_look_acutance_applied = film_look.info.acutance_applied;

    if (request.format == DevelopExportFormat::png16) {
        const negaflow::output::WicPngExportResult exported =
            negaflow::output::export_working_to_srgb16_png(
                film_look.image,
                request.destination);
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
        return outcome;
    }

    const negaflow::output::WicTiffExportResult exported =
        negaflow::output::export_working_to_srgb16_tiff(
            film_look.image,
            request.destination);
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
    return outcome;
}

}  // namespace negaflow::pipeline
