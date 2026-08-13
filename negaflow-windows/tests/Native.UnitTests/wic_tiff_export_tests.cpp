#include "negaflow/output/wic_tiff_export.h"
#include "tiff_ifd_allowlist.h"

#include <Windows.h>

#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

void report_failure(const negaflow::output::WicTiffExportResult& result) {
    if (result.status != negaflow::output::WicTiffExportStatus::ok) {
        std::cerr << "  status="
                  << negaflow::output::wic_tiff_export_status_name(result.status)
                  << " conversion="
                  << negaflow::output::working_to_srgb16_status_name(
                         result.conversion_status)
                  << " unexpected_tag=" << result.info.unexpected_metadata_tag
                  << " native=0x" << std::hex << result.native_error_code
                  << " cleanup=0x" << result.cleanup_error_code << std::dec << '\n';
    }
}

class TempDirectory final {
public:
    TempDirectory() {
        path_ = std::filesystem::temp_directory_path() /
                (L"negaflow-tiff-export-tests-" + std::to_wstring(GetCurrentProcessId()));
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
        error.clear();
        std::filesystem::create_directories(path_, error);
        expect(!error, "temporary TIFF export directory is created");
    }

    TempDirectory(const TempDirectory&) = delete;
    TempDirectory& operator=(const TempDirectory&) = delete;
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
    image.width = 3U;
    image.height = 2U;
    image.stride_pixels = 3U;
    image.pixels = {
        {0.0F, 0.0031308F, 0.21404114F, 1.0F},
        {0.25F, 0.5F, 0.75F, 1.0F},
        {1.0F, 1.1F, -0.1F, 1.0F},
        {0.9F, 0.1F, 0.4F, 1.0F},
        {0.01F, 0.02F, 0.03F, 1.0F},
        {0.6F, 0.7F, 0.8F, 1.0F},
    };
    return image;
}

[[nodiscard]] bool has_staging_file(const std::filesystem::path& root) {
    std::error_code error{};
    for (const auto& entry : std::filesystem::directory_iterator(root, error)) {
        if (entry.path().filename().wstring().starts_with(L".negaflow-export-")) {
            return true;
        }
    }
    return false;
}

[[nodiscard]] std::string read_file(const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    return {
        std::istreambuf_iterator<char>{input},
        std::istreambuf_iterator<char>{},
    };
}

void test_round_trip_and_publish(const std::filesystem::path& root) {
    const std::filesystem::path destination = root / L"round-trip.tif";
    const auto result = negaflow::output::export_working_to_srgb16_tiff(
        make_image(),
        destination);
    report_failure(result);
    expect(
        result.status == negaflow::output::WicTiffExportStatus::ok,
        "16-bit TIFF export succeeds");
    expect(
        result.conversion_status == negaflow::output::WorkingToSrgb16Status::ok,
        "working conversion succeeds");
    expect(
        result.info.width == 3U && result.info.height == 2U &&
            result.info.encoded_pixel_bytes == 36U,
        "TIFF dimensions and encoded pixel bytes are exact");
    expect(result.info.clipped_color_components == 2U, "output clipping is reported");
    expect(
        result.info.color_profile_bytes > 0U && result.info.strip_count > 0U &&
            result.info.ifd_entry_count > 0U && result.info.compression == 1U,
        "TIFF is uncompressed and contains strips, ICC and bounded IFD tags");
    expect(
        result.info.structure_verified && result.info.metadata_verified &&
            result.info.pixels_verified && result.info.profile_verified &&
            result.info.published,
        "structure, metadata, pixels, profile and publish are verified");
    std::error_code error{};
    const std::uint64_t final_size = std::filesystem::file_size(destination, error);
    expect(
        !error && final_size == result.info.artifact_bytes && final_size > 0U,
        "published TIFF artifact size is verified");
    expect(!has_staging_file(root), "successful TIFF publish leaves no staging file");
}

void test_existing_destination_is_preserved(const std::filesystem::path& root) {
    const std::filesystem::path destination = root / L"existing.tif";
    {
        std::ofstream output(destination, std::ios::binary | std::ios::trunc);
        output << "existing-content";
    }
    const auto result = negaflow::output::export_working_to_srgb16_tiff(
        make_image(),
        destination);
    if (result.status != negaflow::output::WicTiffExportStatus::destination_exists) {
        report_failure(result);
    }
    expect(
        result.status == negaflow::output::WicTiffExportStatus::destination_exists,
        "existing TIFF destination is rejected");
    expect(read_file(destination) == "existing-content", "existing TIFF is unchanged");
    expect(!has_staging_file(root), "TIFF destination rejection leaves no staging file");
}

