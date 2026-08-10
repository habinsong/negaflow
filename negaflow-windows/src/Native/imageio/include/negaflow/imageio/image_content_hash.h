#pragma once

#include "negaflow/imageio/image_file_observation.h"

#include <array>
#include <cstdint>
#include <filesystem>
#include <stop_token>
#include <string>

namespace negaflow::imageio {

inline constexpr std::uint32_t default_image_hash_read_buffer_bytes = 8U * 1024U * 1024U;

enum class ImageContentHashMode : std::uint8_t {
    off = 0,
    sha256,
};

enum class ImageContentHashStatus : std::uint8_t {
    disabled = 0,
    ok,
    invalid_argument,
    cancelled,
    open_failed,
    not_regular_file,
    file_info_failed,
    allocation_failed,
    read_failed,
    hash_failed,
    file_changed,
};

struct ImageContentHashProgress final {
    std::uint64_t completed_bytes{0};
    std::uint64_t total_bytes{0};
};

class ImageContentHashProgressObserver {
public:
    ImageContentHashProgressObserver() noexcept = default;
    ImageContentHashProgressObserver(const ImageContentHashProgressObserver&) = delete;
    ImageContentHashProgressObserver& operator=(const ImageContentHashProgressObserver&) = delete;
    virtual ~ImageContentHashProgressObserver() = default;

    virtual void report(ImageContentHashProgress progress) noexcept = 0;
};

struct ImageContentHashControl final {
    // Routine local image work performs no content-hash I/O unless the caller opts in.
    ImageContentHashMode mode{ImageContentHashMode::off};
    std::uint32_t read_buffer_bytes{default_image_hash_read_buffer_bytes};
    std::stop_token stop_token{};
    ImageContentHashProgressObserver* progress_observer{nullptr};
};

struct ImageContentHashResult final {
    ImageContentHashStatus status{ImageContentHashStatus::disabled};
    std::array<std::uint8_t, 32> sha256{};
    std::uint64_t file_bytes{0};
    std::uint64_t bytes_hashed{0};
    std::uint32_t native_error_code{0};
    // Exact filesystem state of the handle after a successful hash. A caller can
    // bind the digest to a later path-based decode without a TOCTOU gap.
    ImageFileObservation observation{};
};

[[nodiscard]] ImageContentHashResult hash_image_content(
    const std::filesystem::path& path,
    const ImageContentHashControl& control = {}) noexcept;

[[nodiscard]] std::string image_sha256_hex(
    const std::array<std::uint8_t, 32>& digest);

[[nodiscard]] const char* image_content_hash_status_name(
    ImageContentHashStatus status) noexcept;

}  // namespace negaflow::imageio
