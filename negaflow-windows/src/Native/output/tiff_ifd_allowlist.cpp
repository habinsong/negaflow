#include "tiff_ifd_allowlist.h"

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>

namespace negaflow::output::detail {
namespace {

class FileHandle final {
public:
    explicit FileHandle(const HANDLE handle) noexcept : handle_(handle) {}
    FileHandle(const FileHandle&) = delete;
    FileHandle& operator=(const FileHandle&) = delete;
    ~FileHandle() noexcept {
        if (handle_ != INVALID_HANDLE_VALUE) {
            static_cast<void>(CloseHandle(handle_));
        }
    }

    [[nodiscard]] HANDLE get() const noexcept { return handle_; }

private:
    HANDLE handle_{INVALID_HANDLE_VALUE};
};

enum class ByteOrder : std::uint8_t {
    little,
    big,
};

[[nodiscard]] std::uint16_t read_u16(
    const std::uint8_t* const bytes,
    const ByteOrder order) noexcept {
    if (order == ByteOrder::little) {
        return static_cast<std::uint16_t>(
            static_cast<std::uint16_t>(bytes[0]) |
            (static_cast<std::uint16_t>(bytes[1]) << 8U));
    }
    return static_cast<std::uint16_t>(
        (static_cast<std::uint16_t>(bytes[0]) << 8U) |
        static_cast<std::uint16_t>(bytes[1]));
}

[[nodiscard]] std::uint32_t read_u32(
    const std::uint8_t* const bytes,
    const ByteOrder order) noexcept {
    if (order == ByteOrder::little) {
        return static_cast<std::uint32_t>(bytes[0]) |
               (static_cast<std::uint32_t>(bytes[1]) << 8U) |
               (static_cast<std::uint32_t>(bytes[2]) << 16U) |
               (static_cast<std::uint32_t>(bytes[3]) << 24U);
    }
    return (static_cast<std::uint32_t>(bytes[0]) << 24U) |
           (static_cast<std::uint32_t>(bytes[1]) << 16U) |
           (static_cast<std::uint32_t>(bytes[2]) << 8U) |
           static_cast<std::uint32_t>(bytes[3]);
}

[[nodiscard]] bool read_exact_at(
    const HANDLE file,
    const std::uint64_t file_bytes,
    const std::uint64_t offset,
    std::uint8_t* const destination,
    const DWORD byte_count,
    std::uint32_t& native_error_code) noexcept {
    if (offset > file_bytes || byte_count > file_bytes - offset ||
        offset > static_cast<std::uint64_t>(MAXLONGLONG)) {
        return false;
    }
    LARGE_INTEGER position{};
    position.QuadPart = static_cast<LONGLONG>(offset);
    if (SetFilePointerEx(file, position, nullptr, FILE_BEGIN) == FALSE) {
        native_error_code = static_cast<std::uint32_t>(GetLastError());
        return false;
    }
    DWORD total = 0U;
    while (total < byte_count) {
        DWORD actual = 0U;
        if (ReadFile(
                file,
                destination + total,
                byte_count - total,
                &actual,
                nullptr) == FALSE) {
            native_error_code = static_cast<std::uint32_t>(GetLastError());
            return false;
        }
        if (actual == 0U) {
            return false;
        }
        total += actual;
    }
    return true;
}

[[nodiscard]] bool is_allowed_minimal_tag(const std::uint16_t tag) noexcept {
    // 271·272·305·306·315·33432·34665 는 내보내기 메타데이터 정책이 쓰는 태그다.
    // binary_search 로 찾으므로 **태그 번호 순서로** 둔다. 뒤에 그냥 붙이면
    // 조용히 못 찾는다.
    constexpr std::array<std::uint16_t, 26> allowed{
        254U,     // NewSubfileType
        256U,     // ImageWidth
        257U,     // ImageLength
        258U,     // BitsPerSample
        259U,     // Compression
        262U,     // PhotometricInterpretation
        266U,     // FillOrder
        271U,     // Make
        272U,     // Model
        273U,     // StripOffsets
        274U,     // Orientation
        277U,     // SamplesPerPixel
        278U,     // RowsPerStrip
        279U,     // StripByteCounts
        282U,     // XResolution
        283U,     // YResolution
        284U,     // PlanarConfiguration
        296U,     // ResolutionUnit
        305U,     // Software
        306U,     // DateTime
        315U,     // Artist
        317U,     // Predictor
        339U,     // SampleFormat
        33432U,   // Copyright
        34665U,   // ExifIFD
        34675U,   // ICCProfile
    };
    return std::binary_search(allowed.begin(), allowed.end(), tag);
}

}  // namespace

TiffIfdAllowlistStatus inspect_minimal_rgb_tiff_ifd(
    const std::filesystem::path& path,
    const std::uint64_t max_file_bytes,
    const std::uint32_t max_ifd_entries,
    TiffIfdAllowlistInfo& info,
    std::uint32_t& native_error_code) noexcept {
    info = {};
    native_error_code = 0U;
    const HANDLE raw_file = CreateFileW(
        path.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
        nullptr);
    if (raw_file == INVALID_HANDLE_VALUE) {
        native_error_code = static_cast<std::uint32_t>(GetLastError());
        return TiffIfdAllowlistStatus::open_failed;
    }
    const FileHandle file{raw_file};

    BY_HANDLE_FILE_INFORMATION file_info{};
    if (GetFileInformationByHandle(file.get(), &file_info) == FALSE) {
        native_error_code = static_cast<std::uint32_t>(GetLastError());
        return TiffIfdAllowlistStatus::read_failed;
    }
    if ((file_info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0U ||
        GetFileType(file.get()) != FILE_TYPE_DISK) {
        return TiffIfdAllowlistStatus::not_regular_file;
    }
    info.file_bytes = (static_cast<std::uint64_t>(file_info.nFileSizeHigh) << 32U) |
                      static_cast<std::uint64_t>(file_info.nFileSizeLow);
    if (info.file_bytes < 8U || info.file_bytes > max_file_bytes) {
        return TiffIfdAllowlistStatus::size_invalid;
    }

    std::array<std::uint8_t, 8> header{};
    if (!read_exact_at(
            file.get(),
            info.file_bytes,
            0U,
            header.data(),
            static_cast<DWORD>(header.size()),
            native_error_code)) {
        return TiffIfdAllowlistStatus::read_failed;
    }
    ByteOrder order{};
    if (header[0] == 0x49U && header[1] == 0x49U) {
        order = ByteOrder::little;
    } else if (header[0] == 0x4dU && header[1] == 0x4dU) {
        order = ByteOrder::big;
    } else {
        return TiffIfdAllowlistStatus::invalid_header;
    }
    if (read_u16(header.data() + 2U, order) != 42U) {
        return TiffIfdAllowlistStatus::invalid_header;
    }
    const std::uint64_t ifd_offset = read_u32(header.data() + 4U, order);
    std::array<std::uint8_t, 2> count_bytes{};
    if (!read_exact_at(
            file.get(),
            info.file_bytes,
            ifd_offset,
            count_bytes.data(),
            static_cast<DWORD>(count_bytes.size()),
            native_error_code)) {
        return TiffIfdAllowlistStatus::invalid_ifd;
    }
    const std::uint32_t entry_count = read_u16(count_bytes.data(), order);
    if (entry_count > max_ifd_entries || entry_count > info.tag_ids.size()) {
        return TiffIfdAllowlistStatus::entry_limit_exceeded;
    }
    const std::uint64_t entries_bytes = static_cast<std::uint64_t>(entry_count) * 12U;
    if (ifd_offset > info.file_bytes || info.file_bytes - ifd_offset < 2U ||
        entries_bytes + 4U > info.file_bytes - ifd_offset - 2U) {
        return TiffIfdAllowlistStatus::invalid_ifd;
    }

    for (std::uint32_t index = 0U; index < entry_count; ++index) {
        std::array<std::uint8_t, 12> entry{};
        const std::uint64_t entry_offset = ifd_offset + 2U + index * entry.size();
        if (!read_exact_at(
                file.get(),
                info.file_bytes,
                entry_offset,
                entry.data(),
                static_cast<DWORD>(entry.size()),
                native_error_code)) {
            return TiffIfdAllowlistStatus::read_failed;
        }
        const std::uint16_t tag = read_u16(entry.data(), order);
        if (std::find(
                info.tag_ids.begin(),
                info.tag_ids.begin() + static_cast<std::ptrdiff_t>(info.tag_count),
                tag) != info.tag_ids.begin() +
                            static_cast<std::ptrdiff_t>(info.tag_count)) {
            return TiffIfdAllowlistStatus::duplicate_tag;
        }
        info.tag_ids[info.tag_count++] = tag;
        if (!is_allowed_minimal_tag(tag)) {
            info.unexpected_tag = tag;
            return TiffIfdAllowlistStatus::unexpected_tag;
        }
        if (tag == 34675U) {
            info.has_color_profile = true;
        }
    }
    if (!info.has_color_profile) {
        return TiffIfdAllowlistStatus::missing_color_profile;
    }
    return TiffIfdAllowlistStatus::ok;
}

}  // namespace negaflow::output::detail
