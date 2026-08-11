#include "negaflow/imageio/wic_tiff_decoder.h"
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

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

class TempDirectory final {
public:
    TempDirectory() {
        path_ = std::filesystem::temp_directory_path() /
                (L"negaflow-wic-tests-" + std::to_wstring(GetCurrentProcessId()));
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
        error.clear();
        std::filesystem::create_directories(path_, error);
        expect(!error, "temporary WIC test directory is created");
    }

    TempDirectory(const TempDirectory&) = delete;
    TempDirectory& operator=(const TempDirectory&) = delete;

    ~TempDirectory() {
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
    }

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_{};
};

class RecordingProgress final
    : public negaflow::imageio::WicTiffDecodeProgressObserver {
public:
    explicit RecordingProgress(
        std::stop_source* const stop_source = nullptr,
        const std::uint32_t cancel_after_rows = 0U) noexcept
        : stop_source_(stop_source), cancel_after_rows_(cancel_after_rows) {}

    void report(const negaflow::imageio::WicTiffDecodeProgress progress) noexcept override {
        if (event_count_ < events_.size()) {
            events_[event_count_] = progress;
            ++event_count_;
        }
        if (stop_source_ != nullptr && progress.completed_rows >= cancel_after_rows_ &&
            progress.completed_rows < progress.total_rows) {
            stop_source_->request_stop();
        }
    }

    [[nodiscard]] std::size_t event_count() const noexcept {
        return event_count_;
    }

    [[nodiscard]] const negaflow::imageio::WicTiffDecodeProgress& event(
        const std::size_t index) const noexcept {
        return events_[index];
    }

private:
    std::array<negaflow::imageio::WicTiffDecodeProgress, 32> events_{};
    std::size_t event_count_{0};
    std::stop_source* stop_source_{nullptr};
    std::uint32_t cancel_after_rows_{0};
};

class CollectingRowSink final : public negaflow::imageio::WicTiffRowSink {
public:
    explicit CollectingRowSink(const bool reject_first_write = false) noexcept
        : reject_first_write_(reject_first_write) {}

    bool begin(const negaflow::imageio::WicTiffFrameView& frame) noexcept override {
        try {
            if (frame.width == 0U || frame.height == 0U ||
                frame.stride_bytes % sizeof(std::uint16_t) != 0U) {
                return false;
            }
            height_ = frame.height;
            stride_samples_ = frame.stride_bytes / sizeof(std::uint16_t);
            const std::uint64_t sample_count =
                static_cast<std::uint64_t>(stride_samples_) * height_;
            if (sample_count > std::numeric_limits<std::size_t>::max()) {
                return false;
            }
            samples_.assign(static_cast<std::size_t>(sample_count), 0U);
            icc_profile_.assign(frame.icc_profile.begin(), frame.icc_profile.end());
            active_ = true;
            return true;
        } catch (...) {
            return false;
        }
    }

    bool write(const negaflow::imageio::WicTiffRowChunk& rows) noexcept override {
        if (reject_first_write_ && next_row_ == 0U) {
            return false;
        }
        if (!active_ || rows.first_row != next_row_ || rows.row_count == 0U ||
            rows.first_row > height_ || rows.row_count > height_ - rows.first_row ||
            rows.stride_bytes / sizeof(std::uint16_t) != stride_samples_) {
            return false;
        }
        const std::size_t expected_samples =
            static_cast<std::size_t>(stride_samples_) * rows.row_count;
        if (rows.samples.size() != expected_samples) {
            return false;
        }
        const std::size_t destination =
            static_cast<std::size_t>(rows.first_row) * stride_samples_;
        std::copy(rows.samples.begin(), rows.samples.end(), samples_.begin() + destination);
        next_row_ += rows.row_count;
        return true;
    }

    void complete(const negaflow::imageio::WicTiffDecodeStatus status) noexcept override {
        ++terminal_count_;
        terminal_status_ = status;
        committed_ = status == negaflow::imageio::WicTiffDecodeStatus::ok &&
                     next_row_ == height_;
        active_ = false;
        if (!committed_) {
            std::vector<std::uint16_t>{}.swap(samples_);
            std::vector<std::uint8_t>{}.swap(icc_profile_);
        }
    }

    [[nodiscard]] const std::vector<std::uint16_t>& samples() const noexcept {
        return samples_;
    }

    [[nodiscard]] const std::vector<std::uint8_t>& icc_profile() const noexcept {
        return icc_profile_;
    }

    [[nodiscard]] std::uint32_t terminal_count() const noexcept {
        return terminal_count_;
    }

    [[nodiscard]] negaflow::imageio::WicTiffDecodeStatus terminal_status() const noexcept {
        return terminal_status_;
    }

    [[nodiscard]] bool committed() const noexcept {
        return committed_;
    }

private:
    std::uint32_t height_{0};
    std::uint32_t stride_samples_{0};
    std::uint32_t next_row_{0};
    std::uint32_t terminal_count_{0};
    negaflow::imageio::WicTiffDecodeStatus terminal_status_{
        negaflow::imageio::WicTiffDecodeStatus::invalid_argument};
    bool active_{false};
    bool committed_{false};
    bool reject_first_write_{false};
    std::vector<std::uint16_t> samples_{};
    std::vector<std::uint8_t> icc_profile_{};
};

void write_fixture(const std::filesystem::path& path, const std::vector<std::uint8_t>& bytes) {
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    output.write(
        reinterpret_cast<const char*>(bytes.data()),
        static_cast<std::streamsize>(bytes.size()));
    output.close();
    expect(output.good(), "synthetic WIC fixture is written");
}

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

}  // namespace

int main(const int argument_count, const char* const arguments[]) {
    if (argument_count > 2) {
        std::cerr << "expected zero or one TIFF fixture path\n";
        return 2;
    }

    TempDirectory temporary{};
    test_valid_lzw(temporary.path());
    test_gray16_companion(temporary.path());
    test_eight_bit_widens_by_bit_replication(temporary.path());
    test_lzw_code_width_transition(temporary.path());
    test_lzw_dictionary_limit_and_forward_reference(temporary.path());
    test_row_copy_progress_and_cancellation(temporary.path());
    test_malformed_lzw(temporary.path());
    test_semantically_invalid_lzw(temporary.path());
    test_deflate_preflight(temporary.path());
    test_decoded_byte_limit(temporary.path());
    if (argument_count == 2) {
        test_repository_fixture(std::filesystem::path{arguments[1]});
    }

    if (failures != 0) {
        std::cerr << failures << " WIC TIFF decoder test(s) failed\n";
        return 1;
    }
    std::cout << "WIC TIFF decoder tests passed\n";
    return 0;
}
