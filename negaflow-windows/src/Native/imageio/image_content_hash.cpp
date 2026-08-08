#include "negaflow/imageio/image_content_hash.h"

#include <Windows.h>
#include <bcrypt.h>

#include <algorithm>
#include <cstddef>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::imageio {
namespace {

constexpr std::uint32_t minimum_read_buffer_bytes = 64U * 1024U;
constexpr std::uint32_t maximum_read_buffer_bytes = 64U * 1024U * 1024U;

class FileHandle final {
public:
    explicit FileHandle(const HANDLE value) noexcept : value_(value) {}
    FileHandle(const FileHandle&) = delete;
    FileHandle& operator=(const FileHandle&) = delete;

    ~FileHandle() {
        if (value_ != INVALID_HANDLE_VALUE) {
            static_cast<void>(CloseHandle(value_));
        }
    }

    [[nodiscard]] HANDLE get() const noexcept { return value_; }

private:
    HANDLE value_{INVALID_HANDLE_VALUE};
};

class HashHandle final {
public:
    HashHandle() noexcept = default;
    HashHandle(const HashHandle&) = delete;
    HashHandle& operator=(const HashHandle&) = delete;

    ~HashHandle() {
        if (value_ != nullptr) {
            static_cast<void>(BCryptDestroyHash(value_));
        }
    }

    [[nodiscard]] BCRYPT_HASH_HANDLE* put() noexcept { return &value_; }
    [[nodiscard]] BCRYPT_HASH_HANDLE get() const noexcept { return value_; }

private:
    BCRYPT_HASH_HANDLE value_{nullptr};
};

[[nodiscard]] bool nt_success(const NTSTATUS status) noexcept {
    return status >= 0;
}

[[nodiscard]] std::uint64_t file_size_bytes(
    const BY_HANDLE_FILE_INFORMATION& info) noexcept {
    return (static_cast<std::uint64_t>(info.nFileSizeHigh) << 32U) |
           static_cast<std::uint64_t>(info.nFileSizeLow);
}

[[nodiscard]] bool same_file_state(
    const BY_HANDLE_FILE_INFORMATION& before,
    const BY_HANDLE_FILE_INFORMATION& after) noexcept {
    return before.dwVolumeSerialNumber == after.dwVolumeSerialNumber &&
           before.nFileIndexHigh == after.nFileIndexHigh &&
           before.nFileIndexLow == after.nFileIndexLow &&
           before.nFileSizeHigh == after.nFileSizeHigh &&
           before.nFileSizeLow == after.nFileSizeLow &&
           before.ftLastWriteTime.dwHighDateTime == after.ftLastWriteTime.dwHighDateTime &&
           before.ftLastWriteTime.dwLowDateTime == after.ftLastWriteTime.dwLowDateTime;
}

void report_progress(
    const ImageContentHashControl& control,
    const std::uint64_t completed_bytes,
    const std::uint64_t total_bytes) noexcept {
    if (control.progress_observer != nullptr) {
        control.progress_observer->report({completed_bytes, total_bytes});
    }
}

}  // namespace

