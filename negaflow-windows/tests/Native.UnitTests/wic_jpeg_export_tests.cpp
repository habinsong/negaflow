#include "negaflow/output/wic_jpeg_export.h"
#include "negaflow/imageio/wic_standard_image_decoder.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <cmath>
#include <cstdint>
#include <filesystem>
#include <iostream>

namespace {

using Microsoft::WRL::ComPtr;
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
                (L"negaflow-jpeg-export-tests-" + std::to_wstring(GetCurrentProcessId()));
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
        error.clear();
        std::filesystem::create_directories(path_, error);
        expect(!error, "temporary JPEG export directory is created");
    }

    ~TempDirectory() {
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
    }

    [[nodiscard]] const std::filesystem::path& path() const noexcept { return path_; }

private:
    std::filesystem::path path_{};
};

negaflow::imaging::WorkingImage make_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 4U;
    image.height = 3U;
    image.stride_pixels = 4U;
    image.pixels = {
        {0.00F, 0.04F, 0.21F, 1.0F}, {0.25F, 0.50F, 0.75F, 1.0F},
        {1.00F, 1.10F, -0.10F, 1.0F}, {0.90F, 0.10F, 0.40F, 1.0F},
        {0.01F, 0.02F, 0.03F, 1.0F}, {0.60F, 0.70F, 0.80F, 1.0F},
        {0.18F, 0.35F, 0.63F, 1.0F}, {0.74F, 0.44F, 0.15F, 1.0F},
        {0.33F, 0.22F, 0.11F, 1.0F}, {0.88F, 0.95F, 0.07F, 1.0F},
        {0.52F, 0.63F, 0.74F, 1.0F}, {0.92F, 0.82F, 0.72F, 1.0F},
    };
    return image;
}

void test_round_trip_and_metadata(const std::filesystem::path& root) {
    const std::filesystem::path destination = root / L"round-trip.jpg";
    const auto result = negaflow::output::export_working_to_srgb8_jpeg(
        make_image(), destination, 0.96F, 300U);
    if (result.status != negaflow::output::WicJpegExportStatus::ok) {
        std::cerr << "  status="
                  << negaflow::output::wic_jpeg_export_status_name(result.status)
                  << " conversion="
                  << negaflow::output::working_to_srgb16_status_name(
                         result.conversion_status)
                  << " native=0x" << std::hex << result.native_error_code
                  << " cleanup=0x" << result.cleanup_error_code << std::dec
                  << " width=" << result.info.width << " height=" << result.info.height
                  << " sampling=" << static_cast<unsigned>(result.info.chroma_subsampling)
                  << " bytes=" << result.info.artifact_bytes << '\n';
    }
    expect(
        result.status == negaflow::output::WicJpegExportStatus::ok,
        "8-bit JPEG export succeeds");
    expect(
        result.conversion_status == negaflow::output::WorkingToSrgb16Status::ok,
        "JPEG working conversion succeeds");
    expect(
        result.info.width == 4U && result.info.height == 3U &&
            result.info.encoded_pixel_bytes == 72U,
        "JPEG dimensions and 16-bit source bytes are exact");
    expect(
        result.info.clipped_color_components == 2U,
        "JPEG reports clipped output components");
    expect(
        result.info.color_profile_bytes > 0U && result.info.artifact_bytes > 0U &&
            result.info.chroma_subsampling == 0x11U,
        "JPEG carries sRGB and the high-quality 4:4:4 policy");
    expect(
        result.info.structure_verified && result.info.profile_verified &&
            result.info.resolution_verified && result.info.published,
        "JPEG structure, profile, resolution and publication are verified");

    const auto decoded = negaflow::imageio::decode_standard_image_with_wic(destination);
    expect(
        decoded.status == negaflow::imageio::WicStandardImageDecodeStatus::ok &&
            decoded.image.width == 4U && decoded.image.height == 3U &&
            !decoded.image.icc_profile.empty(),
        "published JPEG decodes with dimensions and its embedded profile");
    const auto working = negaflow::imaging::convert_scanner_to_working(decoded.image);
    expect(
        working.status == negaflow::imaging::ScannerToWorkingStatus::ok &&
            working.image.pixels.size() == 12U,
        "published JPEG re-enters the standard working path");
}

void test_invalid_quality_does_not_publish(const std::filesystem::path& root) {
    const std::filesystem::path destination = root / L"invalid-quality.jpg";
    const auto result = negaflow::output::export_working_to_srgb8_jpeg(
        make_image(), destination, 1.01F);
    expect(
        result.status == negaflow::output::WicJpegExportStatus::invalid_quality,
        "JPEG rejects a quality outside the normalized public range");
    expect(!std::filesystem::exists(destination), "invalid JPEG options leave no artifact");
}

}  // namespace

int main() {
    TempDirectory root{};
    test_round_trip_and_metadata(root.path());
    test_invalid_quality_does_not_publish(root.path());
    if (failures != 0) {
        std::cerr << failures << " JPEG export test(s) failed\n";
        return 1;
    }
    std::cout << "JPEG export tests passed\n";
    return 0;
}
