#include "wic_tiff_decoder_test_support.h"

#include "synthetic_wic_tiff.h"

#include "negaflow/core/parallel_rows.h"

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

void test_row_copy_progress_and_cancellation(const std::filesystem::path& root) {
    const std::filesystem::path path = root / L"row-copy-lzw-rgb16.tiff";
    write_fixture(path, negaflow::test_fixtures::make_lzw_rgb16_rows_tiff(5U));

    RecordingProgress progress{};
    negaflow::imageio::WicTiffDecodeControl control{};
    control.rows_per_copy = 2U;
    control.progress_observer = &progress;
    const auto chunked = negaflow::imageio::decode_tiff_with_wic(path, {}, control);
    const auto whole = negaflow::imageio::decode_tiff_with_wic(path);
    expect(chunked.status == negaflow::imageio::WicTiffDecodeStatus::ok, "row copies decode");
    expect(whole.status == negaflow::imageio::WicTiffDecodeStatus::ok, "whole copy decodes");
    expect(chunked.image.samples == whole.image.samples, "row copies match whole-frame samples");
    expect(
        chunked.info.copy_operation_count == 3U && chunked.info.completed_rows == 5U &&
            chunked.info.peak_copy_pixel_bytes == 12U,
        "row copy accounting is exact");
    expect(
        whole.info.copy_operation_count == 1U && whole.info.completed_rows == 5U,
        "default decode preserves one whole-frame copy");
    expect(
        progress.event_count() == 4U && progress.event(0U).completed_rows == 0U &&
            progress.event(1U).completed_rows == 2U &&
            progress.event(2U).completed_rows == 4U &&
            progress.event(3U).completed_rows == 5U &&
            progress.event(3U).total_rows == 5U,
        "row progress is monotonic and reaches the total");

    CollectingRowSink streaming_sink{};
    const auto streamed = negaflow::imageio::decode_tiff_rows_with_wic(
        path,
        streaming_sink,
        {},
        control);
    expect(
        streamed.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            streamed.image.samples.empty(),
        "streaming row decode retains no full decoded sample buffer");
    expect(
        streaming_sink.committed() && streaming_sink.terminal_count() == 1U &&
            streaming_sink.terminal_status() == negaflow::imageio::WicTiffDecodeStatus::ok &&
            streaming_sink.samples() == whole.image.samples &&
            streaming_sink.icc_profile() == whole.image.icc_profile,
        "streaming sink commits exact samples and ICC once");

    CollectingRowSink rejecting_sink{true};
    const auto rejected = negaflow::imageio::decode_tiff_rows_with_wic(
        path,
        rejecting_sink,
        {},
        control);
    expect(
        rejected.status == negaflow::imageio::WicTiffDecodeStatus::row_sink_failed &&
            rejected.info.copy_operation_count == 1U &&
            rejected.info.completed_rows == 0U && rejected.image.samples.empty() &&
            rejecting_sink.samples().empty(),
        "row sink rejection publishes no samples or completed rows");
    expect(
        rejecting_sink.terminal_count() == 1U &&
            rejecting_sink.terminal_status() ==
                negaflow::imageio::WicTiffDecodeStatus::row_sink_failed,
        "row sink rejection receives one terminal failure");

    std::stop_source stop_source{};
    RecordingProgress cancelling_progress{&stop_source, 1U};
    control.rows_per_copy = 1U;
    control.stop_token = stop_source.get_token();
    control.progress_observer = &cancelling_progress;
    const auto cancelled = negaflow::imageio::decode_tiff_with_wic(path, {}, control);
    expect(
        cancelled.status == negaflow::imageio::WicTiffDecodeStatus::cancelled,
        "cancellation is observed between row copies");
    expect(
        cancelled.info.copy_operation_count == 1U && cancelled.info.completed_rows == 1U,
        "cancelled decode reports only completed rows");
    expect(cancelled.image.samples.empty(), "cancelled decode publishes no samples");

    std::stop_source streaming_stop_source{};
    RecordingProgress streaming_cancel_progress{&streaming_stop_source, 1U};
    CollectingRowSink cancelled_streaming_sink{};
    control.stop_token = streaming_stop_source.get_token();
    control.progress_observer = &streaming_cancel_progress;
    const auto cancelled_stream = negaflow::imageio::decode_tiff_rows_with_wic(
        path,
        cancelled_streaming_sink,
        {},
        control);
    expect(
        cancelled_stream.status == negaflow::imageio::WicTiffDecodeStatus::cancelled &&
            cancelled_stream.image.samples.empty() &&
            cancelled_streaming_sink.samples().empty(),
        "cancelled streaming decode discards engine and sink samples");
    expect(
        cancelled_streaming_sink.terminal_count() == 1U &&
            cancelled_streaming_sink.terminal_status() ==
                negaflow::imageio::WicTiffDecodeStatus::cancelled &&
            !cancelled_streaming_sink.committed(),
        "cancelled streaming sink receives one terminal result");
}


