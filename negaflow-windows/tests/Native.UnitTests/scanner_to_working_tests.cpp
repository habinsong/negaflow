#include "negaflow/imageio/wic_tiff_decoder.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/imaging/scanner_to_working.h"
#include "synthetic_wic_tiff.h"

#include <Windows.h>

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
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
                (L"negaflow-scanner-stream-tests-" +
                 std::to_wstring(GetCurrentProcessId()));
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
        error.clear();
        std::filesystem::create_directories(path_, error);
        expect(!error, "temporary scanner stream test directory is created");
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

class CancellingProgress final
    : public negaflow::imageio::WicTiffDecodeProgressObserver {
public:
    CancellingProgress(
        std::stop_source& stop_source,
        const std::uint32_t cancel_after_rows) noexcept
        : stop_source_(stop_source), cancel_after_rows_(cancel_after_rows) {}

    void report(const negaflow::imageio::WicTiffDecodeProgress progress) noexcept override {
        if (progress.completed_rows >= cancel_after_rows_ &&
            progress.completed_rows < progress.total_rows) {
            stop_source_.request_stop();
        }
    }

private:
    std::stop_source& stop_source_;
    std::uint32_t cancel_after_rows_{0};
};

void write_fixture(const std::filesystem::path& path, const std::vector<std::uint8_t>& bytes) {
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    output.write(
        reinterpret_cast<const char*>(bytes.data()),
        static_cast<std::streamsize>(bytes.size()));
    output.close();
    expect(output.good(), "synthetic scanner stream fixture is written");
}

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

void write_be_u32(
    std::vector<std::uint8_t>& bytes,
    const std::size_t offset,
    const std::uint32_t value) {
    bytes[offset] = static_cast<std::uint8_t>((value >> 24U) & 0xffU);
    bytes[offset + 1U] = static_cast<std::uint8_t>((value >> 16U) & 0xffU);
    bytes[offset + 2U] = static_cast<std::uint8_t>((value >> 8U) & 0xffU);
    bytes[offset + 3U] = static_cast<std::uint8_t>(value & 0xffU);
}

void test_linear_scanner_path() {
    negaflow::imageio::DecodedImage decoded{};
    decoded.width = 2U;
    decoded.height = 1U;
    decoded.stride_bytes = 12U;
    decoded.layout = negaflow::imageio::DecodedPixelLayout::rgb16;
    decoded.alpha_mode = negaflow::imageio::AlphaMode::opaque;
    decoded.samples = {0U, 32'768U, 65'535U, 65'535U, 0U, 16'384U};

    const auto result = negaflow::imaging::convert_scanner_to_working(decoded);
    expect(
        result.status == negaflow::imaging::ScannerToWorkingStatus::ok,
        "untagged linear scanner input converts");
    expect(
        result.info.transform == negaflow::imaging::ScannerWorkingTransform::linear_scanner_raw,
        "untagged route is explicit");
    expect(result.image.width == 2U && result.image.height == 1U, "dimensions are preserved");
    expect(result.image.pixels.size() == 2U, "working pixel count");
    if (result.image.pixels.size() == 2U) {
        expect(result.image.pixels[0].red == 0.0F, "black remains black");
        expect(
            std::abs(result.image.pixels[0].green - (32'768.0F / 65'535.0F)) < 1.0e-7F,
            "untagged samples are normalized without an sRGB EOTF");
        expect(result.image.pixels[0].blue == 1.0F, "white remains white");
        expect(result.image.pixels[1].alpha == 1.0F, "working alpha is opaque");
    }
}

