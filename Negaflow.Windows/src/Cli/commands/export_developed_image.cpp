#include "export_developed_image.h"

#include "negaflow/core/negative_inversion.h"
#include "negaflow/imageio/image_file_observation.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
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
#include <string_view>
#include <system_error>
#include <utility>

namespace negaflow::cli {
namespace {

using Clock = std::chrono::steady_clock;

constexpr std::uint32_t rows_per_copy = 64U;

struct PipelineReportContext final {
    const negaflow::imaging::ManualNegativeDevelopParameters& parameters;
    const negaflow::imaging::StreamedScannerToWorkingResult& prepared;
    const negaflow::imaging::ManualNegativeDevelopResult& developed;
    std::uint64_t source_file_bytes{0};
    std::uint64_t decode_and_color_wall_microseconds{0};
    std::uint64_t develop_wall_microseconds{0};
    std::uint64_t output_wall_microseconds{0};
    std::uint64_t total_wall_microseconds{0};
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

void print_pipeline_report_suffix(const PipelineReportContext& context) {
    const auto working_pixel_bytes =
        context.developed.image.pixels.size() * sizeof(negaflow::core::Rgba32F);
    std::cout << ",\"source_file_bytes\":" << context.source_file_bytes
              << ",\"source_observation_mode\":\"file_id_size_last_write\","
                 "\"source_unchanged_during_decode\":true,"
                 "\"source_sha256_mode\":\"off\",\"artifact_sha256_mode\":\"off\","
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
              << context.decode_and_color_wall_microseconds
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
              << context.develop_wall_microseconds
              << "},\"output_convert_encode_verify_publish\":{"
                 "\"wall_microseconds\":"
              << context.output_wall_microseconds
              << "}},\"total_wall_microseconds\":"
              << context.total_wall_microseconds << "}\n";
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
              << negaflow::imaging::negative_film_type_name(context.parameters.film_type)
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
              << negaflow::imaging::negative_film_type_name(context.parameters.film_type)
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
    if (argument_count != 8) {
        return print_error("invalid_argument_count");
    }
    if (format != DevelopedExportFormat::png16 &&
        format != DevelopedExportFormat::tiff16) {
        return print_error("unknown_export_format");
    }

    negaflow::imaging::ManualNegativeDevelopParameters parameters{};
    for (std::size_t channel = 0U; channel < parameters.dmin.size(); ++channel) {
        if (!parse_finite_float(arguments[channel + 4U], parameters.dmin[channel])) {
            return print_error("invalid_dmin");
        }
    }
    const std::wstring_view film_type{arguments[7]};
    if (film_type == L"color") {
        parameters.film_type = negaflow::imaging::NegativeFilmType::color;
    } else if (film_type == L"bw") {
        parameters.film_type = negaflow::imaging::NegativeFilmType::black_and_white;
    } else {
        return print_error("unknown_film_type");
    }

    const std::filesystem::path source{arguments[2]};
    const std::filesystem::path destination{arguments[3]};
    const Clock::time_point total_started = Clock::now();
    const negaflow::imageio::ImageFileObservationResult before =
        negaflow::imageio::observe_image_file(source);
    if (before.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return print_observation_error(before);
    }

    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = rows_per_copy;
    const Clock::time_point decode_started = Clock::now();
    auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        source,
        {},
        {},
        decode_control);
    const Clock::time_point decode_finished = Clock::now();
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

    const Clock::time_point develop_started = Clock::now();
    auto developed = negaflow::imaging::develop_manual_negative(
        std::move(prepared.working.image),
        parameters);
    const Clock::time_point develop_finished = Clock::now();
    if (developed.status != negaflow::imaging::ManualNegativeDevelopStatus::ok) {
        if (developed.status == negaflow::imaging::ManualNegativeDevelopStatus::kernel_failed) {
            return print_error(negaflow::core::kernel_status_name(developed.info.kernel_status));
        }
        return print_error(
            negaflow::imaging::manual_negative_develop_status_name(developed.status));
    }

    const Clock::time_point output_started = Clock::now();
    if (format == DevelopedExportFormat::png16) {
        const negaflow::output::WicPngExportResult exported =
            negaflow::output::export_working_to_srgb16_png(developed.image, destination);
        const Clock::time_point output_finished = Clock::now();
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
            parameters,
            prepared,
            developed,
            before.observation.file_bytes,
            elapsed_microseconds(decode_started, decode_finished),
            elapsed_microseconds(develop_started, develop_finished),
            elapsed_microseconds(output_started, output_finished),
            elapsed_microseconds(total_started, output_finished),
        };
        return print_png_success(exported, context);
    }

    const negaflow::output::WicTiffExportResult exported =
        negaflow::output::export_working_to_srgb16_tiff(developed.image, destination);
    const Clock::time_point output_finished = Clock::now();
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
        parameters,
        prepared,
        developed,
        before.observation.file_bytes,
        elapsed_microseconds(decode_started, decode_finished),
        elapsed_microseconds(develop_started, develop_finished),
        elapsed_microseconds(output_started, output_finished),
        elapsed_microseconds(total_started, output_finished),
    };
    return print_tiff_success(exported, context);
}

}  // namespace negaflow::cli
