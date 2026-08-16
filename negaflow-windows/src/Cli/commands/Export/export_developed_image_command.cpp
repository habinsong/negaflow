#include "../export_developed_image.h"

#include "developed_export_options.h"
#include "developed_export_report.h"
#include "../film_look_command_support.h"

#include "negaflow/core/negative_inversion.h"
#include "negaflow/imageio/image_file_observation.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "negaflow/output/wic_png_export.h"
#include "negaflow/output/wic_tiff_export.h"

#include <filesystem>
#include <utility>

namespace negaflow::cli {

int run_export_developed_image(
    const int argument_count,
    const wchar_t* const arguments[],
    const DevelopedExportFormat format) {
    if (!is_developed_export_argument_count(argument_count)) {
        return print_developed_export_error("invalid_argument_count");
    }
    if (format != DevelopedExportFormat::png16 &&
        format != DevelopedExportFormat::tiff16) {
        return print_developed_export_error("unknown_export_format");
    }

    DevelopedExportOptionsParseResult parsed =
        parse_developed_export_options(argument_count, arguments);
    if (!parsed.succeeded()) {
        return print_developed_export_error(parsed.error_code);
    }
    auto negative_parameters = parsed.options.negative;
    auto tone_parameters = parsed.options.tone;
    auto film_look_recipe = parsed.options.film_look;
    const std::filesystem::path source = std::move(parsed.options.source);
    const std::filesystem::path destination = std::move(parsed.options.destination);
    const ProcessCpuTimeSnapshot total_cpu_started =
        query_current_process_cpu_time();
    const DevelopedExportClock::time_point total_started = DevelopedExportClock::now();
    const negaflow::imageio::ImageFileObservationResult before =
        negaflow::imageio::observe_image_file(source);
    if (before.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return print_developed_export_observation_error(before);
    }

    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = developed_export_rows_per_copy;
    const ProcessCpuTimeSnapshot decode_cpu_started =
        query_current_process_cpu_time();
    const DevelopedExportClock::time_point decode_started = DevelopedExportClock::now();
    auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        source,
        {},
        {},
        decode_control);
    const DevelopedExportClock::time_point decode_finished = DevelopedExportClock::now();
    const ProcessCpuTimeSnapshot decode_cpu_finished =
        query_current_process_cpu_time();
    if (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok) {
        if (prepared.decode.status ==
                negaflow::imageio::WicTiffDecodeStatus::row_sink_failed &&
            prepared.working.status !=
                negaflow::imaging::ScannerToWorkingStatus::invalid_argument) {
            return print_developed_export_error(
                negaflow::imaging::scanner_to_working_status_name(prepared.working.status),
                prepared.working.info.native_error_code);
        }
        return print_developed_export_error(
            negaflow::imageio::wic_tiff_decode_status_name(prepared.decode.status));
    }
    if (prepared.working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
        return print_developed_export_error(
            negaflow::imaging::scanner_to_working_status_name(prepared.working.status),
            prepared.working.info.native_error_code);
    }

    const negaflow::imageio::ImageFileObservationResult after =
        negaflow::imageio::observe_image_file(source);
    if (after.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return print_developed_export_observation_error(after);
    }
    if (!negaflow::imageio::same_image_file_observation(
            before.observation,
            after.observation)) {
        return print_developed_export_error("source_changed_during_decode");
    }

    FilmLookCommandWorkspace film_look_workspace{};
    const FilmLookWorkspacePrepareStatus workspace_status =
        prepare_film_look_workspace(
            film_look_recipe.parameters,
            prepared.working.image.width,
            film_look_workspace);
    if (workspace_status != FilmLookWorkspacePrepareStatus::ok) {
        return print_developed_export_error(
            film_look_workspace_prepare_status_name(workspace_status));
    }
    const std::size_t prepared_film_look_workspace_bytes =
        film_look_workspace_bytes(film_look_workspace);

    const ProcessCpuTimeSnapshot develop_cpu_started =
        query_current_process_cpu_time();
    const DevelopedExportClock::time_point develop_started = DevelopedExportClock::now();
    auto developed = negaflow::imaging::develop_manual_negative(
        std::move(prepared.working.image),
        negative_parameters);
    const DevelopedExportClock::time_point develop_finished = DevelopedExportClock::now();
    const ProcessCpuTimeSnapshot develop_cpu_finished =
        query_current_process_cpu_time();
    if (developed.status != negaflow::imaging::ManualNegativeDevelopStatus::ok) {
        if (developed.status == negaflow::imaging::ManualNegativeDevelopStatus::kernel_failed) {
            return print_developed_export_error(negaflow::core::kernel_status_name(developed.info.kernel_status));
        }
        return print_developed_export_error(
            negaflow::imaging::manual_negative_develop_status_name(developed.status));
    }

    const ProcessCpuTimeSnapshot tone_adjust_cpu_started =
        query_current_process_cpu_time();
    const DevelopedExportClock::time_point tone_adjust_started = DevelopedExportClock::now();
    auto adjusted = negaflow::imaging::apply_working_tone_adjustments(
        std::move(developed.image),
        tone_parameters);
    const DevelopedExportClock::time_point tone_adjust_finished = DevelopedExportClock::now();
    const ProcessCpuTimeSnapshot tone_adjust_cpu_finished =
        query_current_process_cpu_time();
    if (adjusted.status != negaflow::imaging::WorkingToneAdjustStatus::ok) {
        if (adjusted.status ==
            negaflow::imaging::WorkingToneAdjustStatus::kernel_failed) {
            return print_developed_export_error(
                negaflow::core::kernel_status_name(adjusted.info.kernel_status));
        }
        if (adjusted.status ==
            negaflow::imaging::WorkingToneAdjustStatus::measurement_failed) {
            return print_developed_export_error(
                "tone_curve_measurement_failed",
                0U,
                0U,
                negaflow::imaging::tone_curve_measurement_status_name(
                    adjusted.info.measurement.status));
        }
        return print_developed_export_error(
            negaflow::imaging::working_tone_adjust_status_name(adjusted.status));
    }

