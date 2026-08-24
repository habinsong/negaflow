#pragma once

#include <cstdint>
#include <filesystem>
#include <span>

namespace negaflow::test_fixtures {

[[nodiscard]] bool write_single_frame_tiff16(
    const std::filesystem::path& path,
    std::uint32_t width,
    std::uint32_t height,
    std::uint8_t channels,
    std::span<const std::uint16_t> pixels) noexcept;

[[nodiscard]] bool write_two_frame_tiff16(
    const std::filesystem::path& path,
    std::uint32_t width,
    std::uint32_t height,
    std::uint8_t channels,
    std::span<const std::uint16_t> first,
    std::span<const std::uint16_t> second) noexcept;

}  // namespace negaflow::test_fixtures
