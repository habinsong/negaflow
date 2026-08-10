#include "prepare_scanner_tiff.h"

#include "working_image_report.h"

#include "negaflow/imaging/scanner_tiff_to_working.h"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <string_view>

namespace negaflow::cli {
namespace {

int print_error(const std::string_view code, const std::uint32_t native_error_code = 0U) {
    std::cerr << "{\"schema_version\":1,\"status\":\"error\","
                 "\"error\":{\"code\":\""
              << code << '"';
    if (native_error_code != 0U) {
        std::cerr << ",\"native_error_code\":\"0x" << std::hex << std::setw(8)
                  << std::setfill('0') << native_error_code << std::dec << '"';
    }
    std::cerr << "}}\n";
    return 2;
}

}  // namespace

int run_prepare_scanner_tiff(
    const int argument_count,
    const wchar_t* const arguments[]) {
    if (argument_count != 3) {
        return print_error("invalid_argument_count");
    }

    constexpr std::uint32_t rows_per_copy = 64U;
    negaflow::imageio::WicTiffDecodeControl control{};
    control.rows_per_copy = rows_per_copy;
    const auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        std::filesystem::path{arguments[2]},
        {},
        {},
        control);
    if (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok) {
        if (prepared.decode.status ==
                negaflow::imageio::WicTiffDecodeStatus::row_sink_failed &&
            prepared.working.status !=
                negaflow::imaging::ScannerToWorkingStatus::invalid_argument) {
            return print_error(
                negaflow::imaging::scanner_to_working_status_name(
                    prepared.working.status),
                prepared.working.info.native_error_code);
        }
        return print_error(
            negaflow::imageio::wic_tiff_decode_status_name(prepared.decode.status));
    }
    const auto& working = prepared.working;
    if (working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
        return print_error(
            negaflow::imaging::scanner_to_working_status_name(working.status),
            working.info.native_error_code);
    }

    const WorkingImageStatistics statistics =
        compute_working_image_statistics(working.image);
    if (!statistics.valid) {
        return print_error("invalid_working_image_layout");
    }

    std::cout << "{\"schema_version\":1,\"status\":\"ok\","
                 "\"operation\":\"prepare_scanner_tiff\",\"working_space\":"
                 "\"extended_linear_srgb_rgba_f32\",\"transform\":\""
              << negaflow::imaging::scanner_working_transform_name(working.info.transform)
              << "\",\"width\":" << working.image.width
              << ",\"height\":" << working.image.height
              << ",\"working_pixel_bytes\":"
              << working.image.pixels.size() * sizeof(negaflow::core::Rgba32F)
              << ",\"icc_profile_bytes\":"
              << prepared.decode.image.icc_profile.size()
              << ",\"intermediate_bits_per_color_channel\":"
              << static_cast<unsigned int>(working.info.intermediate_bits_per_color_channel)
              << ",\"decode_mode\":\"row_streaming\",\"rows_per_copy\":"
              << rows_per_copy << ",\"peak_decode_copy_bytes\":"
              << prepared.decode.info.peak_copy_pixel_bytes
              << ",\"decode_copy_operations\":"
              << prepared.decode.info.copy_operation_count
              << ",\"compressed_segment_bytes\":"
              << prepared.decode.info.compressed_segment_bytes
              << ",\"lzw_code_streams_validated\":"
              << (prepared.decode.info.lzw_code_streams_validated ? "true" : "false")
              << ",\"deflate_streams_validated\":"
              << (prepared.decode.info.deflate_streams_validated ? "true" : "false")
              << ",\"compressed_bytes_validated\":"
              << prepared.decode.info.compressed_bytes_validated
              << ",\"lzw_code_count\":" << prepared.decode.info.lzw_code_count
              << ",\"lzw_decoded_bytes_validated\":"
              << prepared.decode.info.lzw_decoded_bytes_validated
              << ",\"deflate_decoded_bytes_validated\":"
              << prepared.decode.info.deflate_decoded_bytes_validated
              << ",\"peak_conversion_temporary_bytes\":"
              << prepared.info.peak_conversion_temporary_pixel_bytes
              << ",\"pixel_fingerprint_algorithm\":\""
              << working_pixel_fingerprint_algorithm_version
              << "\",\"pixel_fingerprint_cryptographic\":false,"
                 "\"channel_min\":["
              << std::setprecision(9) << statistics.minimum[0] << ','
              << statistics.minimum[1] << ',' << statistics.minimum[2] << ','
              << statistics.minimum[3] << "],\"channel_max\":["
              << statistics.maximum[0] << ',' << statistics.maximum[1] << ','
              << statistics.maximum[2] << ',' << statistics.maximum[3]
              << "],\"pixel_fingerprint_fnv1a64\":\"" << std::hex << std::setw(16)
              << std::setfill('0') << statistics.fingerprint_fnv1a64 << std::dec
              << "\"}\n";
    return 0;
}

}  // namespace negaflow::cli