void test_compression_and_dpi(const std::filesystem::path& root) {
    struct CompressionCase final {
        negaflow::output::WicTiffCompression requested;
        std::uint16_t encoded_tag;
        const wchar_t* name;
    };
    constexpr std::array<CompressionCase, 2> cases{{
        {negaflow::output::WicTiffCompression::lzw, 5U, L"lzw"},
        {negaflow::output::WicTiffCompression::deflate, 8U, L"deflate"},
    }};
    for (const CompressionCase& entry : cases) {
        negaflow::output::WicTiffExportLimits limits{};
        limits.compression = entry.requested;
        limits.output_dpi = 300U;
        const auto result = negaflow::output::export_working_to_srgb16_tiff(
            make_image(),
            root / (std::wstring{L"round-trip-"} + entry.name + L".tif"),
            limits);
        report_failure(result);
        expect(
            result.status == negaflow::output::WicTiffExportStatus::ok &&
                result.info.compression == entry.encoded_tag &&
                result.info.output_dpi == 300U && result.info.resolution_verified &&
                result.info.structure_verified && result.info.metadata_verified &&
                result.info.pixels_verified && result.info.profile_verified &&
                result.info.published,
            "TIFF compression and DPI metadata round trip through WIC");
    }
}

void test_failures_leave_no_file(const std::filesystem::path& root) {
    negaflow::imaging::WorkingImage image = make_image();
    image.pixels[0].alpha = 0.5F;
    const std::filesystem::path alpha_destination = root / L"alpha-rejected.tif";
    const auto alpha_result = negaflow::output::export_working_to_srgb16_tiff(
        image,
        alpha_destination);
    expect(
        alpha_result.status ==
                negaflow::output::WicTiffExportStatus::working_conversion_failed &&
            alpha_result.conversion_status ==
                negaflow::output::WorkingToSrgb16Status::non_opaque_alpha,
        "TIFF alpha is rejected before staging");
    expect(!std::filesystem::exists(alpha_destination), "alpha rejection creates no TIFF");

    negaflow::output::WicTiffExportLimits limits{};
    limits.max_artifact_bytes = 64U;
    const std::filesystem::path artifact_destination = root / L"artifact-limit.tif";
    const auto artifact_result = negaflow::output::export_working_to_srgb16_tiff(
        make_image(),
        artifact_destination,
        limits);
    if (artifact_result.status !=
        negaflow::output::WicTiffExportStatus::structure_verification_failed) {
        report_failure(artifact_result);
    }
    expect(
        artifact_result.status ==
            negaflow::output::WicTiffExportStatus::structure_verification_failed,
        "TIFF artifact budget blocks publish");
    expect(!std::filesystem::exists(artifact_destination), "artifact limit publishes no TIFF");

    limits = {};
    limits.readback_buffer_bytes = 17U;
    const std::filesystem::path readback_destination = root / L"readback-limit.tif";
    const auto readback_result = negaflow::output::export_working_to_srgb16_tiff(
        make_image(),
        readback_destination,
        limits);
    if (readback_result.status != negaflow::output::WicTiffExportStatus::readback_failed) {
        report_failure(readback_result);
    }
    expect(
        readback_result.status == negaflow::output::WicTiffExportStatus::readback_failed,
        "TIFF readback budget must hold one row");
    expect(!std::filesystem::exists(readback_destination), "readback limit publishes no TIFF");
    expect(!has_staging_file(root), "TIFF failures remove staging files");
}

void test_metadata_allowlist_rejects_descriptive_tag(const std::filesystem::path& root) {
    const std::filesystem::path path = root / L"unexpected-metadata.tif";
    constexpr std::array<std::uint8_t, 26> bytes{
        0x49U, 0x49U, 0x2aU, 0x00U, 0x08U, 0x00U, 0x00U, 0x00U,
        0x01U, 0x00U,
        0x0fU, 0x01U, 0x02U, 0x00U, 0x01U, 0x00U, 0x00U, 0x00U,
        0x00U, 0x00U, 0x00U, 0x00U,
        0x00U, 0x00U, 0x00U, 0x00U,
    };
    {
        std::ofstream output(path, std::ios::binary | std::ios::trunc);
        output.write(
            reinterpret_cast<const char*>(bytes.data()),
            static_cast<std::streamsize>(bytes.size()));
    }
    negaflow::output::detail::TiffIfdAllowlistInfo info{};
    std::uint32_t native_error = 0U;
    const auto status = negaflow::output::detail::inspect_minimal_rgb_tiff_ifd(
        path,
        1U * 1024U * 1024U,
        128U,
        info,
        native_error);
    expect(
        status == negaflow::output::detail::TiffIfdAllowlistStatus::unexpected_tag &&
            info.unexpected_tag == 271U,
        "minimal metadata allowlist rejects TIFF Make");
}

}  // namespace

int main() {
    const TempDirectory temporary{};
    test_round_trip_and_publish(temporary.path());
    test_existing_destination_is_preserved(temporary.path());
    test_compression_and_dpi(temporary.path());
    test_failures_leave_no_file(temporary.path());
    test_metadata_allowlist_rejects_descriptive_tag(temporary.path());
    if (failures != 0) {
        std::cerr << failures << " WIC TIFF export test(s) failed\n";
        return 1;
    }
    std::cout << "WIC TIFF export tests passed\n";
    return 0;
}