void test_untagged_srgb_path() {
    negaflow::imageio::DecodedImage decoded{};
    decoded.width = 1U;
    decoded.height = 1U;
    decoded.stride_bytes = 6U;
    decoded.layout = negaflow::imageio::DecodedPixelLayout::rgb16;
    decoded.alpha_mode = negaflow::imageio::AlphaMode::opaque;
    decoded.untagged_rgb_transfer =
        negaflow::imageio::UntaggedRgbTransfer::srgb_encoded;
    decoded.samples = {32'768U, 32'768U, 32'768U};

    const auto result = negaflow::imaging::convert_scanner_to_working(decoded);
    expect(
        result.status == negaflow::imaging::ScannerToWorkingStatus::ok &&
            result.info.transform ==
                negaflow::imaging::ScannerWorkingTransform::untagged_srgb_to_linear,
        "untagged standard image input uses the sRGB transfer");
    expect(
        result.image.pixels.size() == 1U && result.image.pixels[0].red > 0.21F &&
            result.image.pixels[0].red < 0.22F,
        "untagged standard image is not interpreted as linear scanner data");
}

void test_streamed_linear_scanner_path(const std::filesystem::path& root) {
    const std::filesystem::path path = root / L"linear-stream-lzw-rgb16.tiff";
    write_fixture(path, negaflow::test_fixtures::make_lzw_rgb16_rows_tiff(5U));

    const auto decoded = negaflow::imageio::decode_tiff_with_wic(path);
    const auto reference = negaflow::imaging::convert_scanner_to_working(decoded.image);
    negaflow::imageio::WicTiffDecodeControl control{};
    control.rows_per_copy = 2U;
    const auto streamed = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        path,
        {},
        {},
        control);
    expect(
        decoded.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            reference.status == negaflow::imaging::ScannerToWorkingStatus::ok,
        "linear streaming reference path succeeds");
    expect(
        streamed.decode.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            streamed.working.status == negaflow::imaging::ScannerToWorkingStatus::ok &&
            streamed.decode.image.samples.empty(),
        "linear streaming path owns no decoded full frame");
    expect(
        streamed.decode.info.copy_operation_count == 3U &&
            streamed.decode.info.peak_copy_pixel_bytes == 12U &&
            streamed.info.peak_conversion_temporary_pixel_bytes == 0U,
        "linear streaming chunk accounting is exact");
    expect(
        working_images_equal(streamed.working.image, reference.image),
        "linear streaming pixels match full-frame conversion exactly");
}