void test_deflate_preflight(const std::filesystem::path& root) {
    const std::filesystem::path valid_path = root / L"valid-deflate-rgb16.tiff";
    write_fixture(valid_path, negaflow::test_fixtures::make_deflate_rgb16_tiff());
    const auto valid = negaflow::imageio::decode_tiff_with_wic(valid_path);
    expect(
        valid.preflight_status == negaflow::core::TiffProbeStatus::ok &&
            valid.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            valid.info.deflate_streams_validated &&
            valid.info.compressed_bytes_validated == 17U &&
            valid.info.deflate_decoded_bytes_validated == 6U &&
            valid.image.samples.size() ==
                negaflow::test_fixtures::lzw_rgb16_expected_samples.size() &&
            std::equal(
                valid.image.samples.begin(),
                valid.image.samples.end(),
                negaflow::test_fixtures::lzw_rgb16_expected_samples.begin()),
        "stored Deflate passes independent validation before exact WIC decode");

    negaflow::imageio::WicTiffDecodeLimits bounded_limits{};
    bounded_limits.probe.max_deflate_compressed_bytes = 16U;
    const auto bounded =
        negaflow::imageio::decode_tiff_with_wic(valid_path, bounded_limits);
    expect(
        bounded.preflight_status ==
                negaflow::core::TiffProbeStatus::compressed_data_limit_exceeded &&
            bounded.status == negaflow::imageio::WicTiffDecodeStatus::preflight_failed,
        "Deflate compressed-input budget fails closed before WIC decode");

    const std::filesystem::path fixed_path = root / L"fixed-deflate-rgb16.tiff";
    write_fixture(
        fixed_path,
        negaflow::test_fixtures::make_fixed_deflate_rgb16_tiff());
    const auto fixed = negaflow::imageio::decode_tiff_with_wic(fixed_path);
    expect(
        fixed.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            fixed.info.deflate_streams_validated &&
            fixed.info.deflate_decoded_bytes_validated == 6U &&
            fixed.image.samples == valid.image.samples,
        "fixed-Huffman Deflate passes validation and matches stored pixels");

    const std::filesystem::path dynamic_path = root / L"dynamic-deflate-rgb16.tiff";
    write_fixture(
        dynamic_path,
        negaflow::test_fixtures::make_dynamic_deflate_rgb16_tiff());
    const auto dynamic = negaflow::imageio::decode_tiff_with_wic(dynamic_path);
    expect(
        dynamic.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            dynamic.info.deflate_streams_validated &&
            dynamic.info.compressed_bytes_validated == 42U &&
            dynamic.info.deflate_decoded_bytes_validated == 6'144U &&
            dynamic.image.samples.size() == 32U * 32U * 3U &&
            std::equal(
                negaflow::test_fixtures::lzw_rgb16_expected_samples.begin(),
                negaflow::test_fixtures::lzw_rgb16_expected_samples.end(),
                dynamic.image.samples.begin()) &&
            std::equal(
                negaflow::test_fixtures::lzw_rgb16_expected_samples.begin(),
                negaflow::test_fixtures::lzw_rgb16_expected_samples.end(),
                dynamic.image.samples.end() - 3),
        "dynamic-Huffman Deflate validates bounded back-references and exact edge pixels");

    const std::filesystem::path malformed_path = root / L"malformed-deflate-rgb16.tiff";
    write_fixture(
        malformed_path,
        negaflow::test_fixtures::make_malformed_deflate_rgb16_tiff());
    const auto malformed = negaflow::imageio::decode_tiff_with_wic(malformed_path);
    expect(
        malformed.preflight_status ==
                negaflow::core::TiffProbeStatus::invalid_compressed_data &&
            malformed.status == negaflow::imageio::WicTiffDecodeStatus::preflight_failed &&
            malformed.image.samples.empty(),
        "malformed stored block fails before WIC and publishes no samples");

    const std::filesystem::path checksum_path = root / L"checksum-deflate-rgb16.tiff";
    write_fixture(
        checksum_path,
        negaflow::test_fixtures::make_bad_checksum_deflate_rgb16_tiff());
    const auto checksum = negaflow::imageio::decode_tiff_with_wic(checksum_path);
    expect(
        checksum.preflight_status ==
                negaflow::core::TiffProbeStatus::invalid_compressed_data &&
            checksum.status == negaflow::imageio::WicTiffDecodeStatus::preflight_failed &&
            checksum.image.samples.empty(),
        "Deflate Adler-32 mismatch fails before WIC and publishes no samples");
}

