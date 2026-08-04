#include "export_developed_png.h"

#include "negaflow/core/negative_inversion.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/output/wic_png_export.h"

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
    const std::uint32_t native_error_code = 0U,
    const std::uint32_t cleanup_error_code = 0U) {
    std::cerr << "{\"schema_version\":1,\"status\":\"error\","
                 "\"error\":{\"code\":\""
              << code << '"';
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

}  // namespace

int run_export_developed_png(
    const int argument_count,
    const wchar_t* const arguments[]) {
    if (argument_count != 8) {
        return print_error("invalid_argument_count");
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

    const negaflow::output::WicPngExportResult exported =
        negaflow::output::export_working_to_srgb16_png(
            developed.image,
            std::filesystem::path{arguments[3]});
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

    std::cout << "{\"schema_version\":1,\"status\":\"ok\","
                 "\"operation\":\"export_developed_png16\","
                 "\"format\":\"png16_rgb\","
                 "\"working_space\":\"extended_linear_srgb_rgba_f32\","
                 "\"destination_space\":\"srgb\","
                 "\"encoder\":\"microsoft_builtin_wic_png\","
                 "\"algorithm_version\":\""
              << negaflow::core::negative_inversion_algorithm_version
              << "\",\"film_type\":\""
              << negaflow::imaging::negative_film_type_name(parameters.film_type)
              << "\",\"width\":" << exported.info.width
              << ",\"height\":" << exported.info.height
              << ",\"encoded_pixel_bytes\":" << exported.info.encoded_pixel_bytes
              << ",\"artifact_bytes\":" << exported.info.artifact_bytes
              << ",\"color_profile_bytes\":" << exported.info.color_profile_bytes
              << ",\"clipped_color_components\":"
              << exported.info.clipped_color_components
              << ",\"structure_verified\":true,\"pixels_verified\":true,"
                 "\"profile_verified\":true,\"published\":true,"
                 "\"publish_mode\":\"same_directory_create_new_move\","
                 "\"source_sha256_mode\":\"off\","
                 "\"artifact_sha256_mode\":\"off\"}\n";
    return 0;
}

}  // namespace negaflow::cli
