#include "negaflow/output/wic_png_export.h"
#include "atomic_output_file.h"

#include <Windows.h>

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

void report_failure(const negaflow::output::WicPngExportResult& result) {
    if (result.status != negaflow::output::WicPngExportStatus::ok) {
        std::cerr << "  status="
                  << negaflow::output::wic_png_export_status_name(result.status)
                  << " conversion="
                  << negaflow::output::working_to_srgb16_status_name(
                         result.conversion_status)
                  << " native=0x" << std::hex << result.native_error_code
                  << " cleanup=0x" << result.cleanup_error_code << std::dec << '\n';
    }
}

class TempDirectory final {
public:
    TempDirectory() {
        path_ = std::filesystem::temp_directory_path() /
                (L"negaflow-png-export-tests-" + std::to_wstring(GetCurrentProcessId()));
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
        error.clear();
        std::filesystem::create_directories(path_, error);
        expect(!error, "temporary PNG export directory is created");
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
    const std::filesystem::path destination = root / L"round-trip.png";
    const auto result = negaflow::output::export_working_to_srgb16_png(
        make_image(),
        destination);
    report_failure(result);
    expect(
        result.status == negaflow::output::WicPngExportStatus::ok,
        "16-bit PNG export succeeds");
    expect(
        result.conversion_status == negaflow::output::WorkingToSrgb16Status::ok,
        "working conversion succeeds");
    expect(
        result.info.width == 3U && result.info.height == 2U &&
            result.info.encoded_pixel_bytes == 36U,
        "PNG dimensions and encoded pixel bytes are exact");
    expect(result.info.clipped_color_components == 2U, "output clipping is reported");
    expect(
        result.info.color_profile_bytes > 0U && result.info.image_data_chunks > 0U,
        "PNG contains a destination profile and image data");
    expect(
        result.info.structure_verified && result.info.pixels_verified &&
            result.info.profile_verified && result.info.published,
        "structure, pixels, profile and publish are verified");
    std::error_code error{};
    const std::uint64_t final_size = std::filesystem::file_size(destination, error);
    expect(
        !error && final_size == result.info.artifact_bytes && final_size > 0U,
        "published artifact size is verified");
    expect(!has_staging_file(root), "successful publish leaves no staging file");
}

void test_existing_destination_is_preserved(const std::filesystem::path& root) {
    const std::filesystem::path destination = root / L"existing.png";
    {
        std::ofstream output(destination, std::ios::binary | std::ios::trunc);
        output << "existing-content";
    }
    const auto result = negaflow::output::export_working_to_srgb16_png(
        make_image(),
        destination);
    if (result.status != negaflow::output::WicPngExportStatus::destination_exists) {
        report_failure(result);
    }
    expect(
        result.status == negaflow::output::WicPngExportStatus::destination_exists,
        "existing destination is rejected");
    expect(read_file(destination) == "existing-content", "existing destination is unchanged");
    expect(!has_staging_file(root), "destination rejection leaves no staging file");
}

void test_preflight_failures_leave_no_file(const std::filesystem::path& root) {
    negaflow::imaging::WorkingImage image = make_image();
    image.pixels[0].alpha = 0.5F;
    const std::filesystem::path alpha_destination = root / L"alpha-rejected.png";
    const auto alpha_result = negaflow::output::export_working_to_srgb16_png(
        image,
        alpha_destination);
    expect(
        alpha_result.status ==
                negaflow::output::WicPngExportStatus::working_conversion_failed &&
            alpha_result.conversion_status ==
                negaflow::output::WorkingToSrgb16Status::non_opaque_alpha,
        "alpha is rejected before staging");
    expect(!std::filesystem::exists(alpha_destination), "alpha rejection creates no output");

    negaflow::output::WicPngExportLimits limits{};
    limits.conversion.max_encoded_pixel_bytes = 35U;
    const std::filesystem::path budget_destination = root / L"budget-rejected.png";
    const auto budget_result = negaflow::output::export_working_to_srgb16_png(
        make_image(),
        budget_destination,
        limits);
    expect(
        budget_result.status ==
                negaflow::output::WicPngExportStatus::working_conversion_failed &&
            budget_result.conversion_status ==
                negaflow::output::WorkingToSrgb16Status::memory_limit_exceeded,
        "pixel budget is enforced before staging");
    expect(!std::filesystem::exists(budget_destination), "budget rejection creates no output");
    expect(!has_staging_file(root), "preflight failures leave no staging file");
}

void test_failed_verification_discards_staging(const std::filesystem::path& root) {
    negaflow::output::WicPngExportLimits limits{};
    limits.max_artifact_bytes = 64U;
    const std::filesystem::path destination = root / L"artifact-limit.png";
    const auto result = negaflow::output::export_working_to_srgb16_png(
        make_image(),
        destination,
        limits);
    if (result.status !=
        negaflow::output::WicPngExportStatus::structure_verification_failed) {
        report_failure(result);
    }
    expect(
        result.status ==
            negaflow::output::WicPngExportStatus::structure_verification_failed,
        "artifact size limit fails readback verification");
    expect(!std::filesystem::exists(destination), "failed verification is not published");
    expect(!has_staging_file(root), "failed verification removes staging file");
    expect(result.cleanup_error_code == 0U, "staging cleanup succeeds");

    limits = {};
    limits.readback_buffer_bytes = 17U;
    const std::filesystem::path readback_destination = root / L"readback-limit.png";
    const auto readback_result = negaflow::output::export_working_to_srgb16_png(
        make_image(),
        readback_destination,
        limits);
    if (readback_result.status != negaflow::output::WicPngExportStatus::readback_failed) {
        report_failure(readback_result);
    }
    expect(
        readback_result.status == negaflow::output::WicPngExportStatus::readback_failed,
        "readback budget must hold at least one complete row");
    expect(
        !std::filesystem::exists(readback_destination),
        "readback budget failure is not published");
    expect(!has_staging_file(root), "readback budget failure removes staging file");
}

void test_publish_race_preserves_winner(const std::filesystem::path& root) {
    const HRESULT apartment = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    expect(SUCCEEDED(apartment), "COM apartment initializes for atomic publish test");
    const std::filesystem::path destination = root / L"publish-race.png";
    std::unique_ptr<negaflow::output::detail::AtomicOutputFile> output{};
    std::uint32_t native_error = 0U;
    const auto create_status = negaflow::output::detail::AtomicOutputFile::create(
        destination,
        output,
        native_error);
    expect(
        create_status == negaflow::output::detail::AtomicOutputStatus::ok &&
            output != nullptr,
        "atomic staging file is created with CREATE_NEW");
    constexpr char staged[] = "stage";
    ULONG bytes_written = 0U;
    HRESULT write_status = E_FAIL;
    if (output != nullptr) {
        write_status = output->stream()->Write(
            staged,
            static_cast<ULONG>(sizeof(staged) - 1U),
            &bytes_written);
        const auto flush_status = output->close_and_flush(native_error);
        expect(
            SUCCEEDED(write_status) && bytes_written == sizeof(staged) - 1U &&
                flush_status == negaflow::output::detail::AtomicOutputStatus::ok,
            "staging bytes are flushed before publish");
    }
    {
        std::ofstream winner(destination, std::ios::binary | std::ios::trunc);
        winner << "race-winner";
    }
    if (output != nullptr) {
        const auto publish_status = output->publish(sizeof(staged) - 1U, native_error);
        expect(
            publish_status == negaflow::output::detail::AtomicOutputStatus::destination_exists,
            "destination created during encode wins the publish race");
        output->discard(native_error);
    }
    expect(read_file(destination) == "race-winner", "publish race never overwrites winner");
    expect(!has_staging_file(root), "publish race cleanup removes staging file");
    if (apartment == S_OK || apartment == S_FALSE) {
        CoUninitialize();
    }
}

}  // namespace

int main() {
    const TempDirectory temporary{};
    test_round_trip_and_publish(temporary.path());
    test_existing_destination_is_preserved(temporary.path());
    test_preflight_failures_leave_no_file(temporary.path());
    test_failed_verification_discards_staging(temporary.path());
    test_publish_race_preserves_winner(temporary.path());
    if (failures != 0) {
        std::cerr << failures << " WIC PNG export test(s) failed\n";
        return 1;
    }
    std::cout << "WIC PNG export tests passed\n";
    return 0;
}
