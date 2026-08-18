#include "negaflow/core/build_info.h"
#include "negaflow/core/negative_inversion.h"
#include "negaflow/core/tiff_probe.h"
#include "negaflow/imageio/wic_tiff_decoder.h"
#include "commands/develop_negative_tiff.h"
#include "commands/export_developed_png.h"
#include "commands/auto_base_probe.h"
#include "commands/develop_timing.h"
#include "commands/gpu_transfer_bench.h"

#include "negaflow/pipeline/stage_timing.h"
#include "commands/grain_mend_detect.h"
#include "commands/export_developed_tiff.h"
#include "commands/hash_image.h"
#include "commands/prepare_scanner_tiff.h"

#include <array>
#include <charconv>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <limits>
#include <string>
#include <string_view>
#include <system_error>

namespace {

void print_help() {
    std::cout << "Negaflow Windows foundation CLI\n"
                 "\n"
                 "Usage:\n"
                 "  negaflow-cli --build-info\n"
                 "  negaflow-cli --negative-invert <transmission> <dmin> <dmax> <color|bw>\n"
                 "  negaflow-cli --probe-tiff <path>\n"
                 "  negaflow-cli --decode-tiff-wic <path>\n"
                 "  negaflow-cli --prepare-scanner-tiff <path>\n"
                 "  negaflow-cli --develop-negative-tiff <path> <dmin-r> <dmin-g> <dmin-b> <color|bw> [<exposure> <contrast> <curve-highlights> <curve-lights> <curve-darks> <curve-shadows>] [<film_scan> <film-emulation> <film-look-intensity>]\n"
                 "  negaflow-cli --export-developed-png16 <source> <destination> <dmin-r> <dmin-g> <dmin-b> <color|bw> [<exposure> <contrast> <curve-highlights> <curve-lights> <curve-darks> <curve-shadows>] [<film_scan> <film-emulation> <film-look-intensity>]\n"
                 "  negaflow-cli --export-developed-tiff16 <source> <destination> <dmin-r> <dmin-g> <dmin-b> <color|bw> [<exposure> <contrast> <curve-highlights> <curve-lights> <curve-darks> <curve-shadows>] [<film_scan> <film-emulation> <film-look-intensity>]\n"
                 "  negaflow-cli --auto-base-probe <source> [color|bw]\n"
                 "  negaflow-cli --sha256-image <path>\n"
                 "  negaflow-cli --help\n";
}

[[nodiscard]] bool parse_finite_float(const std::wstring_view text, float& value) noexcept {
    if (text.empty() || text.size() > 127U) {
        return false;
    }
    std::array<char, 128> ascii{};
    for (std::size_t index = 0; index < text.size(); ++index) {
        if (text[index] < 0 || text[index] > 127) {
            return false;
        }
        ascii[index] = static_cast<char>(text[index]);
    }
    const auto [end, error] =
        std::from_chars(ascii.data(), ascii.data() + text.size(), value, std::chars_format::general);
    return error == std::errc{} && end == ascii.data() + text.size() && std::isfinite(value);
}

int print_error(const std::string_view code) {
    std::cerr << "{\"schema_version\":1,\"status\":\"error\","
                 "\"error\":{\"code\":\""
              << code << "\"}}\n";
    return 2;
}

int run_negative_invert(const int argument_count, const wchar_t* const arguments[]) {
    if (argument_count != 6) {
        return print_error("invalid_argument_count");
    }

    float transmission = 0.0F;
    float dmin = 0.0F;
    float dmax = 0.0F;
    if (!parse_finite_float(arguments[2], transmission) ||
        !parse_finite_float(arguments[3], dmin) ||
        !parse_finite_float(arguments[4], dmax)) {
        return print_error("invalid_numeric_argument");
    }

    const std::wstring_view response_name{arguments[5]};
    negaflow::core::PrintResponse response{};
    const char* response_json_name = nullptr;
    if (response_name == L"color") {
        response = negaflow::core::color_negative_print_response();
        response_json_name = "color";
    } else if (response_name == L"bw") {
        response = negaflow::core::black_and_white_negative_print_response();
        response_json_name = "bw";
    } else {
        return print_error("unknown_print_response");
    }

    const negaflow::core::Rgba32F source{transmission, transmission, transmission, 1.0F};
    negaflow::core::Rgba32F output{};
    const negaflow::core::ConstImageView input_view{&source, 1U, 1U, 1U, 1U};
    const negaflow::core::ImageView output_view{&output, 1U, 1U, 1U, 1U};
    const negaflow::core::NegativeInversionParameters parameters{
        {dmin, dmin, dmin},
        {dmax, dmax, dmax},
    };
    const negaflow::core::KernelStatus status = negaflow::core::apply_negative_inversion(
        input_view,
        output_view,
        parameters,
        response);
    if (status != negaflow::core::KernelStatus::ok) {
        return print_error(negaflow::core::kernel_status_name(status));
    }

    std::cout << "{\"schema_version\":1,\"status\":\"ok\","
                 "\"operation\":\"negative_invert\",\"algorithm_version\":\""
              << negaflow::core::negative_inversion_algorithm_version
              << "\",\"response\":\"" << response_json_name << "\",\"value\":"
              << std::setprecision(std::numeric_limits<float>::max_digits10) << output.red
              << "}\n";
    return 0;
}

void print_short_array(
    const std::array<std::uint16_t, 8>& values,
    const std::uint8_t count) {
    std::cout << '[';
    for (std::uint8_t index = 0; index < count; ++index) {
        if (index != 0U) {
            std::cout << ',';
        }
        std::cout << values[index];
    }
    std::cout << ']';
}

int run_tiff_probe(const int argument_count, const wchar_t* const arguments[]) {
    if (argument_count != 3) {
        return print_error("invalid_argument_count");
    }

    const negaflow::core::TiffProbeResult result =
        negaflow::core::probe_tiff_file(std::filesystem::path{arguments[2]});
    if (result.status != negaflow::core::TiffProbeStatus::ok) {
        return print_error(negaflow::core::tiff_probe_status_name(result.status));
    }

    const auto& info = result.info;
    std::cout << "{\"schema_version\":1,\"status\":\"ok\","
                 "\"operation\":\"probe_tiff\",\"container\":\""
              << negaflow::core::tiff_variant_name(info.variant)
              << "\",\"byte_order\":\""
              << negaflow::core::tiff_byte_order_name(info.byte_order)
              << "\",\"organization\":\""
              << negaflow::core::tiff_organization_name(info.organization)
              << "\",\"file_bytes\":" << info.file_bytes
              << ",\"first_ifd_offset\":" << info.first_ifd_offset
              << ",\"ifd_entry_count\":" << info.ifd_entry_count
              << ",\"width\":" << info.width << ",\"height\":" << info.height
              << ",\"samples_per_pixel\":" << info.samples_per_pixel
              << ",\"bits_per_sample\":";
    print_short_array(info.bits_per_sample, info.bits_per_sample_count);
    std::cout << ",\"sample_format\":";
    print_short_array(info.sample_format, info.sample_format_count);
    std::cout << ",\"extra_samples\":";
    print_short_array(info.extra_samples, info.extra_samples_count);
    std::cout << ",\"compression\":" << info.compression
              << ",\"photometric_interpretation\":" << info.photometric_interpretation
              << ",\"planar_configuration\":" << info.planar_configuration
              << ",\"orientation\":" << info.orientation
              << ",\"segment_count\":" << info.segment_count
              << ",\"compressed_segment_bytes\":" << info.compressed_segment_bytes
              << ",\"icc_profile_bytes\":" << info.icc_profile_bytes
              << ",\"packed_raster_bytes\":" << info.packed_raster_bytes
              << ",\"working_rgba32f_bytes\":" << info.working_rgba32f_bytes << "}\n";
    return 0;
}

int run_wic_tiff_decode(const int argument_count, const wchar_t* const arguments[]) {
    if (argument_count != 3) {
        return print_error("invalid_argument_count");
    }

    const negaflow::imageio::WicTiffDecodeResult result =
        negaflow::imageio::decode_tiff_with_wic(std::filesystem::path{arguments[2]});
    if (result.status != negaflow::imageio::WicTiffDecodeStatus::ok) {
        return print_error(negaflow::imageio::wic_tiff_decode_status_name(result.status));
    }

    const std::uint8_t channels = negaflow::imageio::channel_count(result.image.layout);
    std::array<std::uint16_t, 4> minimum{
        std::numeric_limits<std::uint16_t>::max(),
        std::numeric_limits<std::uint16_t>::max(),
        std::numeric_limits<std::uint16_t>::max(),
        std::numeric_limits<std::uint16_t>::max(),
    };
    std::array<std::uint16_t, 4> maximum{};
    std::uint64_t fingerprint = 14'695'981'039'346'656'037ULL;
    for (std::size_t index = 0U; index < result.image.samples.size(); ++index) {
        const std::uint16_t sample = result.image.samples[index];
        const std::size_t channel = index % channels;
        minimum[channel] = std::min(minimum[channel], sample);
        maximum[channel] = std::max(maximum[channel], sample);
        fingerprint ^= static_cast<std::uint8_t>(sample & 0xffU);
        fingerprint *= 1'099'511'628'211ULL;
        fingerprint ^= static_cast<std::uint8_t>((sample >> 8U) & 0xffU);
        fingerprint *= 1'099'511'628'211ULL;
    }

    std::cout << "{\"schema_version\":1,\"status\":\"ok\","
                 "\"operation\":\"decode_tiff_wic\",\"decoder\":\"microsoft_builtin_wic_tiff\","
                 "\"width\":"
              << result.image.width << ",\"height\":" << result.image.height
              << ",\"layout\":\""
              << negaflow::imageio::decoded_pixel_layout_name(result.image.layout)
              << "\",\"alpha_mode\":\""
              << negaflow::imageio::alpha_mode_name(result.image.alpha_mode)
              << "\",\"source_pixel_format\":\""
              << negaflow::imageio::wic_pixel_format_name(result.info.source_pixel_format)
              << "\",\"output_pixel_format\":\""
              << negaflow::imageio::wic_pixel_format_name(result.info.output_pixel_format)
              << "\",\"format_conversion_used\":"
              << (result.info.format_conversion_used ? "true" : "false")
              << ",\"decoded_pixel_bytes\":" << result.info.decoded_pixel_bytes
              << ",\"compressed_segment_bytes\":"
              << result.info.compressed_segment_bytes
              << ",\"lzw_code_streams_validated\":"
              << (result.info.lzw_code_streams_validated ? "true" : "false")
              << ",\"deflate_streams_validated\":"
              << (result.info.deflate_streams_validated ? "true" : "false")
              << ",\"compressed_bytes_validated\":"
              << result.info.compressed_bytes_validated
              << ",\"lzw_code_count\":" << result.info.lzw_code_count
              << ",\"lzw_decoded_bytes_validated\":"
              << result.info.lzw_decoded_bytes_validated
              << ",\"deflate_decoded_bytes_validated\":"
              << result.info.deflate_decoded_bytes_validated
              << ",\"icc_profile_bytes\":" << result.image.icc_profile.size()
              << ",\"icc_status\":\""
              << negaflow::color::icc_profile_status_name(result.icc_status) << '\"';
    if (result.icc_status == negaflow::color::IccProfileStatus::ok) {
        const auto device_class =
            negaflow::color::icc_fourcc_string(result.info.icc.device_class);
        const auto data_color_space =
            negaflow::color::icc_fourcc_string(result.info.icc.data_color_space);
        const auto pcs = negaflow::color::icc_fourcc_string(result.info.icc.pcs);
        std::cout << ",\"icc_device_class\":\"" << device_class.data()
                  << "\",\"icc_data_color_space\":\"" << data_color_space.data()
                  << "\",\"icc_pcs\":\"" << pcs.data() << '\"';
    }
    std::cout << ",\"color_transform\":\"not_applied\",\"channel_min\":[";
    for (std::uint8_t channel = 0U; channel < channels; ++channel) {
        if (channel != 0U) {
            std::cout << ',';
        }
        std::cout << minimum[channel];
    }
    std::cout << "],\"channel_max\":[";
    for (std::uint8_t channel = 0U; channel < channels; ++channel) {
        if (channel != 0U) {
            std::cout << ',';
        }
        std::cout << maximum[channel];
    }
    std::cout << "],\"pixel_fingerprint_algorithm\":"
                 "\"fnv1a64-u16-bits-le-v1\","
                 "\"pixel_fingerprint_cryptographic\":false,"
                 "\"pixel_fingerprint_fnv1a64\":\""
              << std::hex << std::setw(16)
              << std::setfill('0') << fingerprint << std::dec << "\"}\n";
    return 0;
}

}  // namespace

