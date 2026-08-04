#pragma once

#include <cstdint>
#include <filesystem>

namespace negaflow::output::detail {

enum class PngStructureStatus : std::uint8_t {
    ok = 0,
    open_failed,
    not_regular_file,
    size_invalid,
    read_failed,
    invalid_signature,
    malformed_chunk,
    invalid_header,
    missing_color_profile,
    missing_image_data,
    missing_end,
};

struct PngStructureInfo final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint8_t bit_depth{0};
    std::uint8_t color_type{0};
    std::uint32_t image_data_chunks{0};
    std::uint64_t file_bytes{0};
    bool has_icc_profile{false};
};

[[nodiscard]] PngStructureStatus inspect_png_structure(
    const std::filesystem::path& path,
    std::uint64_t max_file_bytes,
    PngStructureInfo& info,
    std::uint32_t& native_error_code) noexcept;

}  // namespace negaflow::output::detail