ImageContentHashResult hash_image_content(
    const std::filesystem::path& path,
    const ImageContentHashControl& control) noexcept {
    ImageContentHashResult result{};
    if (control.mode == ImageContentHashMode::off) {
        return result;
    }
    if (control.mode != ImageContentHashMode::sha256 || path.empty() ||
        control.read_buffer_bytes < minimum_read_buffer_bytes ||
        control.read_buffer_bytes > maximum_read_buffer_bytes) {
        result.status = ImageContentHashStatus::invalid_argument;
        return result;
    }
    if (control.stop_token.stop_requested()) {
        result.status = ImageContentHashStatus::cancelled;
        return result;
    }

    const HANDLE raw_file = CreateFileW(
        path.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
        nullptr);
    if (raw_file == INVALID_HANDLE_VALUE) {
        result.status = ImageContentHashStatus::open_failed;
        result.native_error_code = static_cast<std::uint32_t>(GetLastError());
        return result;
    }
    const FileHandle file{raw_file};

    BY_HANDLE_FILE_INFORMATION before{};
    if (GetFileInformationByHandle(file.get(), &before) == FALSE) {
        result.status = ImageContentHashStatus::file_info_failed;
        result.native_error_code = static_cast<std::uint32_t>(GetLastError());
        return result;
    }
    if ((before.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0U ||
        GetFileType(file.get()) != FILE_TYPE_DISK) {
        result.status = ImageContentHashStatus::not_regular_file;
        return result;
    }
    result.file_bytes = file_size_bytes(before);

    HashHandle hash{};
    const NTSTATUS create_status = BCryptCreateHash(
        BCRYPT_SHA256_ALG_HANDLE,
        hash.put(),
        nullptr,
        0U,
        nullptr,
        0U,
        0U);
    if (!nt_success(create_status)) {
        result.status = ImageContentHashStatus::hash_failed;
        result.native_error_code = static_cast<std::uint32_t>(create_status);
        return result;
    }

    try {
        const std::uint64_t desired_buffer_bytes = std::min(
            static_cast<std::uint64_t>(control.read_buffer_bytes),
            std::max<std::uint64_t>(result.file_bytes, 1U));
        std::vector<std::uint8_t> buffer(static_cast<std::size_t>(desired_buffer_bytes));
        report_progress(control, 0U, result.file_bytes);

        while (result.bytes_hashed < result.file_bytes) {
            if (control.stop_token.stop_requested()) {
                result.status = ImageContentHashStatus::cancelled;
                return result;
            }

            const std::uint64_t remaining = result.file_bytes - result.bytes_hashed;
            const DWORD requested = static_cast<DWORD>(std::min<std::uint64_t>(
                remaining,
                static_cast<std::uint64_t>(buffer.size())));
            DWORD bytes_read = 0U;
            if (ReadFile(file.get(), buffer.data(), requested, &bytes_read, nullptr) == FALSE) {
                result.status = ImageContentHashStatus::read_failed;
                result.native_error_code = static_cast<std::uint32_t>(GetLastError());
                return result;
            }
            if (bytes_read == 0U || bytes_read > requested) {
                result.status = ImageContentHashStatus::read_failed;
                return result;
            }

            const NTSTATUS update_status =
                BCryptHashData(hash.get(), buffer.data(), bytes_read, 0U);
            if (!nt_success(update_status)) {
                result.status = ImageContentHashStatus::hash_failed;
                result.native_error_code = static_cast<std::uint32_t>(update_status);
                return result;
            }
            result.bytes_hashed += bytes_read;
            report_progress(control, result.bytes_hashed, result.file_bytes);
        }
    } catch (const std::bad_alloc&) {
        result.status = ImageContentHashStatus::allocation_failed;
        return result;
    }

    if (control.stop_token.stop_requested()) {
        result.status = ImageContentHashStatus::cancelled;
        return result;
    }

    BY_HANDLE_FILE_INFORMATION after{};
    if (GetFileInformationByHandle(file.get(), &after) == FALSE) {
        result.status = ImageContentHashStatus::file_info_failed;
        result.native_error_code = static_cast<std::uint32_t>(GetLastError());
        return result;
    }
    if (!same_file_state(before, after)) {
        result.status = ImageContentHashStatus::file_changed;
        return result;
    }

    const NTSTATUS finish_status = BCryptFinishHash(
        hash.get(),
        result.sha256.data(),
        static_cast<ULONG>(result.sha256.size()),
        0U);
    if (!nt_success(finish_status)) {
        result.sha256.fill(0U);
        result.status = ImageContentHashStatus::hash_failed;
        result.native_error_code = static_cast<std::uint32_t>(finish_status);
        return result;
    }

    result.status = ImageContentHashStatus::ok;
    return result;
}

std::string image_sha256_hex(const std::array<std::uint8_t, 32>& digest) {
    constexpr char digits[] = "0123456789abcdef";
    std::string result(digest.size() * 2U, '0');
    for (std::size_t index = 0U; index < digest.size(); ++index) {
        result[index * 2U] = digits[(digest[index] >> 4U) & 0x0fU];
        result[index * 2U + 1U] = digits[digest[index] & 0x0fU];
    }
    return result;
}

const char* image_content_hash_status_name(const ImageContentHashStatus status) noexcept {
    switch (status) {
        case ImageContentHashStatus::disabled:
            return "disabled";
        case ImageContentHashStatus::ok:
            return "ok";
        case ImageContentHashStatus::invalid_argument:
            return "invalid_argument";
        case ImageContentHashStatus::cancelled:
            return "cancelled";
        case ImageContentHashStatus::open_failed:
            return "open_failed";
        case ImageContentHashStatus::not_regular_file:
            return "not_regular_file";
        case ImageContentHashStatus::file_info_failed:
            return "file_info_failed";
        case ImageContentHashStatus::allocation_failed:
            return "allocation_failed";
        case ImageContentHashStatus::read_failed:
            return "read_failed";
        case ImageContentHashStatus::hash_failed:
            return "hash_failed";
        case ImageContentHashStatus::file_changed:
            return "file_changed";
    }
    return "unknown";
}

}  // namespace negaflow::imageio
