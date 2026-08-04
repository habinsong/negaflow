#include "develop_negative_tiff.h"

#include "film_look_command_support.h"
#include "working_image_report.h"

#include "negaflow/core/negative_inversion.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/imaging/working_tone_adjuster.h"

#include <array>
#include <charconv>
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

void print_working_statistics(const WorkingImageStatistics& statistics) {
    std::cout << "{\"channel_min\":[" << std::setprecision(9)
              << statistics.minimum[0] << ',' << statistics.minimum[1] << ','
              << statistics.minimum[2] << ',' << statistics.minimum[3]
              << "],\"channel_max\":[" << statistics.maximum[0] << ','
              << statistics.maximum[1] << ',' << statistics.maximum[2] << ','
              << statistics.maximum[3] << "],\"pixel_fingerprint_fnv1a64\":\""
              << std::hex << std::setw(16) << std::setfill('0')
              << statistics.fingerprint_fnv1a64 << std::dec << "\"}";
}

}  // namespace

int run_develop_negative_tiff(
    const int argument_count,
    const wchar_t* const arguments[]) {
    const bool tone_arguments_explicit =
        argument_count == 13 || argument_count == 16;
    const bool film_look_arguments_explicit =
        argument_count == 10 || argument_count == 16;
    if (argument_count != 7 && argument_count != 10 &&
        argument_count != 13 && argument_count != 16) {
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

    negaflow::imaging::WorkingToneAdjustParameters tone_parameters{};
    if (tone_arguments_explicit) {
        if (!parse_finite_float(arguments[7], tone_parameters.exposure_stops) ||
            !parse_finite_float(arguments[8], tone_parameters.basic.contrast) ||
            !parse_finite_float(arguments[9], tone_parameters.curve.highlights) ||
            !parse_finite_float(arguments[10], tone_parameters.curve.lights) ||
            !parse_finite_float(arguments[11], tone_parameters.curve.darks) ||
            !parse_finite_float(arguments[12], tone_parameters.curve.shadows) ||
            !negaflow::imaging::valid_working_tone_adjust_parameters(
                tone_parameters)) {
            return print_error("invalid_tone_adjustment_parameter");
        }
    }

    FilmLookCommandRecipe film_look_recipe{};
    if (film_look_arguments_explicit) {
        const std::size_t first_argument =
            tone_arguments_explicit ? 13U : 7U;
        const FilmLookRecipeParseStatus parse_status = parse_film_look_recipe(
            arguments[first_argument],
            arguments[first_argument + 1U],
            arguments[first_argument + 2U],
            film_look_recipe);
        if (parse_status != FilmLookRecipeParseStatus::ok) {
            return print_error(film_look_recipe_parse_status_name(parse_status));
        }
    }
    if (film_look_recipe.parameters.source_kind !=
        negaflow::imaging::DevelopSourceKind::film_scan) {
        return print_error("negative_develop_requires_film_scan_source");
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

    FilmLookCommandWorkspace film_look_workspace{};
    const FilmLookWorkspacePrepareStatus workspace_status =
        prepare_film_look_workspace(
            film_look_recipe.parameters,
            prepared.working.image.width,
            film_look_workspace);
    if (workspace_status != FilmLookWorkspacePrepareStatus::ok) {
        return print_error(
            film_look_workspace_prepare_status_name(workspace_status));
    }

    const WorkingImageStatistics prepared_statistics =
        compute_working_image_statistics(prepared.working.image);
    if (!prepared_statistics.valid) {
        return print_error("invalid_working_image_layout");
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

    const WorkingImageStatistics developed_statistics =
        compute_working_image_statistics(developed.image);
    if (!developed_statistics.valid) {
        return print_error("invalid_working_image_layout");
    }
    auto adjusted = negaflow::imaging::apply_working_tone_adjustments(
        std::move(developed.image),
        tone_parameters);
    if (adjusted.status != negaflow::imaging::WorkingToneAdjustStatus::ok) {
        if (adjusted.status ==
            negaflow::imaging::WorkingToneAdjustStatus::kernel_failed) {
            return print_error(
                negaflow::core::kernel_status_name(adjusted.info.kernel_status));
        }
        if (adjusted.status ==
            negaflow::imaging::WorkingToneAdjustStatus::measurement_failed) {
            return print_error("tone_curve_measurement_failed");
        }
        return print_error(
            negaflow::imaging::working_tone_adjust_status_name(adjusted.status));
    }
    const bool tone_pixels_changed = adjusted.info.exposure_applied ||
        adjusted.info.basic_tone_applied ||
        adjusted.info.parametric_curve_applied ||
        adjusted.info.point_curve_applied ||
        adjusted.info.color_mixer_applied ||
        adjusted.info.color_grading_applied ||
        adjusted.info.primary_calibration_applied;
    WorkingImageStatistics adjusted_statistics = developed_statistics;
    std::uint32_t statistics_full_frame_scan_count = 2U;
    if (tone_pixels_changed) {
        adjusted_statistics = compute_working_image_statistics(adjusted.image);
        statistics_full_frame_scan_count = 3U;
    }
    if (!adjusted_statistics.valid) {
        return print_error("invalid_working_image_layout");
    }

    auto film_look = negaflow::imaging::apply_working_film_look(
        std::move(adjusted.image),
        film_look_recipe.parameters,
        film_look_workspace_view(film_look_workspace));
    if (film_look.status != negaflow::imaging::WorkingFilmLookStatus::ok) {
        if (film_look.status ==
            negaflow::imaging::WorkingFilmLookStatus::kernel_failed) {
            return print_error(
                negaflow::core::kernel_status_name(
                    film_look.info.kernel_status));
        }
        return print_error(
            negaflow::imaging::working_film_look_status_name(
                film_look.status));
    }
    const bool film_look_pixels_changed = film_look.info.color_applied ||
        film_look.info.acutance_applied;
    WorkingImageStatistics film_look_statistics = adjusted_statistics;
    if (film_look_pixels_changed) {
        film_look_statistics =
            compute_working_image_statistics(film_look.image);
        ++statistics_full_frame_scan_count;
    }
    if (!film_look_statistics.valid) {
        return print_error("invalid_working_image_layout");
    }

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
              << film_look.image.width << ",\"height\":"
              << film_look.image.height
              << ",\"working_pixel_bytes\":"
              << film_look.image.pixels.size() *
                     sizeof(negaflow::core::Rgba32F)
              << ",\"develop_additional_full_frame_bytes\":0,\"source_sha256_mode\":\"off\","
                 "\"scanner_transform\":\""
              << negaflow::imaging::scanner_working_transform_name(prepared.working.info.transform)
              << "\",\"decode_mode\":\"row_streaming\",\"rows_per_copy\":"
              << rows_per_copy << ",\"peak_decode_copy_bytes\":"
              << prepared.decode.info.peak_copy_pixel_bytes
              << ",\"peak_conversion_temporary_bytes\":"
              << prepared.info.peak_conversion_temporary_pixel_bytes
              << ",\"tone_algorithm_version\":\""
              << negaflow::imaging::tone_mapping_algorithm_version
              << "\",\"point_curve_algorithm_version\":\""
              << negaflow::imaging::point_curve_algorithm_version
              << "\",\"point_curve_applied\":"
              << (adjusted.info.point_curve_applied ? "true" : "false")
              << ",\"color_mixer_algorithm_version\":\""
              << negaflow::imaging::color_mixer_algorithm_version
              << "\",\"color_mixer_applied\":"
              << (adjusted.info.color_mixer_applied ? "true" : "false")
              << ",\"color_grading_algorithm_version\":\""
              << negaflow::imaging::color_grading_algorithm_version
              << "\",\"color_grading_applied\":"
              << (adjusted.info.color_grading_applied ? "true" : "false")
              << ",\"calibration_algorithm_version\":\""
              << negaflow::imaging::primary_calibration_algorithm_version
              << "\",\"calibration_applied\":"
              << (adjusted.info.primary_calibration_applied ? "true" : "false")
              << ",\"film_look_algorithm_version\":\""
              << negaflow::imaging::working_film_look_algorithm_version
              << "\",\"film_look_arguments_explicit\":"
              << (film_look_recipe.arguments_explicit ? "true" : "false")
              << ",\"source_kind\":\""
              << negaflow::imaging::develop_source_kind_name(
                     film_look_recipe.parameters.source_kind)
              << "\",\"film_emulation\":\""
              << film_emulation_recipe_name(
                     film_look_recipe.parameters.emulation)
              << "\",\"film_emulation_intensity\":"
              << std::setprecision(std::numeric_limits<double>::max_digits10)
              << film_look_recipe.parameters.intensity
              << ",\"film_look_route\":\""
              << negaflow::imaging::film_look_route_name(film_look.info.route)
              << "\",\"film_color_algorithm_version\":\""
              << negaflow::imaging::film_emulation_color_algorithm_version
              << "\",\"film_acutance_algorithm_version\":\""
              << negaflow::imaging::film_emulation_acutance_algorithm_version
              << "\",\"film_color_intensity_step\":"
              << film_look.info.color_intensity_step
              << ",\"film_acutance_amount\":"
              << film_look.info.acutance_amount
              << ",\"film_color_cube_built\":"
              << (film_look.info.color_cube_built ? "true" : "false")
              << ",\"film_color_cube_reused\":"
              << (film_look.info.color_cube_reused ? "true" : "false")
              << ",\"film_color_applied\":"
              << (film_look.info.color_applied ? "true" : "false")
              << ",\"film_acutance_applied\":"
              << (film_look.info.acutance_applied ? "true" : "false")
              << ",\"film_look_workspace_bytes\":"
              << film_look_workspace_bytes(film_look_workspace)
              << ",\"tone_arguments_explicit\":"
              << (tone_arguments_explicit ? "true" : "false")
              << ",\"pixel_fingerprint_algorithm\":\""
              << working_pixel_fingerprint_algorithm_version
              << "\",\"pixel_fingerprint_cryptographic\":false,"
                 "\"statistics_full_frame_scan_count\":"
              << statistics_full_frame_scan_count
              << ",\"statistics_additional_full_frame_bytes\":0,"
                 "\"stage_statistics\":{\"scanner_to_working\":";
    print_working_statistics(prepared_statistics);
    std::cout << ",\"develop\":";
    print_working_statistics(developed_statistics);
    std::cout << ",\"tone_adjust\":";
    print_working_statistics(adjusted_statistics);
    std::cout << ",\"film_look\":";
    print_working_statistics(film_look_statistics);
    std::cout << "},\"channel_min\":[" << std::setprecision(9)
              << film_look_statistics.minimum[0] << ','
              << film_look_statistics.minimum[1] << ','
              << film_look_statistics.minimum[2] << ','
              << film_look_statistics.minimum[3] << "],\"channel_max\":["
              << film_look_statistics.maximum[0] << ','
              << film_look_statistics.maximum[1] << ','
              << film_look_statistics.maximum[2] << ','
              << film_look_statistics.maximum[3]
              << "],\"pixel_fingerprint_fnv1a64\":\"" << std::hex
              << std::setw(16) << std::setfill('0')
              << film_look_statistics.fingerprint_fnv1a64 << std::dec
              << "\"}\n";
    return 0;
}

}  // namespace negaflow::cli
