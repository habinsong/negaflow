#include "negaflow/imageio/image_file_observation.h"

#include <Windows.h>

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <system_error>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

class TemporaryFile final {
public:
    TemporaryFile() {
        wchar_t temporary_directory[MAX_PATH]{};
        wchar_t temporary_file[MAX_PATH]{};
        if (GetTempPathW(MAX_PATH, temporary_directory) == 0U ||
            GetTempFileNameW(temporary_directory, L"nfo", 0U, temporary_file) == 0U) {
            return;
        }
        path_ = temporary_file;
        std::ofstream stream(path_, std::ios::binary | std::ios::trunc);
        const std::uint8_t bytes[]{1U, 2U, 3U};
        stream.write(
            reinterpret_cast<const char*>(bytes),
            static_cast<std::streamsize>(sizeof(bytes)));
        if (!stream) {
            path_.clear();
        }
    }

    TemporaryFile(const TemporaryFile&) = delete;
    TemporaryFile& operator=(const TemporaryFile&) = delete;

    ~TemporaryFile() {
        if (!path_.empty()) {
            std::error_code error{};
            static_cast<void>(std::filesystem::remove(path_, error));
        }
    }

    [[nodiscard]] const std::filesystem::path& path() const noexcept { return path_; }

private:
    std::filesystem::path path_{};
};

}  // namespace

int main() {
    const auto invalid = negaflow::imageio::observe_image_file({});
    expect(
        invalid.status == negaflow::imageio::ImageFileObservationStatus::invalid_argument,
        "empty path is invalid");

    const TemporaryFile file{};
    expect(!file.path().empty(), "temporary fixture created");
    const auto first = negaflow::imageio::observe_image_file(file.path());
    const auto second = negaflow::imageio::observe_image_file(file.path());
    expect(
        first.status == negaflow::imageio::ImageFileObservationStatus::ok &&
            first.observation.file_bytes == 3U,
        "regular file metadata observed");
    expect(
        second.status == negaflow::imageio::ImageFileObservationStatus::ok &&
            negaflow::imageio::same_image_file_observation(
                first.observation,
                second.observation),
        "unchanged observations compare equal");

    {
        std::ofstream stream(file.path(), std::ios::binary | std::ios::app);
        const std::uint8_t byte = 4U;
        stream.write(reinterpret_cast<const char*>(&byte), 1);
    }
    const auto changed = negaflow::imageio::observe_image_file(file.path());
    expect(
        changed.status == negaflow::imageio::ImageFileObservationStatus::ok &&
            changed.observation.file_bytes == 4U &&
            !negaflow::imageio::same_image_file_observation(
                first.observation,
                changed.observation),
        "size change is detected without reading contents");

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"image_file_observation\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
