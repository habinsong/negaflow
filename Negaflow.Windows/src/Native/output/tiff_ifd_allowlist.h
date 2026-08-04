#pragma once

#include <array>
#include <cstdint>
#include <filesystem>

namespace negaflow::output::detail {

enum class TiffIfdAllowlistStatus : std::uint8_t {
    ok = 0,
    open_failed,
    not_regular_file,
    size_invalid,
    read_failed,
    invalid_header,
    invalid_ifd,
    entry_limit_exceeded,
    duplicate_tag,
    unexpected_tag,
    missing_color_profile,
};

struct TiffIfdAllowlistInfo final {
    std::array<std::uint16_t, 128> tag_ids{};
    std::uint32_t tag_count{0};
    std::uint16_t unexpected_tag{0};
    std::uint64_t file_bytes{0};
    bool has_color_profile{false};
};

[[nodiscard]] TiffIfdAllowlistStatus inspect_minimal_rgb_tiff_ifd(
    const std::filesystem::path& path,
    std::uint64_t max_file_bytes,
    std::uint32_t max_ifd_entries,
    TiffIfdAllowlistInfo& info,
    std::uint32_t& native_error_code) noexcept;

}  // namespace negaflow::output::detail
