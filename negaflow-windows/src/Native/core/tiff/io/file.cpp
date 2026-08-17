#include "file.h"

#include "tiff/io/math.h"

#include <limits>

namespace negaflow::core::tiff_probe_detail {

ReadOnlyFile::~ReadOnlyFile() noexcept {
    if (handle_ != INVALID_HANDLE_VALUE) {
        CloseHandle(handle_);
    }
}

bool ReadOnlyFile::open(const std::filesystem::path& path) noexcept {
    handle_ = CreateFileW(
        path.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_DELETE,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_RANDOM_ACCESS,
        nullptr);
    if (handle_ == INVALID_HANDLE_VALUE) {
        return false;
    }

    LARGE_INTEGER size{};
    if (GetFileSizeEx(handle_, &size) == 0 || size.QuadPart < 0) {
        return false;
    }
    size_ = static_cast<std::uint64_t>(size.QuadPart);
    return true;
}

std::uint64_t ReadOnlyFile::size() const noexcept {
    return size_;
}

bool ReadOnlyFile::read(
    const std::uint64_t offset,
    std::uint8_t* const destination,
    const std::size_t byte_count) const noexcept {
    std::uint64_t end = 0;
    if (destination == nullptr ||
        byte_count > static_cast<std::size_t>(std::numeric_limits<DWORD>::max()) ||
        !checked_add(offset, static_cast<std::uint64_t>(byte_count), end) ||
        end > size_ || offset > static_cast<std::uint64_t>(std::numeric_limits<LONGLONG>::max())) {
        return false;
    }

    LARGE_INTEGER position{};
    position.QuadPart = static_cast<LONGLONG>(offset);
    if (SetFilePointerEx(handle_, position, nullptr, FILE_BEGIN) == 0) {
        return false;
    }

    DWORD bytes_read = 0;
    const DWORD requested = static_cast<DWORD>(byte_count);
    return ReadFile(handle_, destination, requested, &bytes_read, nullptr) != 0 &&
           bytes_read == requested;
}

}  // namespace negaflow::core::tiff_probe_detail
