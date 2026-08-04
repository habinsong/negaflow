#pragma once

#include <cstdint>
#include <filesystem>

namespace negaflow::imageio {

enum class ImageFileObservationStatus : std::uint8_t {
    ok = 0,
    invalid_argument,
    open_failed,
    not_regular_file,
    file_info_failed,
};

struct ImageFileObservation final {
    std::uint32_t volume_serial_number{0};
    std::uint64_t file_index{0};
    std::uint64_t file_bytes{0};
    std::uint64_t last_write_ticks{0};
};

struct ImageFileObservationResult final {
    ImageFileObservationStatus status{ImageFileObservationStatus::invalid_argument};
    ImageFileObservation observation{};
    std::uint32_t native_error_code{0};
};

// Reads filesystem metadata only. It does not read or hash image contents.
[[nodiscard]] ImageFileObservationResult observe_image_file(
    const std::filesystem::path& path) noexcept;

[[nodiscard]] bool same_image_file_observation(
    const ImageFileObservation& left,
    const ImageFileObservation& right) noexcept;

[[nodiscard]] const char* image_file_observation_status_name(
    ImageFileObservationStatus status) noexcept;

}  // namespace negaflow::imageio