void test_rejections() {
    negaflow::imageio::DecodedImage rgba{};
    rgba.width = 1U;
    rgba.height = 1U;
    rgba.stride_bytes = 8U;
    rgba.layout = negaflow::imageio::DecodedPixelLayout::rgba16;
    rgba.alpha_mode = negaflow::imageio::AlphaMode::associated;
    rgba.samples = {1U, 2U, 3U, 65'534U};
    expect(
        negaflow::imaging::convert_scanner_to_working(rgba).status ==
            negaflow::imaging::ScannerToWorkingStatus::ok,
        "non-opaque alpha enters the working image");
    const auto alpha_result = negaflow::imaging::convert_scanner_to_working(rgba);
    expect(
        alpha_result.image.pixels.size() == 1U &&
            std::abs(alpha_result.image.pixels[0].alpha - (65'534.0F / 65'535.0F)) < 1.0e-7F,
        "the decoded alpha sample is preserved in working space");

    rgba.samples[3] = 65'535U;
    rgba.icc_profile.resize(132U, 0U);
    expect(
        negaflow::imaging::convert_scanner_to_working(rgba).status ==
            negaflow::imaging::ScannerToWorkingStatus::invalid_icc_profile,
        "invalid ICC bytes are rejected before WIC");

    rgba.icc_profile.clear();
    rgba.stride_bytes = 6U;
    expect(
        negaflow::imaging::convert_scanner_to_working(rgba).status ==
            negaflow::imaging::ScannerToWorkingStatus::invalid_stride,
        "short source stride is rejected");

    rgba.stride_bytes = 8U;
    rgba.layout = static_cast<negaflow::imageio::DecodedPixelLayout>(0xffU);
    expect(
        negaflow::imaging::convert_scanner_to_working(rgba).status ==
            negaflow::imaging::ScannerToWorkingStatus::invalid_argument,
        "unknown decoded pixel layouts are rejected");

    rgba.layout = negaflow::imageio::DecodedPixelLayout::rgba16;
    rgba.icc_profile.assign(132U, 0U);
    write_be_u32(rgba.icc_profile, 0U, 132U);
    write_be_u32(rgba.icc_profile, 12U, 0x70727472U);
    write_be_u32(rgba.icc_profile, 16U, 0x52474220U);
    write_be_u32(rgba.icc_profile, 20U, 0x58595a20U);
    write_be_u32(rgba.icc_profile, 36U, 0x61637370U);
    expect(
        negaflow::imaging::convert_scanner_to_working(rgba).status ==
            negaflow::imaging::ScannerToWorkingStatus::unsupported_icc_profile_class,
        "output-class RGB profiles are rejected as scanner sources");
}

void test_embedded_icc_path(const std::filesystem::path& path) {
    const auto modified_before = std::filesystem::last_write_time(path);
    const auto size_before = std::filesystem::file_size(path);
    auto decoded = negaflow::imageio::decode_tiff_with_wic(path);
    expect(
        decoded.status == negaflow::imageio::WicTiffDecodeStatus::ok,
        "ICC integration fixture decodes");
    if (decoded.status != negaflow::imageio::WicTiffDecodeStatus::ok) {
        return;
    }
    const std::vector<std::uint16_t> samples_before = decoded.image.samples;
    const std::vector<std::uint8_t> profile_before = decoded.image.icc_profile;

    const auto result = negaflow::imaging::convert_scanner_to_working(decoded.image);
    negaflow::imageio::WicTiffDecodeControl row_control{};
    row_control.rows_per_copy = 37U;
    const auto streamed = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        path,
        {},
        {},
        row_control);
    expect(
        result.status == negaflow::imaging::ScannerToWorkingStatus::ok,
        "embedded ICC converts through WIC");
    expect(
        result.info.transform ==
            negaflow::imaging::ScannerWorkingTransform::embedded_icc_windows_icm_srgb16,
        "ICC route is explicit");
    expect(
        result.info.intermediate_bits_per_color_channel == 16U,
        "Windows ICM intermediate precision is reported");
    expect(
        result.image.width == decoded.image.width && result.image.height == decoded.image.height,
        "ICC transform preserves dimensions");
    expect(
        result.image.pixels.size() ==
            static_cast<std::size_t>(decoded.image.width) * decoded.image.height,
        "ICC transform produces one working pixel per source pixel");
    for (const auto& pixel : result.image.pixels) {
        expect(
            std::isfinite(pixel.red) && std::isfinite(pixel.green) &&
                std::isfinite(pixel.blue) && pixel.red >= 0.0F && pixel.red <= 1.0F &&
                pixel.green >= 0.0F && pixel.green <= 1.0F && pixel.blue >= 0.0F &&
                pixel.blue <= 1.0F && pixel.alpha == 1.0F,
            "ICC output is finite normalized linear RGB with opaque alpha");
        if (failures != 0) {
            break;
        }
    }
    expect(decoded.image.samples == samples_before, "ICM color transform does not mutate samples");
    expect(decoded.image.icc_profile == profile_before, "ICM color transform does not mutate ICC");
    expect(
        streamed.decode.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            streamed.working.status == negaflow::imaging::ScannerToWorkingStatus::ok &&
            streamed.decode.image.samples.empty() &&
            streamed.info.peak_conversion_temporary_pixel_bytes > 0U,
        "embedded ICC streaming conversion succeeds without a decoded full frame");
    expect(
        working_images_equal(streamed.working.image, result.image),
        "embedded ICC row conversion matches full-frame conversion exactly");

    negaflow::imaging::ScannerToWorkingLimits temporary_limit{};
    temporary_limit.max_temporary_pixel_bytes = 1U;
    const auto limited = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        path,
        {},
        temporary_limit,
        row_control);
    expect(
        limited.decode.status == negaflow::imageio::WicTiffDecodeStatus::row_sink_failed &&
            limited.working.status ==
                negaflow::imaging::ScannerToWorkingStatus::memory_limit_exceeded &&
            limited.working.image.pixels.empty(),
        "streaming ICC temporary-byte limit publishes no working pixels");

    std::stop_source stop_source{};
    CancellingProgress cancelling_progress{stop_source, 37U};
    row_control.stop_token = stop_source.get_token();
    row_control.progress_observer = &cancelling_progress;
    const auto cancelled = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        path,
        {},
        {},
        row_control);
    expect(
        cancelled.decode.status == negaflow::imageio::WicTiffDecodeStatus::cancelled &&
            cancelled.working.status == negaflow::imaging::ScannerToWorkingStatus::cancelled &&
            cancelled.working.image.pixels.empty(),
        "streaming ICC cancellation discards partial working pixels");
    expect(std::filesystem::file_size(path) == size_before, "fixture size is unchanged");
    expect(
        std::filesystem::last_write_time(path) == modified_before,
        "fixture modification time is unchanged");
}

}  // namespace

int main(const int argument_count, const char* const arguments[]) {
    TempDirectory temporary{};
    test_linear_scanner_path();
    test_untagged_srgb_path();
    test_streamed_linear_scanner_path(temporary.path());
    test_rejections();
    if (argument_count == 2) {
        test_embedded_icc_path(std::filesystem::path{arguments[1]});
    } else if (argument_count != 1) {
        std::cerr << "expected zero or one TIFF fixture path\n";
        return 2;
    }

    if (failures != 0) {
        std::cerr << failures << " scanner-to-working test(s) failed\n";
        return 1;
    }
    std::cout << "scanner-to-working tests passed\n";
    return 0;
}
