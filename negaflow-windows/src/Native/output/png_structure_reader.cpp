#include "png_structure_reader.h"

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>

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

[[nodiscard]] std::uint32_t read_be_u32(const std::uint8_t* const bytes) noexcept {
    return (static_cast<std::uint32_t>(bytes[0]) << 24U) |
           (static_cast<std::uint32_t>(bytes[1]) << 16U) |
           (static_cast<std::uint32_t>(bytes[2]) << 8U) |
           static_cast<std::uint32_t>(bytes[3]);
}

[[nodiscard]] bool read_exact(
    const HANDLE file,
    std::uint8_t* const destination,
    const DWORD byte_count,
    std::uint32_t& native_error_code) noexcept {
    DWORD total = 0U;
    while (total < byte_count) {
        DWORD actual = 0U;
        if (ReadFile(file, destination + total, byte_count - total, &actual, nullptr) == FALSE) {
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

[[nodiscard]] bool skip_bytes(
    const HANDLE file,
    const std::uint64_t byte_count,
    std::uint32_t& native_error_code) noexcept {
    if (byte_count > static_cast<std::uint64_t>(std::numeric_limits<LONGLONG>::max())) {
        return false;
    }
    LARGE_INTEGER distance{};
    distance.QuadPart = static_cast<LONGLONG>(byte_count);
    if (SetFilePointerEx(file, distance, nullptr, FILE_CURRENT) == FALSE) {
        native_error_code = static_cast<std::uint32_t>(GetLastError());
        return false;
    }
    return true;
}

[[nodiscard]] bool chunk_type_is(
    const std::array<std::uint8_t, 4>& type,
    const char (&expected)[5]) noexcept {
    return std::memcmp(type.data(), expected, type.size()) == 0;
}

}  // namespace

PngStructureStatus inspect_png_structure(
    const std::filesystem::path& path,
    const std::uint64_t max_file_bytes,
    PngStructureInfo& info,
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
        return PngStructureStatus::open_failed;
    }
    const FileHandle file{raw_file};

    BY_HANDLE_FILE_INFORMATION file_info{};
    if (GetFileInformationByHandle(file.get(), &file_info) == FALSE) {
        native_error_code = static_cast<std::uint32_t>(GetLastError());
        return PngStructureStatus::read_failed;
    }
    if ((file_info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0U ||
        GetFileType(file.get()) != FILE_TYPE_DISK) {
        return PngStructureStatus::not_regular_file;
    }
    info.file_bytes = (static_cast<std::uint64_t>(file_info.nFileSizeHigh) << 32U) |
                      static_cast<std::uint64_t>(file_info.nFileSizeLow);
    constexpr std::uint64_t minimum_png_bytes = 8U + 12U + 13U + 12U;
    if (info.file_bytes < minimum_png_bytes || info.file_bytes > max_file_bytes) {
        return PngStructureStatus::size_invalid;
    }

    constexpr std::array<std::uint8_t, 8> signature{
        137U,
        80U,
        78U,
        71U,
        13U,
        10U,
        26U,
        10U,
    };
    std::array<std::uint8_t, 8> actual_signature{};
    if (!read_exact(
            file.get(),
            actual_signature.data(),
            static_cast<DWORD>(actual_signature.size()),
            native_error_code)) {
        return PngStructureStatus::read_failed;
    }
    if (actual_signature != signature) {
        return PngStructureStatus::invalid_signature;
    }

    std::uint64_t position = signature.size();
    std::uint32_t chunk_index = 0U;
    bool has_header = false;
    bool has_end = false;
    while (position < info.file_bytes) {
        if (chunk_index >= 65'536U) {
            return PngStructureStatus::malformed_chunk;
        }
        if (info.file_bytes - position < 12U) {
            return PngStructureStatus::malformed_chunk;
        }
        std::array<std::uint8_t, 8> chunk_header{};
        if (!read_exact(
                file.get(),
                chunk_header.data(),
                static_cast<DWORD>(chunk_header.size()),
                native_error_code)) {
            return PngStructureStatus::read_failed;
        }
        position += chunk_header.size();
        const std::uint32_t length = read_be_u32(chunk_header.data());
        std::array<std::uint8_t, 4> type{};
        std::copy_n(chunk_header.data() + 4U, type.size(), type.data());
        if (static_cast<std::uint64_t>(length) + 4U > info.file_bytes - position) {
            return PngStructureStatus::malformed_chunk;
        }

        if (chunk_type_is(type, "IHDR")) {
            if (chunk_index != 0U || has_header || length != 13U) {
                return PngStructureStatus::invalid_header;
            }
            std::array<std::uint8_t, 13> header{};
            if (!read_exact(
                    file.get(),
                    header.data(),
                    static_cast<DWORD>(header.size()),
                    native_error_code)) {
                return PngStructureStatus::read_failed;
            }
            position += header.size();
            info.width = read_be_u32(header.data());
            info.height = read_be_u32(header.data() + 4U);
            info.bit_depth = header[8];
            info.color_type = header[9];
            if (info.width == 0U || info.height == 0U || info.bit_depth != 16U ||
                info.color_type != 2U || header[10] != 0U || header[11] != 0U ||
                header[12] != 0U) {
                return PngStructureStatus::invalid_header;
            }
            has_header = true;
        } else {
            if (!has_header || has_end ||
                !skip_bytes(file.get(), length, native_error_code)) {
                return PngStructureStatus::malformed_chunk;
            }
            position += length;
            if (chunk_type_is(type, "iCCP")) {
                if (info.has_icc_profile || info.image_data_chunks != 0U || length == 0U) {
                    return PngStructureStatus::malformed_chunk;
                }
                info.has_icc_profile = true;
            } else if (chunk_type_is(type, "IDAT")) {
                ++info.image_data_chunks;
            } else if (chunk_type_is(type, "IEND")) {
                if (length != 0U || info.image_data_chunks == 0U) {
                    return PngStructureStatus::malformed_chunk;
                }
                has_end = true;
            }
        }

        std::array<std::uint8_t, 4> crc{};
        if (!read_exact(
                file.get(),
                crc.data(),
                static_cast<DWORD>(crc.size()),
                native_error_code)) {
            return PngStructureStatus::read_failed;
        }
        position += crc.size();
        ++chunk_index;
        if (has_end && position != info.file_bytes) {
            return PngStructureStatus::malformed_chunk;
        }
    }

    if (!has_header) {
        return PngStructureStatus::invalid_header;
    }
    if (!info.has_icc_profile) {
        return PngStructureStatus::missing_color_profile;
    }
    if (info.image_data_chunks == 0U) {
        return PngStructureStatus::missing_image_data;
    }
    return has_end ? PngStructureStatus::ok : PngStructureStatus::missing_end;
}

}  // namespace negaflow::output::detail
