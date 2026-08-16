#include "negaflow/output/wic_png_export.h"
#include "negaflow/imageio/wic_standard_image_decoder.h"
#include "negaflow/imaging/scanner_to_working.h"
#include "atomic_output_file.h"

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>

namespace {

int failures = 0;
using Microsoft::WRL::ComPtr;

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

[[nodiscard]] bool inject_jpeg_exif_orientation(
    const std::filesystem::path& path,
    const std::uint16_t orientation) {
    if (orientation < 1U || orientation > 8U) {
        return false;
    }
    std::ifstream input(path, std::ios::binary);
    std::vector<std::uint8_t> jpeg{
        std::istreambuf_iterator<char>{input},
        std::istreambuf_iterator<char>{},
    };
    if (!input.good() && !input.eof()) {
        return false;
    }
    if (jpeg.size() < 2U || jpeg[0] != 0xFFU || jpeg[1] != 0xD8U) {
        return false;
    }
    const std::array<std::uint8_t, 36U> app1{{
        0xFFU, 0xE1U, 0x00U, 0x22U,
        'E', 'x', 'i', 'f', 0U, 0U,
        'I', 'I', 0x2AU, 0U, 0x08U, 0U, 0U, 0U,
        0x01U, 0U,
        0x12U, 0x01U, 0x03U, 0U, 0x01U, 0U, 0U, 0U,
        static_cast<std::uint8_t>(orientation),
        static_cast<std::uint8_t>(orientation >> 8U), 0U, 0U,
        0U, 0U, 0U, 0U,
    }};
    std::vector<std::uint8_t> output{};
    output.reserve(jpeg.size() + app1.size());
    output.insert(output.end(), jpeg.begin(), jpeg.begin() + 2);
    output.insert(output.end(), app1.begin(), app1.end());
    output.insert(output.end(), jpeg.begin() + 2, jpeg.end());
    std::ofstream destination(path, std::ios::binary | std::ios::trunc);
    destination.write(
        reinterpret_cast<const char*>(output.data()),
        static_cast<std::streamsize>(output.size()));
    return destination.good();
}

void test_round_trip_and_publish(const std::filesystem::path& root) {
    const std::filesystem::path destination = root / L"round-trip.png";
    negaflow::output::WicPngExportLimits limits{};
    limits.write_buffer_bytes = 18U;
    limits.readback_buffer_bytes = 18U;
    const auto result = negaflow::output::export_working_to_srgb16_png(
        make_image(),
        destination,
        limits);
    report_failure(result);
    expect(
        result.status == negaflow::output::WicPngExportStatus::ok,
        "16-bit PNG export succeeds with one-row write and readback buffers");
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

    const auto decoded = negaflow::imageio::decode_standard_image_with_wic(destination);
    expect(
        decoded.status == negaflow::imageio::WicStandardImageDecodeStatus::ok &&
            decoded.image.width == 3U && decoded.image.height == 2U &&
            decoded.image.layout == negaflow::imageio::DecodedPixelLayout::rgba16 &&
            !decoded.image.icc_profile.empty(),
        "published PNG decodes as standard image input with its profile");
    const auto working = negaflow::imaging::convert_scanner_to_working(decoded.image);
    expect(
        working.status == negaflow::imaging::ScannerToWorkingStatus::ok &&
            working.info.transform ==
                negaflow::imaging::ScannerWorkingTransform::embedded_icc_windows_icm_srgb16 &&
            working.image.pixels.size() == 6U,
        "standard PNG reaches the linear working image");
}

void test_jpeg_standard_image_decode(const std::filesystem::path& root) {
    const HRESULT apartment = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    expect(SUCCEEDED(apartment), "COM apartment initializes for JPEG input test");
    const std::filesystem::path destination = root / L"standard-input.jpg";
    const std::array<std::uint8_t, 18U> pixels{{
        24U, 72U, 220U, 220U, 72U, 24U,
        40U, 120U, 190U, 190U, 120U, 40U,
        80U, 160U, 150U, 150U, 160U, 80U,
    }};
    HRESULT status = E_FAIL;
    ComPtr<IWICImagingFactory> factory{};
    ComPtr<IWICStream> stream{};
    ComPtr<IWICBitmapEncoder> encoder{};
    ComPtr<IWICBitmapFrameEncode> frame{};
    if (SUCCEEDED(apartment)) {
        status = CoCreateInstance(
            CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
    }
    if (SUCCEEDED(status)) status = factory->CreateStream(&stream);
    if (SUCCEEDED(status)) status = stream->InitializeFromFilename(destination.c_str(), GENERIC_WRITE);
    if (SUCCEEDED(status)) status = factory->CreateEncoder(GUID_ContainerFormatJpeg, nullptr, &encoder);
    if (SUCCEEDED(status)) status = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
    if (SUCCEEDED(status)) status = encoder->CreateNewFrame(&frame, nullptr);
    if (SUCCEEDED(status)) status = frame->Initialize(nullptr);
    if (SUCCEEDED(status)) status = frame->SetSize(2U, 3U);
    WICPixelFormatGUID format = GUID_WICPixelFormat24bppBGR;
    if (SUCCEEDED(status)) status = frame->SetPixelFormat(&format);
    if (SUCCEEDED(status) && IsEqualGUID(format, GUID_WICPixelFormat24bppBGR) == FALSE) {
        status = E_FAIL;
    }
    if (SUCCEEDED(status)) {
        status = frame->WritePixels(3U, 6U, static_cast<UINT>(pixels.size()),
            const_cast<std::uint8_t*>(pixels.data()));
    }
    if (SUCCEEDED(status)) status = frame->Commit();
    if (SUCCEEDED(status)) status = encoder->Commit();
    expect(SUCCEEDED(status), "a small WIC JPEG fixture is encoded");
    factory.Reset();
    stream.Reset();
    encoder.Reset();
    frame.Reset();
    if (apartment == S_OK || apartment == S_FALSE) CoUninitialize();
    if (FAILED(status)) return;
    expect(inject_jpeg_exif_orientation(destination, 6U),
        "EXIF orientation metadata is injected into the JPEG fixture");

    const auto decoded = negaflow::imageio::decode_standard_image_with_wic(destination);
    expect(
        decoded.status == negaflow::imageio::WicStandardImageDecodeStatus::ok &&
            decoded.image.width == 3U && decoded.image.height == 2U &&
            decoded.image.layout == negaflow::imageio::DecodedPixelLayout::rgba16 &&
            decoded.image.icc_profile.empty() && decoded.info.exif_orientation == 6U &&
            decoded.info.orientation_applied,
        "an EXIF-oriented JPEG decodes as clockwise-oriented standard sRGB image input");
}

void test_dpi_metadata(const std::filesystem::path& root) {
    negaflow::output::WicPngExportLimits limits{};
    limits.output_dpi = 300U;
    const auto result = negaflow::output::export_working_to_srgb16_png(
        make_image(),
        root / L"dpi.png",
        limits);
    report_failure(result);
    expect(
        result.status == negaflow::output::WicPngExportStatus::ok &&
            result.info.output_dpi == 300U && result.info.resolution_verified &&
            result.info.structure_verified && result.info.pixels_verified &&
            result.info.profile_verified && result.info.published,
        "PNG DPI metadata round trips through WIC");
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
    const std::filesystem::path alpha_destination = root / L"alpha-preserved.png";
    negaflow::output::WicPngExportLimits alpha_limits{};
    alpha_limits.conversion.preserve_alpha = true;
    const auto alpha_result = negaflow::output::export_working_to_srgb16_png(
        image, alpha_destination, alpha_limits);
    report_failure(alpha_result);
    expect(
        alpha_result.status == negaflow::output::WicPngExportStatus::ok &&
            alpha_result.info.encoded_pixel_bytes == 48U && alpha_result.info.structure_verified &&
            alpha_result.info.pixels_verified && alpha_result.info.published,
        "16-bit PNG preserves a non-opaque alpha channel through structure and readback");
    const auto alpha_decoded = negaflow::imageio::decode_standard_image_with_wic(alpha_destination);
    expect(
        alpha_decoded.status == negaflow::imageio::WicStandardImageDecodeStatus::ok &&
            alpha_decoded.image.samples.size() >= 4U &&
            alpha_decoded.image.samples[3] == 32'768U,
        "published PNG stores the straight alpha sample without gamma conversion");

    alpha_limits.bits_per_sample = 8U;
    const std::filesystem::path alpha8_destination = root / L"alpha-preserved-8.png";
    const auto alpha8_result = negaflow::output::export_working_to_srgb16_png(
        image, alpha8_destination, alpha_limits);
    report_failure(alpha8_result);
    expect(
        alpha8_result.status == negaflow::output::WicPngExportStatus::ok &&
            alpha8_result.info.encoded_pixel_bytes == 24U && alpha8_result.info.structure_verified &&
            alpha8_result.info.pixels_verified && alpha8_result.info.published,
        "8-bit PNG preserves a non-opaque alpha channel through BGRA WIC structure and readback");
    const auto alpha8_decoded = negaflow::imageio::decode_standard_image_with_wic(alpha8_destination);
    expect(
        alpha8_decoded.status == negaflow::imageio::WicStandardImageDecodeStatus::ok &&
            alpha8_decoded.image.samples.size() >= 4U &&
            alpha8_decoded.image.samples[3] == 32'896U,
        "8-bit PNG expands the straight 128 alpha sample without gamma conversion");

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

    limits = {};
    limits.write_buffer_bytes = 17U;
    const std::filesystem::path write_destination = root / L"write-limit.png";
    const auto write_result = negaflow::output::export_working_to_srgb16_png(
        make_image(),
        write_destination,
        limits);
    if (write_result.status != negaflow::output::WicPngExportStatus::encode_failed) {
        report_failure(write_result);
    }
    expect(
        write_result.status == negaflow::output::WicPngExportStatus::encode_failed,
        "write budget must hold at least one complete row");
    expect(!std::filesystem::exists(write_destination), "write budget failure is not published");
    expect(!has_staging_file(root), "write budget failure removes staging file");
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
    test_dpi_metadata(temporary.path());
    test_jpeg_standard_image_decode(temporary.path());
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
