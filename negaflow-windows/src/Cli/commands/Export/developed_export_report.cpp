#include "developed_export_report.h"

#include "negaflow/core/negative_inversion.h"

#include <iomanip>
#include <iostream>

namespace negaflow::cli {

[[nodiscard]] std::uint64_t elapsed_microseconds(
    const DevelopedExportClock::time_point started,
    const DevelopedExportClock::time_point finished) noexcept {
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(finished - started).count());
}

[[nodiscard]] DevelopedExportStageTiming make_developed_export_stage_timing(
    const DevelopedExportClock::time_point wall_started,
    const DevelopedExportClock::time_point wall_finished,
    const ProcessCpuTimeSnapshot& cpu_started,
    const ProcessCpuTimeSnapshot& cpu_finished) noexcept {
    return {
        elapsed_microseconds(wall_started, wall_finished),
        elapsed_process_cpu_microseconds(cpu_started, cpu_finished),
    };
}

int print_developed_export_error(
    const std::string_view code,
    const std::uint32_t native_error_code,
    const std::uint32_t cleanup_error_code,
    const char* const detail) {
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

int print_developed_export_observation_error(
    const negaflow::imageio::ImageFileObservationResult& observation) {
    return print_developed_export_error(
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

void print_pipeline_report_suffix(const DevelopedExportPipelineReport& context) {
    const auto working_pixel_bytes =
        context.film_look.image.pixels.size() * sizeof(negaflow::core::Rgba32F);
    const auto& measurement = context.adjusted.info.measurement.info;
    std::cout << ",\"source_file_bytes\":" << context.source_file_bytes
              << ",\"source_observation_mode\":\"file_id_size_last_write\","
                 "\"source_unchanged_during_decode\":true,"
                 "\"source_sha256_mode\":\"off\",\"artifact_sha256_mode\":\"off\","
                 "\"cpu_time_source\":\"get_process_times\","
                 "\"cpu_time_scope\":\"process_user_plus_kernel_all_threads\","
                 "\"stages\":{\"decode_and_color_convert\":{"
                 "\"mode\":\"row_streaming\",\"developed_export_rows_per_copy\":"
              << developed_export_rows_per_copy << ",\"source_pixel_format\":\""
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
              << ",\"deflate_streams_validated\":"
              << (context.prepared.decode.info.deflate_streams_validated
                      ? "true"
                      : "false")
              << ",\"compressed_bytes_validated\":"
              << context.prepared.decode.info.compressed_bytes_validated
              << ",\"lzw_code_count\":"
              << context.prepared.decode.info.lzw_code_count
              << ",\"lzw_decoded_bytes_validated\":"
              << context.prepared.decode.info.lzw_decoded_bytes_validated
              << ",\"deflate_decoded_bytes_validated\":"
              << context.prepared.decode.info.deflate_decoded_bytes_validated
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
              << "},\"film_look\":{\"algorithm_version\":\""
              << negaflow::imaging::working_film_look_algorithm_version
              << "\",\"arguments_explicit\":"
              << (context.film_look_recipe.arguments_explicit ? "true" : "false")
              << ",\"source_kind\":\""
              << negaflow::imaging::develop_source_kind_name(
                     context.film_look_recipe.parameters.source_kind)
              << "\",\"film_emulation\":\""
              << film_emulation_recipe_name(
                     context.film_look_recipe.parameters.emulation)
              << "\",\"intensity\":"
              << std::setprecision(std::numeric_limits<double>::max_digits10)
              << context.film_look_recipe.parameters.intensity
              << ",\"route\":\""
              << negaflow::imaging::film_look_route_name(
                     context.film_look.info.route)
              << "\",\"color_algorithm_version\":\""
              << negaflow::imaging::film_emulation_color_algorithm_version
              << "\",\"acutance_algorithm_version\":\""
              << negaflow::imaging::film_emulation_acutance_algorithm_version
              << "\",\"color_intensity_step\":"
              << context.film_look.info.color_intensity_step
              << ",\"acutance_amount\":"
              << context.film_look.info.acutance_amount
              << ",\"color_cube_built\":"
              << (context.film_look.info.color_cube_built ? "true" : "false")
              << ",\"color_cube_reused\":"
              << (context.film_look.info.color_cube_reused ? "true" : "false")
              << ",\"color_applied\":"
              << (context.film_look.info.color_applied ? "true" : "false")
              << ",\"acutance_applied\":"
              << (context.film_look.info.acutance_applied ? "true" : "false")
              << ",\"required_acutance_scratch_pixels\":"
              << context.film_look.info.required_acutance_scratch_pixels
              << ",\"peak_workspace_bytes\":"
              << context.film_look_workspace_bytes
              << ",\"additional_full_frame_bytes\":0,\"wall_microseconds\":"
              << context.film_look_timing.wall_microseconds
              << ",\"cpu_microseconds\":";
    print_cpu_microseconds(context.film_look_timing.cpu_microseconds);
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

int print_developed_png_success(
    const negaflow::output::WicPngExportResult& exported,
    const DevelopedExportPipelineReport& context) {
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

int print_developed_tiff_success(
    const negaflow::output::WicTiffExportResult& exported,
    const DevelopedExportPipelineReport& context) {
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


}  // namespace negaflow::cli
