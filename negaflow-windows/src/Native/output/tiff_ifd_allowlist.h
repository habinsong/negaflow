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

/// `descriptive_tags_allowed` 는 내보내기 메타데이터 정책이 원본의 태그를 싣는 경우다.
/// 사용자가 원본 메타데이터를 실으라고 골랐으면 "뜻밖의 태그" 라는 말이 성립하지 않는다 —
/// 그 경우에도 중복 태그·항목 수 상한·색 프로파일 존재는 그대로 본다. 픽셀과 어긋날 수 있는
/// 구조 태그는 애초에 옮기지 않으므로(`export_metadata.cpp`) 여기서 다시 막지 않는다.
[[nodiscard]] TiffIfdAllowlistStatus inspect_minimal_rgb_tiff_ifd(
    const std::filesystem::path& path,
    std::uint64_t max_file_bytes,
    std::uint32_t max_ifd_entries,
    bool descriptive_tags_allowed,
    TiffIfdAllowlistInfo& info,
    std::uint32_t& native_error_code) noexcept;

}  // namespace negaflow::output::detail
