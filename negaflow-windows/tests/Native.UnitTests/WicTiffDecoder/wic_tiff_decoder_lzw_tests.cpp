#include "wic_tiff_decoder_test_support.h"

#include "synthetic_wic_tiff.h"

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <stop_token>
#include <string>
#include <vector>

namespace wic_tiff_decoder_tests {

void test_valid_lzw(const std::filesystem::path& root) {
    const std::filesystem::path path = root / L"valid-lzw-rgb16.tiff";
    write_fixture(path, negaflow::test_fixtures::make_lzw_rgb16_tiff());

    const auto result = negaflow::imageio::decode_tiff_with_wic(path);
    expect(result.status == negaflow::imageio::WicTiffDecodeStatus::ok, "valid LZW decodes");
    expect(
        result.preflight_status == negaflow::core::TiffProbeStatus::ok,
        "valid LZW passes preflight");
    expect(
        result.image.width == 1U && result.image.height == 1U,
        "valid LZW dimensions match");
    expect(
        result.image.layout == negaflow::imageio::DecodedPixelLayout::rgb16,
        "valid LZW layout is RGB16");
    expect(
        result.image.samples.size() ==
                negaflow::test_fixtures::lzw_rgb16_expected_samples.size() &&
            std::equal(
                result.image.samples.begin(),
                result.image.samples.end(),
                negaflow::test_fixtures::lzw_rgb16_expected_samples.begin()),
        "valid LZW samples match");
    expect(
        result.info.lzw_code_streams_validated &&
            result.info.compressed_segment_bytes == 9U &&
            result.info.compressed_bytes_validated == 9U &&
            result.info.lzw_code_count == 8U &&
            result.info.lzw_decoded_bytes_validated == 6U,
        "valid LZW code stream is fully accounted before WIC decode");
}

void test_gray16_companion(const std::filesystem::path& root) {
    const std::filesystem::path path = root / L"infrared-gray16.tiff";
    write_fixture(path, negaflow::test_fixtures::make_uncompressed_gray16_tiff(9U, 7U));
    const auto result = negaflow::imageio::decode_tiff_with_wic(path);
    expect(
        result.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            result.image.width == 9U && result.image.height == 7U &&
            result.image.layout == negaflow::imageio::DecodedPixelLayout::gray16 &&
            result.image.stride_bytes == 18U && result.image.samples.size() == 63U &&
            result.info.output_pixel_format == negaflow::imageio::WicPixelFormat::gray16,
        "Gray16 infrared companion TIFF decodes without RGB expansion");
}

// An 8-bit scan has to open, and it has to widen exactly. WIC replicates the byte
// (v * 257), which is the same number as v / 255 once the working conversion divides by
// 65535 — so the file loses no accuracy on the way in. Any other widening rule (a left
// shift, say) would darken every sample by up to one part in 256 and would show up here.
void test_eight_bit_widens_by_bit_replication(const std::filesystem::path& root) {
    constexpr std::uint32_t width = 7U;
    constexpr std::uint32_t height = 5U;
    const std::filesystem::path path = root / L"uncompressed-rgb8.tiff";
    const std::vector<std::uint8_t> bytes =
        negaflow::test_fixtures::make_uncompressed_rgb8_tiff(width, height);
    write_fixture(path, bytes);

    const auto result = negaflow::imageio::decode_tiff_with_wic(path);
    expect(
        result.status == negaflow::imageio::WicTiffDecodeStatus::ok,
        "an 8-bit RGB TIFF decodes");
    expect(
        result.image.layout == negaflow::imageio::DecodedPixelLayout::rgb16 &&
            result.info.format_conversion_used,
        "8-bit input is widened to the 16-bit working layout");
    expect(
        result.image.width == width && result.image.height == height,
        "8-bit dimensions match");

    bool replicated = result.image.samples.size() ==
                      static_cast<std::size_t>(width) * height * 3U;
    for (std::uint32_t y = 0U; replicated && y < height; ++y) {
        for (std::uint32_t x = 0U; replicated && x < width; ++x) {
            const std::size_t index =
                ((static_cast<std::size_t>(y) * width) + x) * 3U;
            const std::uint16_t expected_red =
                static_cast<std::uint16_t>(((x * 251U) % 256U) * 257U);
            const std::uint16_t expected_green =
                static_cast<std::uint16_t>(((y * 149U) % 256U) * 257U);
            const std::uint16_t expected_blue =
                static_cast<std::uint16_t>((((x + y) * 97U) % 256U) * 257U);
            replicated = result.image.samples[index] == expected_red &&
                         result.image.samples[index + 1U] == expected_green &&
                         result.image.samples[index + 2U] == expected_blue;
        }
    }
    expect(replicated, "every 8-bit sample widens to exactly v * 257");
}

void test_lzw_code_width_transition(const std::filesystem::path& root) {
    constexpr std::uint32_t row_count = 300U;
    const std::filesystem::path path = root / L"code-width-transition-lzw-rgb16.tiff";
    write_fixture(
        path,
        negaflow::test_fixtures::make_lzw_code_width_transition_rgb16_tiff());

    const auto result = negaflow::imageio::decode_tiff_with_wic(path);
    expect(
        result.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            result.info.lzw_code_streams_validated,
        "TIFF early-change LZW stream decodes across all code-width boundaries");
    expect(
        result.info.lzw_code_count == 1'802U &&
            result.info.lzw_decoded_bytes_validated == row_count * 6U,
        "LZW 9-to-10, 10-to-11, and 11-to-12-bit accounting is exact");
    expect(
        result.image.samples.size() == row_count * 3U,
        "LZW width-transition output size matches all rows");
    for (std::size_t index = 0U; index < result.image.samples.size(); ++index) {
        expect(
            result.image.samples[index] ==
                negaflow::test_fixtures::lzw_rgb16_expected_samples[index % 3U],
            "LZW width-transition pixels remain exact");
    }
}

void test_lzw_dictionary_limit_and_forward_reference(
    const std::filesystem::path& root) {
    constexpr std::uint32_t row_count = 640U;
    const std::filesystem::path limit_path = root / L"dictionary-limit-lzw-rgb16.tiff";
    write_fixture(
        limit_path,
        negaflow::test_fixtures::make_lzw_dictionary_limit_rgb16_tiff());

    const auto limit = negaflow::imageio::decode_tiff_with_wic(limit_path);
    expect(
        limit.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            limit.info.lzw_code_streams_validated &&
            limit.info.lzw_code_count == 3'843U &&
            limit.info.lzw_decoded_bytes_validated == row_count * 6U,
        "LZW entry 4094 is followed by a 12-bit Clear and a 9-bit reset");
    expect(
        limit.image.samples.size() == row_count * 3U,
        "dictionary-limit LZW output contains every row");
    for (std::size_t index = 0U; index < limit.image.samples.size(); ++index) {
        expect(
            limit.image.samples[index] ==
                negaflow::test_fixtures::lzw_rgb16_expected_samples[index % 3U],
            "dictionary-limit LZW pixels remain exact");
    }

    const std::filesystem::path forward_path =
        root / L"forward-reference-lzw-rgb16.tiff";
    write_fixture(
        forward_path,
        negaflow::test_fixtures::make_lzw_forward_reference_rgb16_tiff());

    const auto forward = negaflow::imageio::decode_tiff_with_wic(forward_path);
    expect(
        forward.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            forward.info.lzw_code_streams_validated &&
            forward.info.lzw_code_count == 5U &&
            forward.info.lzw_decoded_bytes_validated == 6U,
        "standard LZW code-equals-next forward reference is accepted");
    expect(
        forward.image.samples == std::vector<std::uint16_t>(3U, 0x3434U),
        "forward-reference LZW samples remain exact");

    const std::filesystem::path fill_bits_path =
        root / L"nonzero-fill-bits-lzw-rgb16.tiff";
    write_fixture(
        fill_bits_path,
        negaflow::test_fixtures::make_nonzero_fill_bits_lzw_rgb16_tiff());
    negaflow::core::TiffProbeControl semantic_control{};
    semantic_control.validate_lzw_code_streams = true;
    const auto fill_bits =
        negaflow::core::probe_tiff_file(fill_bits_path, {}, semantic_control);
    expect(
        fill_bits.status == negaflow::core::TiffProbeStatus::ok &&
            fill_bits.info.lzw_code_streams_validated,
        "unused bits after EOI may be nonzero inside the final segment byte");
}


void test_malformed_lzw(const std::filesystem::path& root) {
    const std::filesystem::path path = root / L"malformed-lzw-rgb16.tiff";
    write_fixture(path, negaflow::test_fixtures::make_malformed_lzw_rgb16_tiff());

    const auto result = negaflow::imageio::decode_tiff_with_wic(path);
    expect(
        result.preflight_status == negaflow::core::TiffProbeStatus::tag_data_out_of_bounds,
        "truncated LZW segment fails bounded preflight");
    expect(
        result.status == negaflow::imageio::WicTiffDecodeStatus::preflight_failed,
        "truncated LZW is rejected before WIC decode");
    expect(result.image.samples.empty(), "truncated LZW publishes no decoded samples");
}

void test_semantically_invalid_lzw(const std::filesystem::path& root) {
    struct InvalidFixture final {
        const wchar_t* name;
        std::vector<std::uint8_t> bytes;
    };
    std::array<InvalidFixture, 6> fixtures{
        InvalidFixture{
            L"missing-clear-lzw-rgb16.tiff",
            negaflow::test_fixtures::make_missing_clear_lzw_rgb16_tiff()},
        InvalidFixture{
            L"missing-eoi-lzw-rgb16.tiff",
            negaflow::test_fixtures::make_missing_eoi_lzw_rgb16_tiff()},
        InvalidFixture{
            L"short-decoded-lzw-rgb16.tiff",
            negaflow::test_fixtures::make_short_decoded_lzw_rgb16_tiff()},
        InvalidFixture{
            L"long-decoded-lzw-rgb16.tiff",
            negaflow::test_fixtures::make_long_decoded_lzw_rgb16_tiff()},
        InvalidFixture{
            L"invalid-forward-code-lzw-rgb16.tiff",
            negaflow::test_fixtures::make_invalid_forward_code_lzw_rgb16_tiff()},
        InvalidFixture{
            L"trailing-data-lzw-rgb16.tiff",
            negaflow::test_fixtures::make_trailing_data_lzw_rgb16_tiff()},
    };

    for (const InvalidFixture& fixture : fixtures) {
        const std::filesystem::path path = root / fixture.name;
        write_fixture(path, fixture.bytes);
        const auto result = negaflow::imageio::decode_tiff_with_wic(path);
        expect(
            result.preflight_status ==
                negaflow::core::TiffProbeStatus::invalid_compressed_data,
            "bounded LZW semantics reject an in-range malformed code stream");
        expect(
            result.status == negaflow::imageio::WicTiffDecodeStatus::preflight_failed,
            "semantic LZW failure occurs before WIC decode");
        expect(result.image.samples.empty(), "semantic LZW failure publishes no samples");
    }

    const std::filesystem::path valid_path = root / L"limited-lzw-rgb16.tiff";
    write_fixture(valid_path, negaflow::test_fixtures::make_lzw_rgb16_tiff());
    negaflow::imageio::WicTiffDecodeLimits limits{};
    limits.probe.max_lzw_compressed_bytes = 8U;
    const auto limited = negaflow::imageio::decode_tiff_with_wic(valid_path, limits);
    expect(
        limited.preflight_status ==
                negaflow::core::TiffProbeStatus::compressed_data_limit_exceeded &&
            limited.status == negaflow::imageio::WicTiffDecodeStatus::preflight_failed,
        "LZW compressed-input work budget fails closed before WIC decode");

    std::stop_source stop_source{};
    stop_source.request_stop();
    negaflow::core::TiffProbeControl control{};
    control.validate_lzw_code_streams = true;
    control.stop_token = stop_source.get_token();
    const auto cancelled = negaflow::core::probe_tiff_file(valid_path, {}, control);
    expect(
        cancelled.status == negaflow::core::TiffProbeStatus::cancelled,
        "LZW semantic preflight observes cancellation");
}


}  // namespace wic_tiff_decoder_tests
