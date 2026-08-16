#include "negaflow/output/wic_tiff_export.h"

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <optional>
#include <string>
#include <system_error>
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
                (L"negaflow-task6-golden-" + std::to_wstring(GetCurrentProcessId()));
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
        error.clear();
        std::filesystem::create_directories(path_, error);
        expect(!error, "task6 temporary output directory is created");
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

[[nodiscard]] negaflow::imaging::WorkingImage make_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 64U;
    image.height = 64U;
    image.stride_pixels = image.width;
    image.pixels.assign(
        static_cast<std::size_t>(image.width) * image.height,
        {0.25F, 0.50F, 0.75F, 1.0F});
    return image;
}

struct TiffEntry final {
    std::uint16_t type{0U};
    std::uint32_t count{0U};
    std::vector<std::uint8_t> value{};
};

struct TiffIfd final {
    std::map<std::uint16_t, TiffEntry> entries{};
};

[[nodiscard]] std::uint16_t read_u16(
    const std::vector<std::uint8_t>& bytes,
    const std::size_t offset,
    const bool little_endian,
    bool& valid) {
    if (offset > bytes.size() || bytes.size() - offset < 2U) {
        valid = false;
        return 0U;
    }
    if (little_endian) {
        return static_cast<std::uint16_t>(bytes[offset]) |
               static_cast<std::uint16_t>(bytes[offset + 1U] << 8U);
    }
    return static_cast<std::uint16_t>(bytes[offset] << 8U) |
           static_cast<std::uint16_t>(bytes[offset + 1U]);
}

[[nodiscard]] std::uint32_t read_u32(
    const std::vector<std::uint8_t>& bytes,
    const std::size_t offset,
    const bool little_endian,
    bool& valid) {
    if (offset > bytes.size() || bytes.size() - offset < 4U) {
        valid = false;
        return 0U;
    }
    if (little_endian) {
        return static_cast<std::uint32_t>(bytes[offset]) |
               (static_cast<std::uint32_t>(bytes[offset + 1U]) << 8U) |
               (static_cast<std::uint32_t>(bytes[offset + 2U]) << 16U) |
               (static_cast<std::uint32_t>(bytes[offset + 3U]) << 24U);
    }
    return (static_cast<std::uint32_t>(bytes[offset]) << 24U) |
           (static_cast<std::uint32_t>(bytes[offset + 1U]) << 16U) |
           (static_cast<std::uint32_t>(bytes[offset + 2U]) << 8U) |
           static_cast<std::uint32_t>(bytes[offset + 3U]);
}

[[nodiscard]] std::optional<std::size_t> type_size(const std::uint16_t type) noexcept {
    switch (type) {
        case 1U:  // BYTE
        case 2U:  // ASCII
        case 6U:  // SBYTE
        case 7U:  // UNDEFINED
            return 1U;
        case 3U:  // SHORT
        case 8U:  // SSHORT
            return 2U;
        case 4U:  // LONG
        case 9U:  // SLONG
        case 11U: // FLOAT
            return 4U;
        case 5U:  // RATIONAL
        case 10U: // SRATIONAL
        case 12U: // DOUBLE
            return 8U;
    }
    return std::nullopt;
}

[[nodiscard]] TiffIfd read_root_ifd(const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    const std::vector<std::uint8_t> bytes{
        std::istreambuf_iterator<char>{input},
        std::istreambuf_iterator<char>{}};
    bool valid = bytes.size() >= 8U;
    const bool little_endian = valid && bytes[0] == 'I' && bytes[1] == 'I';
    valid = valid && (little_endian || (bytes[0] == 'M' && bytes[1] == 'M'));
    const std::uint16_t version = read_u16(bytes, 2U, little_endian, valid);
    const std::uint32_t ifd_offset = read_u32(bytes, 4U, little_endian, valid);
    valid = valid && version == 42U && ifd_offset <= bytes.size();
    const std::uint16_t entry_count = read_u16(bytes, ifd_offset, little_endian, valid);
    TiffIfd result{};
    for (std::uint16_t index = 0U; valid && index < entry_count; ++index) {
        const std::size_t entry = static_cast<std::size_t>(ifd_offset) + 2U +
            static_cast<std::size_t>(index) * 12U;
        const std::uint16_t tag = read_u16(bytes, entry, little_endian, valid);
        const std::uint16_t type = read_u16(bytes, entry + 2U, little_endian, valid);
        const std::uint32_t count = read_u32(bytes, entry + 4U, little_endian, valid);
        const std::optional<std::size_t> size = type_size(type);
        if (!size.has_value() || count > bytes.size() / *size) {
            valid = false;
            break;
        }
        const std::size_t value_bytes = static_cast<std::size_t>(count) * *size;
        const std::size_t value_offset = value_bytes <= 4U
            ? entry + 8U
            : static_cast<std::size_t>(read_u32(bytes, entry + 8U, little_endian, valid));
        if (value_offset > bytes.size() || bytes.size() - value_offset < value_bytes) {
            valid = false;
            break;
        }
        result.entries.emplace(
            tag,
            TiffEntry{
                type,
                count,
                std::vector<std::uint8_t>(
                    bytes.begin() + static_cast<std::ptrdiff_t>(value_offset),
                    bytes.begin() + static_cast<std::ptrdiff_t>(value_offset + value_bytes)),
            });
    }
    expect(valid, "published Task6 TIFF has a readable classic root IFD");
    return result;
}

[[nodiscard]] bool has(const TiffIfd& ifd, const std::uint16_t tag) noexcept {
    return ifd.entries.contains(tag);
}