void test_decoded_byte_limit(const std::filesystem::path& root) {
    constexpr std::uint32_t dimension = 8'192U;
    constexpr std::uint64_t expected_decoded_bytes =
        static_cast<std::uint64_t>(dimension) * dimension * 3U * sizeof(std::uint16_t);
    const std::filesystem::path path = root / L"claimed-expansion-lzw-rgb16.tiff";
    write_fixture(
        path,
        negaflow::test_fixtures::make_claimed_expansion_lzw_rgb16_tiff(
            dimension,
            dimension));

    negaflow::imageio::WicTiffDecodeLimits limits{};
    limits.max_decoded_pixel_bytes = 64ULL * 1024ULL * 1024ULL;
    const auto result = negaflow::imageio::decode_tiff_with_wic(path, limits);
    expect(
        result.preflight_status == negaflow::core::TiffProbeStatus::ok,
        "claimed expansion passes structural preflight");
    expect(
        result.status == negaflow::imageio::WicTiffDecodeStatus::memory_limit_exceeded,
        "decoded-byte limit rejects claimed expansion before CopyPixels");
    expect(
        result.info.decoded_pixel_bytes == expected_decoded_bytes,
        "required decoded bytes are reported");
    expect(result.image.samples.empty(), "decoded-byte rejection allocates no sample buffer");
}

void test_repository_fixture(const std::filesystem::path& path) {
    const auto modified_before = std::filesystem::last_write_time(path);
    const auto size_before = std::filesystem::file_size(path);
    const auto result = negaflow::imageio::decode_tiff_with_wic(path);
    negaflow::imageio::WicTiffDecodeControl row_control{};
    row_control.rows_per_copy = 37U;
    const auto row_result = negaflow::imageio::decode_tiff_with_wic(path, {}, row_control);
    CollectingRowSink streaming_sink{};
    const auto stream_result = negaflow::imageio::decode_tiff_rows_with_wic(
        path,
        streaming_sink,
        {},
        row_control);
    expect(result.status == negaflow::imageio::WicTiffDecodeStatus::ok, "fixture decodes");
    expect(
        result.image.width == 631U && result.image.height == 403U &&
            result.image.layout == negaflow::imageio::DecodedPixelLayout::rgb16 &&
            result.image.alpha_mode == negaflow::imageio::AlphaMode::opaque &&
            result.image.samples.size() == 631ULL * 403ULL * 3ULL &&
            result.image.icc_profile.size() == 3'144U &&
            result.icc_status == negaflow::color::IccProfileStatus::ok &&
            result.info.source_pixel_format == negaflow::imageio::WicPixelFormat::rgb16 &&
            !result.info.format_conversion_used,
        "repository fixture decode contract matches");
    expect(
        row_result.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            row_result.info.copy_operation_count == 11U &&
            row_result.info.completed_rows == 403U &&
            row_result.image.samples == result.image.samples &&
            row_result.image.icc_profile == result.image.icc_profile,
        "repository fixture row copies match whole-frame decode");
    expect(
        stream_result.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            stream_result.image.samples.empty() &&
            stream_result.info.copy_operation_count == 11U && streaming_sink.committed() &&
            streaming_sink.samples() == result.image.samples &&
            streaming_sink.icc_profile() == result.image.icc_profile,
        "repository fixture streaming rows match whole-frame decode");
    expect(
        std::filesystem::file_size(path) == size_before &&
            std::filesystem::last_write_time(path) == modified_before,
        "repository fixture remains unchanged");
}

}  // namespace wic_tiff_decoder_tests

namespace wic_tiff_decoder_tests {
namespace {

// 일부 줄만 원하는 싱크입니다. 입력 감마 추정처럼 띠만 받고, 받은 띠를 그대로 모읍니다.
class BandSink final : public negaflow::imageio::WicTiffRowSink {
public:
    explicit BandSink(std::vector<negaflow::imageio::WicTiffRowBand> bands) : bands_(std::move(bands)) {}

    bool begin(const negaflow::imageio::WicTiffFrameView& frame) noexcept override {
        stride_samples_ = frame.stride_bytes / sizeof(std::uint16_t);
        return true;
    }
    bool write(const negaflow::imageio::WicTiffRowChunk& rows) noexcept override {
        firsts_.push_back(rows.first_row);
        counts_.push_back(rows.row_count);
        samples_.insert(samples_.end(), rows.samples.begin(), rows.samples.end());
        return true;
    }
    void complete(const negaflow::imageio::WicTiffDecodeStatus status) noexcept override {
        ++terminal_count_;
        terminal_status_ = status;
    }
    std::span<const negaflow::imageio::WicTiffRowBand> wanted_rows() const noexcept override { return bands_; }

