#include "develop_negative_tiff.h"

#include "working_image_report.h"

#include "negaflow/core/negative_inversion.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"

#include <array>
#include <charconv>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <string_view>
#include <system_error>
#include <utility>

namespace negaflow::cli {
namespace {

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

int print_error(
    const std::string_view code,
    const std::uint32_t native_error_code = 0U) {
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

int run_develop_negative_tiff(
    const int argument_count,
    const wchar_t* const arguments[]) {
    if (argument_count != 7) {
        return print_error("invalid_argument_count");
    }

    negaflow::imaging::ManualNegativeDevelopParameters parameters{};
    for (std::size_t channel = 0U; channel < parameters.dmin.size(); ++channel) {
        if (!parse_finite_float(arguments[channel + 3U], parameters.dmin[channel])) {
            return print_error("invalid_dmin");
        }
    }
    const std::wstring_view film_type{arguments[6]};
    if (film_type == L"color") {
        parameters.film_type = negaflow::imaging::NegativeFilmType::color;
    } else if (film_type == L"bw") {
        parameters.film_type = negaflow::imaging::NegativeFilmType::black_and_white;
    } else {
        return print_error("unknown_film_type");
    }

    constexpr std::uint32_t rows_per_copy = 64U;
    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = rows_per_copy;
    auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        std::filesystem::path{arguments[2]},
        {},
        {},
        decode_control);
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

    auto developed = negaflow::imaging::develop_manual_negative(
        std::move(prepared.working.image),
        parameters);
    if (developed.status != negaflow::imaging::ManualNegativeDevelopStatus::ok) {
        if (developed.status == negaflow::imaging::ManualNegativeDevelopStatus::kernel_failed) {
            return print_error(negaflow::core::kernel_status_name(developed.info.kernel_status));
        }
        return print_error(
            negaflow::imaging::manual_negative_develop_status_name(developed.status));
    }

    const WorkingImageStatistics statistics =
        compute_working_image_statistics(developed.image);
    std::cout << "{\"schema_version\":1,\"status\":\"ok\","
                 "\"operation\":\"develop_negative_tiff\","
                 "\"working_space\":\"extended_linear_srgb_rgba_f32\","
                 "\"algorithm_version\":\""
              << negaflow::core::negative_inversion_algorithm_version
              << "\",\"film_type\":\""
              << negaflow::imaging::negative_film_type_name(parameters.film_type)
              << "\",\"manual_dmin\":[" << developed.info.applied_dmin[0] << ','
              << developed.info.applied_dmin[1] << ',' << developed.info.applied_dmin[2]
              << "],\"dmax_normalized\":[" << developed.info.dmax_normalized[0] << ','
              << developed.info.dmax_normalized[1] << ','
              << developed.info.dmax_normalized[2] << "],\"width\":"
              << developed.image.width << ",\"height\":" << developed.image.height
              << ",\"working_pixel_bytes\":"
              << developed.image.pixels.size() * sizeof(negaflow::core::Rgba32F)
              << ",\"develop_additional_full_frame_bytes\":0,\"source_sha256_mode\":\"off\","
                 "\"scanner_transform\":\""
              << negaflow::imaging::scanner_working_transform_name(prepared.working.info.transform)
              << "\",\"decode_mode\":\"row_streaming\",\"rows_per_copy\":"
              << rows_per_copy << ",\"peak_decode_copy_bytes\":"
              << prepared.decode.info.peak_copy_pixel_bytes
              << ",\"peak_conversion_temporary_bytes\":"
              << prepared.info.peak_conversion_temporary_pixel_bytes
              << ",\"channel_min\":[" << std::setprecision(9) << statistics.minimum[0]
              << ',' << statistics.minimum[1] << ',' << statistics.minimum[2] << ','
              << statistics.minimum[3] << "],\"channel_max\":["
              << statistics.maximum[0] << ',' << statistics.maximum[1] << ','
              << statistics.maximum[2] << ',' << statistics.maximum[3]
              << "],\"pixel_fingerprint_fnv1a64\":\"" << std::hex << std::setw(16)
              << std::setfill('0') << statistics.fingerprint_fnv1a64 << std::dec << "\"}\n";
    return 0;
}

}  // namespace negaflow::cli
