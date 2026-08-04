#include "negaflow/imageio/wic_tiff_decoder.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <iostream>
#include <vector>

namespace {

[[nodiscard]] bool working_images_equal(
    const negaflow::imaging::WorkingImage& left,
    const negaflow::imaging::WorkingImage& right) noexcept {
    if (left.width != right.width || left.height != right.height ||
        left.stride_pixels != right.stride_pixels ||
        left.pixels.size() != right.pixels.size()) {
        return false;
    }
    for (std::size_t index = 0U; index < left.pixels.size(); ++index) {
        const auto& first = left.pixels[index];
        const auto& second = right.pixels[index];
        if (first.red != second.red || first.green != second.green ||
            first.blue != second.blue || first.alpha != second.alpha) {
            return false;
        }
    }
    return true;
}

[[nodiscard]] bool compare_one(
    const std::filesystem::path& path,
    std::uint64_t& peak_decode_copy_bytes,
    std::uint64_t& peak_conversion_temporary_bytes) {
    auto decoded = negaflow::imageio::decode_tiff_with_wic(path);
    if (decoded.status != negaflow::imageio::WicTiffDecodeStatus::ok) {
        return false;
    }
    const auto full = negaflow::imaging::convert_scanner_to_working(decoded.image);
    if (full.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
        return false;
    }
    const auto full_layout = decoded.image.layout;
    const auto full_alpha = decoded.image.alpha_mode;
    const auto full_icc = decoded.image.icc_profile;
    const auto full_source_format = decoded.info.source_pixel_format;
    const auto full_output_format = decoded.info.output_pixel_format;
    const bool full_format_conversion = decoded.info.format_conversion_used;
    std::vector<std::uint16_t>{}.swap(decoded.image.samples);

    negaflow::imageio::WicTiffDecodeControl control{};
    control.rows_per_copy = 64U;
    const auto streamed = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        path,
        {},
        {},
        control);
    if (streamed.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
        streamed.working.status != negaflow::imaging::ScannerToWorkingStatus::ok ||
        !streamed.decode.image.samples.empty() ||
        streamed.decode.image.layout != full_layout ||
        streamed.decode.image.alpha_mode != full_alpha ||
        streamed.decode.image.icc_profile != full_icc ||
        streamed.decode.info.source_pixel_format != full_source_format ||
        streamed.decode.info.output_pixel_format != full_output_format ||
        streamed.decode.info.format_conversion_used != full_format_conversion ||
        streamed.working.info.transform != full.info.transform ||
        streamed.working.info.intermediate_bits_per_color_channel !=
            full.info.intermediate_bits_per_color_channel ||
        !working_images_equal(streamed.working.image, full.image)) {
        return false;
    }

    peak_decode_copy_bytes =
        std::max(peak_decode_copy_bytes, streamed.decode.info.peak_copy_pixel_bytes);
    peak_conversion_temporary_bytes = std::max(
        peak_conversion_temporary_bytes,
        streamed.info.peak_conversion_temporary_pixel_bytes);
    return true;
}

}  // namespace

int wmain(const int argument_count, const wchar_t* const arguments[]) {
    if (argument_count < 2) {
        std::cerr << "expected at least one TIFF path\n";
        return 2;
    }

    std::uint32_t succeeded = 0U;
    std::uint64_t peak_decode_copy_bytes = 0U;
    std::uint64_t peak_conversion_temporary_bytes = 0U;
    for (int index = 1; index < argument_count; ++index) {
        if (!compare_one(
                std::filesystem::path{arguments[index]},
                peak_decode_copy_bytes,
                peak_conversion_temporary_bytes)) {
            std::cerr << "stream parity failed at input index " << index << '\n';
            return 1;
        }
        ++succeeded;
    }

    std::cout << "{\"schema_version\":1,\"status\":\"ok\","
                 "\"operation\":\"scanner_stream_parity\",\"file_count\":"
              << succeeded << ",\"rows_per_copy\":64,\"exact_pixels_equal\":true,"
                 "\"stream_retained_decoded_samples\":false,"
                 "\"max_peak_decode_copy_bytes\":"
              << peak_decode_copy_bytes
              << ",\"max_peak_conversion_temporary_bytes\":"
              << peak_conversion_temporary_bytes << "}\n";
    return 0;
}