    std::vector<negaflow::imageio::WicTiffRowBand> bands_;
    std::uint32_t stride_samples_{0};
    std::vector<std::uint32_t> firsts_{};
    std::vector<std::uint32_t> counts_{};
    std::vector<std::uint16_t> samples_{};
    std::uint32_t terminal_count_{0};
    negaflow::imageio::WicTiffDecodeStatus terminal_status_{negaflow::imageio::WicTiffDecodeStatus::invalid_argument};
};

}  // namespace

void test_row_bands(const std::filesystem::path& root) {
    const std::filesystem::path path = root / L"row-bands-lzw-rgb16.tiff";
    write_fixture(path, negaflow::test_fixtures::make_lzw_rgb16_rows_tiff(12U));
    const auto whole = negaflow::imageio::decode_tiff_with_wic(path);
    expect(whole.status == negaflow::imageio::WicTiffDecodeStatus::ok, "row band fixture decodes whole");

    negaflow::imageio::WicTiffDecodeControl control{};
    control.rows_per_copy = 4U;
    BandSink sink{{{1U, 2U}, {5U, 3U}, {11U, 1U}}};
    const auto decoded = negaflow::imageio::decode_tiff_rows_with_wic(path, sink, {}, control);
    std::vector<std::uint16_t> expected{};
    for (const auto& band : sink.bands_) {
        const auto first = whole.image.samples.begin() + static_cast<std::ptrdiff_t>(band.first_row * sink.stride_samples_);
        expected.insert(expected.end(), first, first + static_cast<std::ptrdiff_t>(band.row_count * sink.stride_samples_));
    }
    expect(decoded.status == negaflow::imageio::WicTiffDecodeStatus::ok && sink.terminal_count_ == 1U &&
               sink.terminal_status_ == negaflow::imageio::WicTiffDecodeStatus::ok,
        "row bands decode and complete once");
    expect(sink.firsts_ == std::vector<std::uint32_t>{1U, 5U, 11U} &&
               sink.counts_ == std::vector<std::uint32_t>{2U, 3U, 1U} &&
               decoded.info.copy_operation_count == 3U,
        "only the wanted row bands are copied");
    expect(sink.samples_ == expected, "row band pixels match the whole-frame decode");

    for (const auto& invalid : std::vector<std::vector<negaflow::imageio::WicTiffRowBand>>{
             {{4U, 3U}, {5U, 2U}}, {{10U, 3U}}, {{2U, 0U}}}) {
        BandSink rejected{invalid};
        const auto result = negaflow::imageio::decode_tiff_rows_with_wic(path, rejected, {}, control);
        expect(result.status == negaflow::imageio::WicTiffDecodeStatus::invalid_argument &&
                   rejected.terminal_count_ == 1U && rejected.firsts_.empty(),
            "overlapping, out-of-range, or empty row bands are rejected before copying");
    }
}

// 줄 묶음을 여러 레인이 동시에 풀어도 한 소스가 순서대로 푼 것과 화소가 같아야 합니다.
// 레인은 덩이를 모아 한 번에 넘기므로, 코어가 둘 이상인 기계에서는 쓰기 횟수가 줄어듭니다.
void test_row_lanes(const std::filesystem::path& root) {
    // 압축 스트립 하나짜리는 레인을 쓰지 않습니다(`plan_tiff_lanes`). 비압축은 줄마다 따로 읽힙니다.
    const std::filesystem::path path = root / L"row-lanes-rgb16.tiff";
    write_fixture(path, negaflow::test_fixtures::make_uncompressed_rgb16_defect_tiff(16U, 24U));
    const auto whole = negaflow::imageio::decode_tiff_with_wic(path);
    expect(whole.status == negaflow::imageio::WicTiffDecodeStatus::ok, "row lane fixture decodes whole");

    negaflow::imageio::WicTiffDecodeControl control{};
    control.rows_per_copy = 1U;
    BandSink sink{{}};
    const auto decoded = negaflow::imageio::decode_tiff_rows_with_wic(path, sink, {}, control);
    expect(decoded.status == negaflow::imageio::WicTiffDecodeStatus::ok && sink.terminal_count_ == 1U &&
               sink.terminal_status_ == negaflow::imageio::WicTiffDecodeStatus::ok,
        "row lanes decode and complete once");
    expect(sink.samples_ == whole.image.samples, "row lane pixels match the whole-frame decode");
    std::uint32_t next = 0U;
    for (std::size_t index = 0U; index < sink.firsts_.size(); ++index) {
        expect(sink.firsts_[index] == next, "row lane chunks arrive in row order");
        next += sink.counts_[index];
    }
    expect(next == 24U, "row lanes cover every row");
    if (negaflow::core::physical_cores() >= 2U) {
        expect(sink.firsts_.size() < 24U, "row lanes hand several rows over per write");
    }
}

}  // namespace wic_tiff_decoder_tests
