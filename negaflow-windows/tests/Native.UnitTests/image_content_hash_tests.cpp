#include "negaflow/imageio/image_content_hash.h"

#include <Windows.h>

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

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
    explicit TemporaryFile(const std::vector<std::uint8_t>& bytes) {
        wchar_t temporary_directory[MAX_PATH]{};
        wchar_t temporary_file[MAX_PATH]{};
        if (GetTempPathW(MAX_PATH, temporary_directory) == 0U ||
            GetTempFileNameW(temporary_directory, L"nfh", 0U, temporary_file) == 0U) {
            return;
        }
        path_ = temporary_file;
        std::ofstream stream(path_, std::ios::binary | std::ios::trunc);
        if (!stream) {
            path_.clear();
            return;
        }
        stream.write(
            reinterpret_cast<const char*>(bytes.data()),
            static_cast<std::streamsize>(bytes.size()));
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
    const auto disabled = negaflow::imageio::hash_image_content(
        std::filesystem::path{L"Z:\\this-path-must-not-be-opened\\missing.tiff"});
    expect(
        disabled.status == negaflow::imageio::ImageContentHashStatus::disabled &&
            disabled.file_bytes == 0U && disabled.bytes_hashed == 0U &&
            disabled.native_error_code == 0U,
        "default image content hashing is off and performs no path I/O");

    const std::vector<std::uint8_t> abc{'a', 'b', 'c'};
    const TemporaryFile abc_file{abc};
    expect(!abc_file.path().empty(), "temporary abc fixture created");

    negaflow::imageio::ImageContentHashControl enabled{};
    enabled.mode = negaflow::imageio::ImageContentHashMode::sha256;
    const auto abc_result = negaflow::imageio::hash_image_content(abc_file.path(), enabled);
    expect(
        abc_result.status == negaflow::imageio::ImageContentHashStatus::ok,
        "explicit SHA-256 succeeds");
    expect(abc_result.file_bytes == 3U && abc_result.bytes_hashed == 3U, "abc byte count");
    expect(
        negaflow::imageio::image_sha256_hex(abc_result.sha256) ==
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "abc SHA-256 known answer");

    std::vector<std::uint8_t> multi_chunk(200'000U);
    for (std::size_t index = 0U; index < multi_chunk.size(); ++index) {
        multi_chunk[index] = static_cast<std::uint8_t>(index % 251U);
    }
    const TemporaryFile multi_chunk_file{multi_chunk};
    expect(!multi_chunk_file.path().empty(), "temporary multi-chunk fixture created");
    enabled.read_buffer_bytes = 64U * 1024U;
    const auto multi_chunk_result =
        negaflow::imageio::hash_image_content(multi_chunk_file.path(), enabled);
    expect(
        multi_chunk_result.status == negaflow::imageio::ImageContentHashStatus::ok &&
            multi_chunk_result.bytes_hashed == multi_chunk.size(),
        "multi-chunk SHA-256 succeeds");
    expect(
        negaflow::imageio::image_sha256_hex(multi_chunk_result.sha256) ==
            "e24bc62381f1224fbbb74688663f8f9743b9680b193edd666835e97b06e730eb",
        "multi-chunk SHA-256 known answer");

    std::stop_source stop_source{};
    stop_source.request_stop();
    enabled.stop_token = stop_source.get_token();
    const auto cancelled =
        negaflow::imageio::hash_image_content(abc_file.path(), enabled);
    expect(
        cancelled.status == negaflow::imageio::ImageContentHashStatus::cancelled &&
            cancelled.bytes_hashed == 0U,
        "pre-cancelled hash performs no read");

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"image_content_hash\",\"failures\":" << failures
              << "}\n";
    return failures == 0 ? 0 : 1;
}