namespace {

// `NEGA_TIMING=1` 이면 어떤 명령이든 끝에 단계별 표를 stderr 로 찍습니다.
// 명령마다 따로 붙이지 않는 이유는 **재는 자리를 빠뜨리지 않기 위해서**입니다.
struct StageTimingDump final {
    ~StageTimingDump() {
        if (negaflow::pipeline::stage_timing_enabled()) {
            negaflow::pipeline::dump_stage_timings();
        }
    }
};

}  // namespace

int wmain(const int argument_count, const wchar_t* const arguments[]) {
    const StageTimingDump timing_dump{};

    if (argument_count == 1) {
        std::cout << negaflow::core::build_info_json() << '\n';
        return 0;
    }

    const std::wstring_view command{arguments[1]};
    if (command == L"--build-info") {
        std::cout << negaflow::core::build_info_json() << '\n';
        return 0;
    }
    if (command == L"--negative-invert") {
        return run_negative_invert(argument_count, arguments);
    }
    if (command == L"--probe-tiff") {
        return run_tiff_probe(argument_count, arguments);
    }
    if (command == L"--decode-tiff-wic") {
        return run_wic_tiff_decode(argument_count, arguments);
    }
    if (command == L"--prepare-scanner-tiff") {
        return negaflow::cli::run_prepare_scanner_tiff(argument_count, arguments);
    }
    if (command == L"--develop-negative-tiff") {
        return negaflow::cli::run_develop_negative_tiff(argument_count, arguments);
    }
    if (command == L"--export-developed-png16") {
        return negaflow::cli::run_export_developed_png(argument_count, arguments);
    }
    if (command == L"--export-developed-tiff16") {
        return negaflow::cli::run_export_developed_tiff(argument_count, arguments);
    }
    if (command == L"--develop-timing") {
        return negaflow::cli::run_develop_timing(argument_count, arguments);
    }
    if (command == L"--gpu-transfer-bench") {
        return negaflow::cli::run_gpu_transfer_bench(argument_count, arguments);
    }
    if (command == L"--auto-base-probe") {
        return negaflow::cli::run_auto_base_probe(argument_count, arguments);
    }
    if (command == L"--grain-mend-detect") {
        return negaflow::cli::run_grain_mend_detect(argument_count, arguments);
    }
    if (command == L"--sha256-image") {
        return negaflow::cli::run_hash_image(argument_count, arguments);
    }
    if (command == L"--help" || command == L"-h") {
        print_help();
        return 0;
    }

    return print_error("unknown_argument");
}
