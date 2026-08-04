#include "negaflow/imageio/image_file_observation.h"

#include <Windows.h>

namespace negaflow::imageio {
namespace {

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

[[nodiscard]] std::uint64_t combine_u32(
    const std::uint32_t high,
    const std::uint32_t low) noexcept {
    return (static_cast<std::uint64_t>(high) << 32U) |
           static_cast<std::uint64_t>(low);
}

}  // namespace

ImageFileObservationResult observe_image_file(
    const std::filesystem::path& path) noexcept {
    ImageFileObservationResult result{};
    if (path.empty()) {
        return result;
    }

    const HANDLE raw_file = CreateFileW(
        path.c_str(),
        FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);
    if (raw_file == INVALID_HANDLE_VALUE) {
        result.status = ImageFileObservationStatus::open_failed;
        result.native_error_code = static_cast<std::uint32_t>(GetLastError());
        return result;
    }
    const FileHandle file{raw_file};

    BY_HANDLE_FILE_INFORMATION info{};
    if (GetFileInformationByHandle(file.get(), &info) == FALSE) {
        result.status = ImageFileObservationStatus::file_info_failed;
        result.native_error_code = static_cast<std::uint32_t>(GetLastError());
        return result;
    }
    if ((info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0U ||
        GetFileType(file.get()) != FILE_TYPE_DISK) {
        result.status = ImageFileObservationStatus::not_regular_file;
        return result;
    }

    result.observation.volume_serial_number = info.dwVolumeSerialNumber;
    result.observation.file_index = combine_u32(info.nFileIndexHigh, info.nFileIndexLow);
    result.observation.file_bytes = combine_u32(info.nFileSizeHigh, info.nFileSizeLow);
    result.observation.last_write_ticks = combine_u32(
        info.ftLastWriteTime.dwHighDateTime,
        info.ftLastWriteTime.dwLowDateTime);
    result.status = ImageFileObservationStatus::ok;
    return result;
}

bool same_image_file_observation(
    const ImageFileObservation& left,
    const ImageFileObservation& right) noexcept {
    return left.volume_serial_number == right.volume_serial_number &&
           left.file_index == right.file_index &&
           left.file_bytes == right.file_bytes &&
           left.last_write_ticks == right.last_write_ticks;
}

const char* image_file_observation_status_name(
    const ImageFileObservationStatus status) noexcept {
    switch (status) {
        case ImageFileObservationStatus::ok:
            return "ok";
        case ImageFileObservationStatus::invalid_argument:
            return "invalid_argument";
        case ImageFileObservationStatus::open_failed:
            return "open_failed";
        case ImageFileObservationStatus::not_regular_file:
            return "not_regular_file";
        case ImageFileObservationStatus::file_info_failed:
            return "file_info_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imageio
