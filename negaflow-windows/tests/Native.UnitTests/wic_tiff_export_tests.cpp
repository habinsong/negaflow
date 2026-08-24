#include "negaflow/output/wic_tiff_export.h"
#include "negaflow/core/tiff_probe.h"
#include "export_metadata_rules.h"
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
    negaflow::output::WicTiffExportLimits limits{};
    // 인코더가 쓴 화소가 의도한 화소와 같다는 증명은 여기서 듭니다 —
    // 내보내기 경로는 macOS 처럼 이 대조를 하지 않습니다.
    limits.verify_pixel_readback = true;
    limits.write_buffer_bytes = 18U;
    limits.readback_buffer_bytes = 18U;
    const auto result = negaflow::output::export_working_to_srgb16_tiff(
        make_image(),
        destination,
        limits);
    report_failure(result);
    expect(
        result.status == negaflow::output::WicTiffExportStatus::ok,
        "16-bit TIFF export succeeds with one-row write and readback buffers");
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

void test_linear_round_trip_and_publish(const std::filesystem::path& root) {
    const std::filesystem::path destination = root / L"linear-round-trip.tif";
    negaflow::output::WicTiffExportLimits limits{};
    limits.verify_pixel_readback = true;
    limits.write_buffer_bytes = 18U;
    limits.readback_buffer_bytes = 18U;
    const auto result = negaflow::output::export_working_to_linear16_tiff(
        make_image(),
        destination,
        limits);
    report_failure(result);
    const auto probe = negaflow::core::probe_tiff_file(destination);
    expect(
        result.status == negaflow::output::WicTiffExportStatus::ok &&
            result.info.encoded_pixel_bytes == 36U && result.info.compression == 1U &&
            result.info.color_profile_bytes > 0U && result.info.pixels_verified &&
            result.info.profile_verified && result.info.published,
        "linear RGB16 TIFF publishes with exact pixel and profile readback");
    expect(
        probe.status == negaflow::core::TiffProbeStatus::ok &&
            probe.info.bits_per_sample_count == 3U && probe.info.bits_per_sample[0] == 16U &&
            probe.info.bits_per_sample[1] == 16U && probe.info.bits_per_sample[2] == 16U &&
            probe.info.samples_per_pixel == 3U && probe.info.extra_samples_count == 0U &&
            probe.info.compression == 1U && probe.info.icc_profile_bytes > 0U,
        "linear bake TIFF is opaque RGB16, uncompressed and ICC-tagged");
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
        // 인코더가 쓴 화소가 의도한 화소와 같다는 증명은 여기서 듭니다 —
        // 내보내기 경로는 macOS 처럼 이 대조를 하지 않습니다.
        limits.verify_pixel_readback = true;
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
    const std::filesystem::path alpha_destination = root / L"alpha-preserved.tif";
    negaflow::output::WicTiffExportLimits alpha_limits{};
    // 인코더가 쓴 화소가 의도한 화소와 같다는 증명은 여기서 듭니다 —
    // 내보내기 경로는 macOS 처럼 이 대조를 하지 않습니다.
    alpha_limits.verify_pixel_readback = true;
    alpha_limits.conversion.preserve_alpha = true;
    const auto alpha_result = negaflow::output::export_working_to_srgb16_tiff(
        image, alpha_destination, alpha_limits);
    report_failure(alpha_result);
    expect(
        alpha_result.status == negaflow::output::WicTiffExportStatus::ok &&
            alpha_result.info.encoded_pixel_bytes == 48U && alpha_result.info.structure_verified &&
            alpha_result.info.pixels_verified && alpha_result.info.published,
        "16-bit TIFF preserves a non-opaque alpha channel through structure and readback");
    const auto alpha_probe = negaflow::core::probe_tiff_file(alpha_destination);
    expect(
        alpha_probe.status == negaflow::core::TiffProbeStatus::ok &&
            alpha_probe.info.samples_per_pixel == 4U && alpha_probe.info.extra_samples_count == 1U &&
            alpha_probe.info.extra_samples[0] == 2U,
        "published TIFF declares one unassociated ExtraSamples alpha channel");

    alpha_limits.bits_per_sample = 8U;
    const std::filesystem::path alpha8_destination = root / L"alpha-preserved-8.tif";
    const auto alpha8_result = negaflow::output::export_working_to_srgb16_tiff(
        image, alpha8_destination, alpha_limits);
    report_failure(alpha8_result);
    expect(
        alpha8_result.status == negaflow::output::WicTiffExportStatus::ok &&
            alpha8_result.info.encoded_pixel_bytes == 24U && alpha8_result.info.structure_verified &&
            alpha8_result.info.pixels_verified && alpha8_result.info.published,
        "8-bit TIFF preserves a non-opaque alpha channel through BGRA WIC structure and readback");
    const auto alpha8_probe = negaflow::core::probe_tiff_file(alpha8_destination);
    expect(
        alpha8_probe.status == negaflow::core::TiffProbeStatus::ok &&
            alpha8_probe.info.samples_per_pixel == 4U && alpha8_probe.info.bits_per_sample_count == 4U &&
            alpha8_probe.info.bits_per_sample[3] == 8U && alpha8_probe.info.extra_samples_count == 1U &&
            alpha8_probe.info.extra_samples[0] == 2U,
        "8-bit TIFF declares one unassociated ExtraSamples alpha channel");

    negaflow::output::WicTiffExportLimits limits{};
    // 인코더가 쓴 화소가 의도한 화소와 같다는 증명은 여기서 듭니다 —
    // 내보내기 경로는 macOS 처럼 이 대조를 하지 않습니다.
    limits.verify_pixel_readback = true;
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

// 이 목록은 "우리가 쓴 것만 들어 있다" 를 지킨다. 내보내기 메타데이터 정책이 쓰는 태그는
// 허용되지만, 우리가 절대 쓰지 않는 것 — 특히 위치 — 은 여전히 게시를 막아야 한다.
void test_metadata_allowlist_rejects_descriptive_tag(const std::filesystem::path& root) {
    const std::filesystem::path path = root / L"unexpected-metadata.tif";
    constexpr std::array<std::uint8_t, 26> bytes{
        0x49U, 0x49U, 0x2aU, 0x00U, 0x08U, 0x00U, 0x00U, 0x00U,
        0x01U, 0x00U,
        0x25U, 0x88U, 0x04U, 0x00U, 0x01U, 0x00U, 0x00U, 0x00U,
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
        false,
        info,
        native_error);
    expect(
        status == negaflow::output::detail::TiffIfdAllowlistStatus::unexpected_tag &&
            info.unexpected_tag == 34853U,
        "metadata allowlist rejects a GPS IFD");

    // 사용자가 원본 메타데이터를 실으라고 고른 경우 GPS 태그 자체는 더 이상 거절 사유가
    // 아니다. 그렇다고 검사가 없어지지는 않는다 — 이 픽스처는 색 프로파일이 없고, 그것은
    // 정책과 무관하게 여전히 걸린다.
    negaflow::output::detail::TiffIfdAllowlistInfo carried{};
    const auto carried_status = negaflow::output::detail::inspect_minimal_rgb_tiff_ifd(
        path,
        1U * 1024U * 1024U,
        128U,
        true,
        carried,
        native_error);
    expect(
        carried_status ==
                negaflow::output::detail::TiffIfdAllowlistStatus::missing_color_profile &&
            carried.unexpected_tag == 0U && carried.tag_count == 1U,
        "carrying source metadata stops rejecting GPS but still demands a profile");
}

/// 원본 메타데이터를 정책대로 거르는 판정. 이 규칙은 실물 파일 없이 이름만 보고 정해지므로
/// 여기서 표로 못 박는다 — 실제 파일 왕복은 셸 하네스가 따로 본다.
void test_source_metadata_policy_rules() {
    using negaflow::output::ExportMetadataPolicy;
    using negaflow::output::detail::copies_source_leaf;
    using negaflow::output::detail::enters_source_block;
    using negaflow::output::detail::source_block_of;
    using Block = negaflow::output::detail::SourceMetadataBlock;

    // WIC 는 하위 덩이를 가리키는 태그 번호로 열거한다. 이름으로 찾으면 하나도 못 찾는다.
    expect(source_block_of(L"/{ushort=34665}") == Block::exif, "34665 is the Exif block");
    expect(source_block_of(L"/{ushort=34853}") == Block::gps, "34853 is the GPS block");
    expect(source_block_of(L"/{ushort=33723}") == Block::iptc, "33723 is the IPTC block");
    expect(source_block_of(L"/exif") == Block::exif, "the JPEG spelling still resolves");
    expect(source_block_of(L"/{ushort=315}") == Block::other, "Artist is not a block");

    // 장소는 `all` 에서만 남는다. 촬영 기록은 저작권만 남기는 정책에서 빠진다.
    expect(
        enters_source_block(ExportMetadataPolicy::all, Block::gps) &&
            !enters_source_block(ExportMetadataPolicy::remove_location, Block::gps) &&
            !enters_source_block(ExportMetadataPolicy::copyright_only, Block::gps),
        "GPS is entered only by the policy that carries everything");
    expect(
        enters_source_block(ExportMetadataPolicy::remove_location, Block::exif) &&
            !enters_source_block(ExportMetadataPolicy::copyright_only, Block::exif),
        "Exif is entered by every policy but copyright only");

    // 픽셀과 어긋날 수 있는 구조 태그는 어느 정책에서도 옮기지 않는다.
    constexpr std::array<std::uint16_t, 5> structural_tags{256U, 273U, 274U, 279U, 34675U};
    for (const std::uint16_t structural : structural_tags) {
        const std::wstring name = L"/{ushort=" + std::to_wstring(structural) + L"}";
        expect(
            !copies_source_leaf(ExportMetadataPolicy::all, Block::root, name),
            "structural tags never travel");
    }
    expect(
        copies_source_leaf(ExportMetadataPolicy::all, Block::root, L"/{ushort=270}") &&
            !copies_source_leaf(
                ExportMetadataPolicy::copyright_only, Block::root, L"/{ushort=270}") &&
            copies_source_leaf(
                ExportMetadataPolicy::copyright_only, Block::root, L"/{ushort=315}") &&
            copies_source_leaf(
                ExportMetadataPolicy::copyright_only, Block::root, L"/{ushort=33432}"),
        "copyright only keeps Artist and Copyright and drops the description");

    // IPTC 항목은 `/{str=By-line}` 처럼 나온다. 껍데기를 못 벗기면 어떤 이름과도 안 맞는다.
    expect(
        !copies_source_leaf(
            ExportMetadataPolicy::remove_location, Block::iptc, L"/{str=City}") &&
            !copies_source_leaf(
                ExportMetadataPolicy::remove_location, Block::iptc, L"/{str=Sub-location}") &&
            !copies_source_leaf(
                ExportMetadataPolicy::remove_location,
                Block::iptc,
                L"/{str=Country/Primary Location Name}"),
        "removing location drops the place fields whatever their spelling");
    expect(
        copies_source_leaf(
            ExportMetadataPolicy::remove_location, Block::iptc, L"/{str=Headline}") &&
            copies_source_leaf(
                ExportMetadataPolicy::remove_location, Block::iptc, L"/{str=By-line}"),
        "removing location keeps what is not a place");
    expect(
        copies_source_leaf(
            ExportMetadataPolicy::copyright_only, Block::iptc, L"/{str=Copyright Notice}") &&
            copies_source_leaf(
                ExportMetadataPolicy::copyright_only, Block::iptc, L"/{str=By-line}") &&
            !copies_source_leaf(
                ExportMetadataPolicy::copyright_only, Block::iptc, L"/{str=Headline}"),
        "copyright only keeps the byline and the notice");
}

}  // namespace

int main() {
    const TempDirectory temporary{};
    test_source_metadata_policy_rules();
    test_round_trip_and_publish(temporary.path());
    test_linear_round_trip_and_publish(temporary.path());
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