    const ProcessCpuTimeSnapshot film_look_cpu_started =
        query_current_process_cpu_time();
    const DevelopedExportClock::time_point film_look_started = DevelopedExportClock::now();
    auto film_look = negaflow::imaging::apply_working_film_look(
        std::move(adjusted.image),
        film_look_recipe.parameters,
        film_look_workspace_view(film_look_workspace));
    const DevelopedExportClock::time_point film_look_finished = DevelopedExportClock::now();
    const ProcessCpuTimeSnapshot film_look_cpu_finished =
        query_current_process_cpu_time();
    if (film_look.status != negaflow::imaging::WorkingFilmLookStatus::ok) {
        if (film_look.status ==
            negaflow::imaging::WorkingFilmLookStatus::kernel_failed) {
            return print_developed_export_error(
                negaflow::core::kernel_status_name(
                    film_look.info.kernel_status));
        }
        return print_developed_export_error(
            negaflow::imaging::working_film_look_status_name(
                film_look.status));
    }

    const ProcessCpuTimeSnapshot output_cpu_started =
        query_current_process_cpu_time();
    const DevelopedExportClock::time_point output_started = DevelopedExportClock::now();
    if (format == DevelopedExportFormat::png16) {
        const negaflow::output::WicPngExportResult exported =
            negaflow::output::export_working_to_srgb16_png(film_look.image, destination);
        const DevelopedExportClock::time_point output_finished = DevelopedExportClock::now();
        const ProcessCpuTimeSnapshot output_cpu_finished =
            query_current_process_cpu_time();
        if (exported.status != negaflow::output::WicPngExportStatus::ok) {
            if (exported.status ==
                negaflow::output::WicPngExportStatus::working_conversion_failed) {
                return print_developed_export_error(
                    negaflow::output::working_to_srgb16_status_name(
                        exported.conversion_status),
                    exported.native_error_code,
                    exported.cleanup_error_code);
            }
            return print_developed_export_error(
                negaflow::output::wic_png_export_status_name(exported.status),
                exported.native_error_code,
                exported.cleanup_error_code);
        }
        const DevelopedExportPipelineReport context{
            negative_parameters,
            tone_parameters,
            prepared,
            developed,
            adjusted,
            film_look_recipe,
            film_look,
            before.observation.file_bytes,
            prepared_film_look_workspace_bytes,
            make_developed_export_stage_timing(
                decode_started,
                decode_finished,
                decode_cpu_started,
                decode_cpu_finished),
            make_developed_export_stage_timing(
                develop_started,
                develop_finished,
                develop_cpu_started,
                develop_cpu_finished),
            make_developed_export_stage_timing(
                tone_adjust_started,
                tone_adjust_finished,
                tone_adjust_cpu_started,
                tone_adjust_cpu_finished),
            make_developed_export_stage_timing(
                film_look_started,
                film_look_finished,
                film_look_cpu_started,
                film_look_cpu_finished),
            make_developed_export_stage_timing(
                output_started,
                output_finished,
                output_cpu_started,
                output_cpu_finished),
            make_developed_export_stage_timing(
                total_started,
                output_finished,
                total_cpu_started,
                output_cpu_finished),
        };
        return print_developed_png_success(exported, context);
    }

    const negaflow::output::WicTiffExportResult exported =
        negaflow::output::export_working_to_srgb16_tiff(film_look.image, destination);
    const DevelopedExportClock::time_point output_finished = DevelopedExportClock::now();
    const ProcessCpuTimeSnapshot output_cpu_finished =
        query_current_process_cpu_time();
    if (exported.status != negaflow::output::WicTiffExportStatus::ok) {
        if (exported.status ==
            negaflow::output::WicTiffExportStatus::working_conversion_failed) {
            return print_developed_export_error(
                negaflow::output::working_to_srgb16_status_name(
                    exported.conversion_status),
                exported.native_error_code,
                exported.cleanup_error_code);
        }
        return print_developed_export_error(
            negaflow::output::wic_tiff_export_status_name(exported.status),
            exported.native_error_code,
            exported.cleanup_error_code);
    }
    const DevelopedExportPipelineReport context{
        negative_parameters,
        tone_parameters,
        prepared,
        developed,
        adjusted,
        film_look_recipe,
        film_look,
        before.observation.file_bytes,
        prepared_film_look_workspace_bytes,
        make_developed_export_stage_timing(
            decode_started,
            decode_finished,
            decode_cpu_started,
            decode_cpu_finished),
        make_developed_export_stage_timing(
            develop_started,
            develop_finished,
            develop_cpu_started,
            develop_cpu_finished),
        make_developed_export_stage_timing(
            tone_adjust_started,
            tone_adjust_finished,
            tone_adjust_cpu_started,
            tone_adjust_cpu_finished),
        make_developed_export_stage_timing(
            film_look_started,
            film_look_finished,
            film_look_cpu_started,
            film_look_cpu_finished),
        make_developed_export_stage_timing(
            output_started,
            output_finished,
            output_cpu_started,
            output_cpu_finished),
        make_developed_export_stage_timing(
            total_started,
            output_finished,
            total_cpu_started,
            output_cpu_finished),
    };
    return print_developed_tiff_success(exported, context);
}

}  // namespace negaflow::cli
