#include "export_developed_image.h"

#include "process_cpu_time.h"

#include "negaflow/core/negative_inversion.h"
#include "negaflow/imageio/image_file_observation.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "negaflow/output/wic_png_export.h"
#include "negaflow/output/wic_tiff_export.h"

#include <array>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <limits>
#include <optional>
#include <string_view>
#include <system_error>
#include <utility>

namespace negaflow::cli {
namespace {

using Clock = std::chrono::steady_clock;

constexpr std::uint32_t rows_per_copy = 64U;

struct StageTiming final {
    std::uint64_t wall_microseconds{0};
    std::optional<std::uint64_t> cpu_microseconds{};
};

struct PipelineReportContext final {
    const negaflow::imaging::ManualNegativeDevelopParameters& negative_parameters;
    const negaflow::imaging::WorkingToneAdjustParameters& tone_parameters;
    const negaflow::imaging::StreamedScannerToWorkingResult& prepared;
    const negaflow::imaging::ManualNegativeDevelopResult& developed;
    const negaflow::imaging::WorkingToneAdjustResult& adjusted;
    std::uint64_t source_file_bytes{0};
    StageTiming decode_and_color{};
    StageTiming develop{};
    StageTiming tone_adjust{};
    StageTiming output{};
    StageTiming total{};
};

[[nodiscard]] bool parse_finite_float(const std::wstring_view text, float& value) noexcept {
    if (text.empty() || text.size() > 127U) {
        return false;
    }
    std::array<char, 128> ascii{};
    for (std::size_t index = 0U; index < text.size(); ++index) {
        if (text[index] < 0 || text[index] > 127) {
            return false;
        }
        ascii[index] = static_cast<char>(text[index]);
    }
    const auto [end, error] =
        std::from_chars(ascii.data(), ascii.data() + text.size(), value, std::chars_format::general);
    return error == std::errc{} && end == ascii.data() + text.size() && std::isfinite(value);
}

[[nodiscard]] std::uint64_t elapsed_microseconds(
    const Clock::time_point started,
    const Clock::time_point finished) noexcept {
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(finished - started).count());
}

[[nodiscard]] StageTiming make_stage_timing(
    const Clock::time_point wall_started,
    const Clock::time_point wall_finished,
    const ProcessCpuTimeSnapshot& cpu_started,
    const ProcessCpuTimeSnapshot& cpu_finished) noexcept {
    return {
        elapsed_microseconds(wall_started, wall_finished),
        elapsed_process_cpu_microseconds(cpu_started, cpu_finished),
    };
}

int print_error(
    const std::string_view code,
    const std::uint32_t native_error_code = 0U,
    const std::uint32_t cleanup_error_code = 0U,
    const char* const detail = nullptr) {
    std::cerr << "{\"schema_version\":1,\"status\":\"error\","
                 "\"error\":{\"code\":\""
              << code << '"';
    if (detail != nullptr) {
        std::cerr << ",\"detail\":\"" << detail << '"';
    }
    if (native_error_code != 0U) {
        std::cerr << ",\"native_error_code\":\"0x" << std::hex << std::setw(8)
                  << std::setfill('0') << native_error_code << std::dec << '"';
    }
    if (cleanup_error_code != 0U) {
        std::cerr << ",\"cleanup_error_code\":\"0x" << std::hex << std::setw(8)
                  << std::setfill('0') << cleanup_error_code << std::dec << '"';
    }
    std::cerr << "}}\n";
    return 2;
}

int print_observation_error(
    const negaflow::imageio::ImageFileObservationResult& observation) {
    return print_error(
        "source_observation_failed",
        observation.native_error_code,
        0U,
        negaflow::imageio::image_file_observation_status_name(observation.status));
}

void print_cpu_microseconds(const std::optional<std::uint64_t> value) {
    if (value.has_value()) {
        std::cout << *value;
    } else {
        std::cout << "null";
    }
}

void print_pipeline_report_suffix(const PipelineReportContext& context) {
    const auto working_pixel_bytes =
        context.adjusted.image.pixels.size() * sizeof(negaflow::core::Rgba32F);
    const auto& measurement = context.adjusted.info.measurement.info;
    std::cout << ",\"source_file_bytes\":" << context.source_file_bytes
              << ",\"source_observation_mode\":\"file_id_size_last_write\","
                 "\"source_unchanged_during_decode\":true,"
                 "\"source_sha256_mode\":\"off\",\"artifact_sha256_mode\":\"off\","
                 "\"cpu_time_source\":\"get_process_times\","
                 "\"cpu_time_scope\":\"process_user_plus_kernel_all_threads\","
                 "\"stages\":{\"decode_and_color_convert\":{"
                 "\"mode\":\"row_streaming\",\"rows_per_copy\":"
              << rows_per_copy << ",\"source_pixel_format\":\""
              << negaflow::imageio::wic_pixel_format_name(
                     context.prepared.decode.info.source_pixel_format)
              << "\",\"output_pixel_format\":\""
              << negaflow::imageio::wic_pixel_format_name(
                     context.prepared.decode.info.output_pixel_format)
              << "\",\"format_conversion_used\":"
              << (context.prepared.decode.info.format_conversion_used ? "true" : "false")
              << ",\"frame_count\":" << context.prepared.decode.info.frame_count
              << ",\"completed_rows\":" << context.prepared.decode.info.completed_rows
              << ",\"decoded_pixel_bytes\":"
              << context.prepared.decode.info.decoded_pixel_bytes
              << ",\"compressed_segment_bytes\":"
              << context.prepared.decode.info.compressed_segment_bytes
              << ",\"lzw_code_streams_validated\":"
              << (context.prepared.decode.info.lzw_code_streams_validated
                      ? "true"
                      : "false")
              << ",\"compressed_bytes_validated\":"
              << context.prepared.decode.info.compressed_bytes_validated
              << ",\"lzw_code_count\":"
              << context.prepared.decode.info.lzw_code_count
              << ",\"lzw_decoded_bytes_validated\":"
              << context.prepared.decode.info.lzw_decoded_bytes_validated
              << ",\"peak_copy_pixel_bytes\":"
              << context.prepared.decode.info.peak_copy_pixel_bytes
              << ",\"copy_operation_count\":"
              << context.prepared.decode.info.copy_operation_count
              << ",\"scanner_transform\":\""
              << negaflow::imaging::scanner_working_transform_name(
                     context.prepared.working.info.transform)
              << "\",\"intermediate_bits_per_color_channel\":"
              << static_cast<std::uint32_t>(
                     context.prepared.working.info.intermediate_bits_per_color_channel)
              << ",\"working_pixel_bytes\":" << working_pixel_bytes
              << ",\"peak_conversion_temporary_bytes\":"
              << context.prepared.info.peak_conversion_temporary_pixel_bytes
              << ",\"wall_microseconds\":"
              << context.decode_and_color.wall_microseconds
              << ",\"cpu_microseconds\":";
    print_cpu_microseconds(context.decode_and_color.cpu_microseconds);
    std::cout
              << "},\"develop\":{\"manual_dmin\":["
              << std::setprecision(std::numeric_limits<float>::max_digits10)
              << context.developed.info.applied_dmin[0] << ','
              << context.developed.info.applied_dmin[1] << ','
              << context.developed.info.applied_dmin[2]
              << "],\"dmax_normalized\":["
              << context.developed.info.dmax_normalized[0] << ','
              << context.developed.info.dmax_normalized[1] << ','
              << context.developed.info.dmax_normalized[2]
              << "],\"additional_full_frame_bytes\":0,\"wall_microseconds\":"
              << context.develop.wall_microseconds
              << ",\"cpu_microseconds\":";
    print_cpu_microseconds(context.develop.cpu_microseconds);
    std::cout
              << "},\"tone_adjust\":{\"algorithm_version\":\""
              << negaflow::imaging::tone_mapping_algorithm_version
              << "\",\"formula_reference\":\"macos_chromabase\","
                 "\"exposure_stops\":"
              << context.tone_parameters.exposure_stops
              << ",\"basic\":{\"contrast\":"
              << context.tone_parameters.basic.contrast
              << ",\"density\":" << context.tone_parameters.basic.density
              << ",\"highlights\":" << context.tone_parameters.basic.highlights
              << ",\"shadows\":" << context.tone_parameters.basic.shadows
              << ",\"whites\":" << context.tone_parameters.basic.whites
              << ",\"blacks\":" << context.tone_parameters.basic.blacks
              << "},\"curve\":{\"highlights\":"
              << context.tone_parameters.curve.highlights
              << ",\"lights\":" << context.tone_parameters.curve.lights
              << ",\"darks\":" << context.tone_parameters.curve.darks
              << ",\"shadows\":" << context.tone_parameters.curve.shadows
              << "},\"exposure_applied\":"
              << (context.adjusted.info.exposure_applied ? "true" : "false")
              << ",\"basic_tone_applied\":"
              << (context.adjusted.info.basic_tone_applied ? "true" : "false")
              << ",\"parametric_curve_applied\":"
              << (context.adjusted.info.parametric_curve_applied ? "true" : "false")
              << ",\"point_curve_algorithm_version\":\""
              << negaflow::imaging::point_curve_algorithm_version
              << "\",\"point_curve_applied\":"
              << (context.adjusted.info.point_curve_applied ? "true" : "false")
              << ",\"color_mixer_algorithm_version\":\""
              << negaflow::imaging::color_mixer_algorithm_version
              << "\",\"color_mixer_applied\":"
              << (context.adjusted.info.color_mixer_applied ? "true" : "false")
              << ",\"color_grading_algorithm_version\":\""
              << negaflow::imaging::color_grading_algorithm_version
              << "\",\"color_grading_applied\":"
              << (context.adjusted.info.color_grading_applied ? "true" : "false")
              << ",\"calibration_algorithm_version\":\""
              << negaflow::imaging::primary_calibration_algorithm_version
              << "\",\"calibration_applied\":"
              << (context.adjusted.info.primary_calibration_applied
                      ? "true"
                      : "false")
              << ",\"curve_sampling_mode\":\""
              << negaflow::imaging::tone_curve_sampling_mode_name(
                     measurement.sampling_mode)
              << "\",\"curve_sampling_target_width\":"
              << measurement.target_width
              << ",\"curve_sampling_target_height\":"
              << measurement.target_height
              << ",\"curve_sampled_luma_count\":"
              << measurement.sampled_luma_count;
    if (context.adjusted.info.parametric_curve_applied) {
        std::cout << ",\"curve_bands\":{\"shadow_low\":"
                  << measurement.bands.shadow_low
                  << ",\"shadow_high\":" << measurement.bands.shadow_high
                  << ",\"dark_low\":" << measurement.bands.dark_low
                  << ",\"dark_high\":" << measurement.bands.dark_high
                  << ",\"light_low\":" << measurement.bands.light_low
                  << ",\"light_high\":" << measurement.bands.light_high
                  << ",\"highlight_low\":" << measurement.bands.highlight_low
                  << ",\"highlight_high\":" << measurement.bands.highlight_high
                  << '}';
    } else {
        std::cout << ",\"curve_bands\":null";
    }
    std::cout << ",\"additional_full_frame_bytes\":0,"
                 "\"peak_measurement_temporary_bytes\":"
              << measurement.peak_temporary_bytes
              << ",\"wall_microseconds\":"
              << context.tone_adjust.wall_microseconds
              << ",\"cpu_microseconds\":";
    print_cpu_microseconds(context.tone_adjust.cpu_microseconds);
    std::cout
              << "},\"output_convert_encode_verify_publish\":{"
                 "\"wall_microseconds\":"
              << context.output.wall_microseconds
              << ",\"cpu_microseconds\":";
    print_cpu_microseconds(context.output.cpu_microseconds);
    std::cout << "}},\"total_wall_microseconds\":"
              << context.total.wall_microseconds
              << ",\"total_cpu_microseconds\":";
    print_cpu_microseconds(context.total.cpu_microseconds);
    std::cout << "}\n";
}

int print_png_success(
    const negaflow::output::WicPngExportResult& exported,
    const PipelineReportContext& context) {
    std::cout << "{\"schema_version\":1,\"status\":\"ok\","
                 "\"operation\":\"export_developed_png16\","
                 "\"format\":\"png16_rgb\","
                 "\"working_space\":\"extended_linear_srgb_rgba_f32\","
                 "\"destination_space\":\"srgb\","
                 "\"encoder\":\"microsoft_builtin_wic_png\","
                 "\"algorithm_version\":\""
              << negaflow::core::negative_inversion_algorithm_version
              << "\",\"film_type\":\""
              << negaflow::imaging::negative_film_type_name(
                     context.negative_parameters.film_type)
              << "\",\"width\":" << exported.info.width
              << ",\"height\":" << exported.info.height
              << ",\"encoded_pixel_bytes\":" << exported.info.encoded_pixel_bytes
              << ",\"artifact_bytes\":" << exported.info.artifact_bytes
              << ",\"color_profile_bytes\":" << exported.info.color_profile_bytes
              << ",\"clipped_color_components\":"
              << exported.info.clipped_color_components
              << ",\"structure_verified\":true,\"pixels_verified\":true,"
                 "\"profile_verified\":true,\"published\":true,"
                 "\"publish_mode\":\"same_directory_create_new_move\"";
    print_pipeline_report_suffix(context);
    return 0;
}

int print_tiff_success(
    const negaflow::output::WicTiffExportResult& exported,
    const PipelineReportContext& context) {
    std::cout << "{\"schema_version\":1,\"status\":\"ok\","
                 "\"operation\":\"export_developed_tiff16\","
                 "\"format\":\"tiff16_rgb\","
                 "\"working_space\":\"extended_linear_srgb_rgba_f32\","
                 "\"destination_space\":\"srgb\","
                 "\"encoder\":\"microsoft_builtin_wic_tiff\","
                 "\"algorithm_version\":\""
              << negaflow::core::negative_inversion_algorithm_version
              << "\",\"film_type\":\""
              << negaflow::imaging::negative_film_type_name(
                     context.negative_parameters.film_type)
              << "\",\"width\":" << exported.info.width
              << ",\"height\":" << exported.info.height
              << ",\"encoded_pixel_bytes\":" << exported.info.encoded_pixel_bytes
              << ",\"artifact_bytes\":" << exported.info.artifact_bytes
              << ",\"color_profile_bytes\":" << exported.info.color_profile_bytes
              << ",\"clipped_color_components\":"
              << exported.info.clipped_color_components
              << ",\"compression\":\"none\",\"compression_tag\":"
              << exported.info.compression
              << ",\"strip_count\":" << exported.info.strip_count
              << ",\"ifd_entry_count\":" << exported.info.ifd_entry_count
              << ",\"metadata_policy\":\"minimal\","
                 "\"structure_verified\":true,\"metadata_verified\":true,"
                 "\"pixels_verified\":true,\"profile_verified\":true,"
                 "\"published\":true,"
                 "\"publish_mode\":\"same_directory_create_new_move\"";
    print_pipeline_report_suffix(context);
    return 0;
}

}  // namespace