[[nodiscard]] std::optional<std::string> ascii(const TiffIfd& ifd, const std::uint16_t tag) {
    const auto found = ifd.entries.find(tag);
    if (found == ifd.entries.end() || found->second.type != 2U || found->second.value.empty()) {
        return std::nullopt;
    }
    const auto terminator = std::find(
        found->second.value.begin(), found->second.value.end(), static_cast<std::uint8_t>(0U));
    return std::string(found->second.value.begin(), terminator);
}

struct Case final {
    negaflow::output::ExportMetadataPolicy policy;
    const wchar_t* output;
    bool carries_source_identity;
    bool carries_source_description;
    bool carries_exif;
    bool carries_iptc;
    bool carries_gps;
};

[[nodiscard]] negaflow::output::WicTiffExportLimits make_limits(
    const std::filesystem::path& source,
    const negaflow::output::ExportMetadataPolicy policy) {
    negaflow::output::WicTiffExportLimits limits{};
    limits.output_dpi = 2400U;
    limits.metadata_policy = policy;
    limits.metadata.make = L"Seiko Epson";
    limits.metadata.model = L"GT-X900";
    limits.metadata.software = L"negaflow golden harness";
    limits.metadata.film_type = L"colorNegative";
    limits.metadata.film_stock = L"Kodak Portra 400";
    limits.metadata.captured_at = L"2026:01:02 03:04:05";
    if (policy != negaflow::output::ExportMetadataPolicy::minimal) {
        limits.metadata.source_path = source.wstring();
    }
    return limits;
}

void verify_case(
    const std::filesystem::path& source,
    const TiffIfd& source_ifd,
    const TempDirectory& temporary,
    const Case& entry) {
    const std::filesystem::path destination = temporary.path() / entry.output;
    const auto result = negaflow::output::export_working_to_srgb16_tiff(
        make_image(), destination, make_limits(source, entry.policy));
    expect(
        result.status == negaflow::output::WicTiffExportStatus::ok &&
            result.info.metadata_verified && result.info.published,
        "Windows Task6 TIFF export and metadata verification succeed");
    if (result.status != negaflow::output::WicTiffExportStatus::ok) {
        std::cerr << "  status="
                  << negaflow::output::wic_tiff_export_status_name(result.status)
                  << " native=0x" << std::hex << result.native_error_code << std::dec << '\n';
        return;
    }
    const TiffIfd ifd = read_root_ifd(destination);
    const bool app_identity = has(ifd, 271U) && has(ifd, 272U) && has(ifd, 305U) &&
        has(ifd, 306U) && has(ifd, 34665U);
    expect(
        entry.policy == negaflow::output::ExportMetadataPolicy::copyright_only || app_identity,
        "Task6 policy writes the macOS equipment and EXIF metadata when permitted");
    expect(
        has(ifd, 315U) == entry.carries_source_identity &&
            has(ifd, 33432U) == entry.carries_source_identity,
        "Task6 policy preserves source Artist and Copyright only when permitted");
    if (entry.carries_source_identity) {
        expect(
            ascii(ifd, 315U) == ascii(source_ifd, 315U) &&
                ascii(ifd, 33432U) == ascii(source_ifd, 33432U),
            "Task6 policy preserves the source Artist and Copyright text values");
    }
    expect(
        has(ifd, 270U) == entry.carries_source_description,
        "Task6 policy preserves the source description only when permitted");
    if (entry.carries_source_description) {
        expect(
            ascii(ifd, 270U) == ascii(source_ifd, 270U),
            "Task6 policy preserves the source description text value");
    }
    expect(
        has(ifd, 34665U) == entry.carries_exif,
        "Task6 policy preserves an EXIF block only when permitted");
    expect(
        has(ifd, 33723U) == entry.carries_iptc,
        "Task6 policy preserves an IPTC block only when permitted");
    expect(
        has(ifd, 34853U) == entry.carries_gps,
        "Task6 policy preserves a GPS block only for all metadata");
}

void test_task6_goldens(const std::filesystem::path& root) {
    const std::filesystem::path source = root / L"policy-all.tif";
    expect(std::filesystem::is_regular_file(source), "Task6 macOS policy-all golden is available");
    if (!std::filesystem::is_regular_file(source)) {
        return;
    }
    const TiffIfd source_ifd = read_root_ifd(source);
    expect(
        ascii(source_ifd, 270U).has_value() && ascii(source_ifd, 315U).has_value() &&
            ascii(source_ifd, 33432U).has_value(),
        "Task6 macOS source exposes the description, Artist and Copyright text values");
    constexpr std::array<Case, 4U> cases{{
        {negaflow::output::ExportMetadataPolicy::minimal, L"minimal.tif", false, false, true, false, false},
        {negaflow::output::ExportMetadataPolicy::copyright_only, L"copyright.tif", true, false, false, true, false},
        {negaflow::output::ExportMetadataPolicy::remove_location, L"remove-location.tif", true, true, true, true, false},
        {negaflow::output::ExportMetadataPolicy::all, L"all.tif", true, true, true, true, true},
    }};
    const TempDirectory temporary{};
    for (const Case& entry : cases) {
        verify_case(source, source_ifd, temporary, entry);
    }
}

}  // namespace

int main(const int argc, char** argv) {
    expect(argc == 2, "task6 receives the macOS metadata golden directory");
    if (argc == 2) {
        test_task6_goldens(argv[1]);
    }
    return failures == 0 ? 0 : 1;
}