int run_export_developed_image(
    const int argument_count,
    const wchar_t* const arguments[],
    const DevelopedExportFormat format) {
    if (argument_count != 8 && argument_count != 14) {
        return print_error("invalid_argument_count");
    }
    if (format != DevelopedExportFormat::png16 &&
        format != DevelopedExportFormat::tiff16) {
        return print_error("unknown_export_format");
    }

    negaflow::imaging::ManualNegativeDevelopParameters negative_parameters{};
    for (std::size_t channel = 0U; channel < negative_parameters.dmin.size(); ++channel) {
        if (!parse_finite_float(
                arguments[channel + 4U],
                negative_parameters.dmin[channel])) {
            return print_error("invalid_dmin");
        }
    }
    const std::wstring_view film_type{arguments[7]};
    if (film_type == L"color") {
        negative_parameters.film_type = negaflow::imaging::NegativeFilmType::color;
    } else if (film_type == L"bw") {
        negative_parameters.film_type =
            negaflow::imaging::NegativeFilmType::black_and_white;
    } else {
        return print_error("unknown_film_type");
    }

    negaflow::imaging::WorkingToneAdjustParameters tone_parameters{};
    if (argument_count == 14) {
        if (!parse_finite_float(arguments[8], tone_parameters.exposure_stops) ||
            !parse_finite_float(arguments[9], tone_parameters.basic.contrast) ||
            !parse_finite_float(arguments[10], tone_parameters.curve.highlights) ||
            !parse_finite_float(arguments[11], tone_parameters.curve.lights) ||
            !parse_finite_float(arguments[12], tone_parameters.curve.darks) ||
            !parse_finite_float(arguments[13], tone_parameters.curve.shadows) ||
            !negaflow::imaging::valid_working_tone_adjust_parameters(
                tone_parameters)) {
            return print_error("invalid_tone_adjustment_parameter");
        }
    }

    const std::filesystem::path source{arguments[2]};
    const std::filesystem::path destination{arguments[3]};
    const ProcessCpuTimeSnapshot total_cpu_started =
        query_current_process_cpu_time();
    const Clock::time_point total_started = Clock::now();
    const negaflow::imageio::ImageFileObservationResult before =
        negaflow::imageio::observe_image_file(source);
    if (before.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return print_observation_error(before);
    }

    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = rows_per_copy;
    const ProcessCpuTimeSnapshot decode_cpu_started =
        query_current_process_cpu_time();
    const Clock::time_point decode_started = Clock::now();
    auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        source,
        {},
        {},
        decode_control);
    const Clock::time_point decode_finished = Clock::now();
    const ProcessCpuTimeSnapshot decode_cpu_finished =
        query_current_process_cpu_time();
    if (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok) {
        if (prepared.decode.status ==
                negaflow::imageio::WicTiffDecodeStatus::row_sink_failed &&
            prepared.working.status !=
                negaflow::imaging::ScannerToWorkingStatus::invalid_argument) {
            return print_error(
                negaflow::imaging::scanner_to_working_status_name(prepared.working.status),
                prepared.working.info.native_error_code);
        }
        return print_error(
            negaflow::imageio::wic_tiff_decode_status_name(prepared.decode.status));
    }
    if (prepared.working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
        return print_error(
            negaflow::imaging::scanner_to_working_status_name(prepared.working.status),
            prepared.working.info.native_error_code);
    }

    const negaflow::imageio::ImageFileObservationResult after =
        negaflow::imageio::observe_image_file(source);
    if (after.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return print_observation_error(after);
    }
    if (!negaflow::imageio::same_image_file_observation(
            before.observation,
            after.observation)) {
        return print_error("source_changed_during_decode");
    }

    const ProcessCpuTimeSnapshot develop_cpu_started =
        query_current_process_cpu_time();
    const Clock::time_point develop_started = Clock::now();
    auto developed = negaflow::imaging::develop_manual_negative(
        std::move(prepared.working.image),
        negative_parameters);
    const Clock::time_point develop_finished = Clock::now();
    const ProcessCpuTimeSnapshot develop_cpu_finished =
        query_current_process_cpu_time();
    if (developed.status != negaflow::imaging::ManualNegativeDevelopStatus::ok) {
        if (developed.status == negaflow::imaging::ManualNegativeDevelopStatus::kernel_failed) {
            return print_error(negaflow::core::kernel_status_name(developed.info.kernel_status));
        }
        return print_error(
            negaflow::imaging::manual_negative_develop_status_name(developed.status));
    }

    const ProcessCpuTimeSnapshot tone_adjust_cpu_started =
        query_current_process_cpu_time();
    const Clock::time_point tone_adjust_started = Clock::now();
    auto adjusted = negaflow::imaging::apply_working_tone_adjustments(
        std::move(developed.image),
        tone_parameters);
    const Clock::time_point tone_adjust_finished = Clock::now();
    const ProcessCpuTimeSnapshot tone_adjust_cpu_finished =
        query_current_process_cpu_time();
    if (adjusted.status != negaflow::imaging::WorkingToneAdjustStatus::ok) {
        if (adjusted.status ==
            negaflow::imaging::WorkingToneAdjustStatus::kernel_failed) {
            return print_error(
                negaflow::core::kernel_status_name(adjusted.info.kernel_status));
        }
        if (adjusted.status ==
            negaflow::imaging::WorkingToneAdjustStatus::measurement_failed) {
            return print_error(
                "tone_curve_measurement_failed",
                0U,
                0U,
                negaflow::imaging::tone_curve_measurement_status_name(
                    adjusted.info.measurement.status));
        }
        return print_error(
            negaflow::imaging::working_tone_adjust_status_name(adjusted.status));
    }

    const ProcessCpuTimeSnapshot output_cpu_started =
        query_current_process_cpu_time();
    const Clock::time_point output_started = Clock::now();
    if (format == DevelopedExportFormat::png16) {
        const negaflow::output::WicPngExportResult exported =
            negaflow::output::export_working_to_srgb16_png(adjusted.image, destination);
        const Clock::time_point output_finished = Clock::now();
        const ProcessCpuTimeSnapshot output_cpu_finished =
            query_current_process_cpu_time();
        if (exported.status != negaflow::output::WicPngExportStatus::ok) {
            if (exported.status ==
                negaflow::output::WicPngExportStatus::working_conversion_failed) {
                return print_error(
                    negaflow::output::working_to_srgb16_status_name(
                        exported.conversion_status),
                    exported.native_error_code,
                    exported.cleanup_error_code);
            }
            return print_error(
                negaflow::output::wic_png_export_status_name(exported.status),
                exported.native_error_code,
                exported.cleanup_error_code);
        }
        const PipelineReportContext context{
            negative_parameters,
            tone_parameters,
            prepared,
            developed,
            adjusted,
            before.observation.file_bytes,
            make_stage_timing(
                decode_started,
                decode_finished,
                decode_cpu_started,
                decode_cpu_finished),
            make_stage_timing(
                develop_started,
                develop_finished,
                develop_cpu_started,
                develop_cpu_finished),
            make_stage_timing(
                tone_adjust_started,
                tone_adjust_finished,
                tone_adjust_cpu_started,
                tone_adjust_cpu_finished),
            make_stage_timing(
                output_started,
                output_finished,
                output_cpu_started,
                output_cpu_finished),
            make_stage_timing(
                total_started,
                output_finished,
                total_cpu_started,
                output_cpu_finished),
        };
        return print_png_success(exported, context);
    }

    const negaflow::output::WicTiffExportResult exported =
        negaflow::output::export_working_to_srgb16_tiff(adjusted.image, destination);
    const Clock::time_point output_finished = Clock::now();
    const ProcessCpuTimeSnapshot output_cpu_finished =
        query_current_process_cpu_time();
    if (exported.status != negaflow::output::WicTiffExportStatus::ok) {
        if (exported.status ==
            negaflow::output::WicTiffExportStatus::working_conversion_failed) {
            return print_error(
                negaflow::output::working_to_srgb16_status_name(
                    exported.conversion_status),
                exported.native_error_code,
                exported.cleanup_error_code);
        }
        return print_error(
            negaflow::output::wic_tiff_export_status_name(exported.status),
            exported.native_error_code,
            exported.cleanup_error_code);
    }
    const PipelineReportContext context{
        negative_parameters,
        tone_parameters,
        prepared,
        developed,
        adjusted,
        before.observation.file_bytes,
        make_stage_timing(
            decode_started,
            decode_finished,
            decode_cpu_started,
            decode_cpu_finished),
        make_stage_timing(
            develop_started,
            develop_finished,
            develop_cpu_started,
            develop_cpu_finished),
        make_stage_timing(
            tone_adjust_started,
            tone_adjust_finished,
            tone_adjust_cpu_started,
            tone_adjust_cpu_finished),
        make_stage_timing(
            output_started,
            output_finished,
            output_cpu_started,
            output_cpu_finished),
        make_stage_timing(
            total_started,
            output_finished,
            total_cpu_started,
            output_cpu_finished),
    };
    return print_tiff_success(exported, context);
}

}  // namespace negaflow::cli
