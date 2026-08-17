#pragma once

#include "negaflow/core/tiff_probe.h"

#include <array>
#include <cstdint>

namespace negaflow::core::tiff_probe_detail {

// 한 IFD 항목의 온디스크 표현. 값은 인라인이거나 파일 오프셋이다.
struct DirectoryEntry final {
    std::uint16_t tag{0};
    std::uint16_t type{0};
    std::uint64_t count{0};
    std::uint64_t total_bytes{0};
    std::uint64_t value_offset{0};
    std::uint8_t inline_capacity{0};
    std::array<std::uint8_t, 8> inline_bytes{};
};

[[nodiscard]] bool is_segment_array_tag(std::uint16_t tag) noexcept;

[[nodiscard]] TiffProbeStatus parse_entry(
    const TiffRandomAccessReader& file,
    TiffByteOrder byte_order,
    TiffVariant variant,
    std::uint64_t entry_offset,
    std::uint64_t header_bytes,
    const TiffProbeLimits& limits,
    DirectoryEntry& entry) noexcept;

[[nodiscard]] TiffProbeStatus read_unsigned_element(
    const TiffRandomAccessReader& file,
    TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    std::uint64_t index,
    std::uint64_t& value) noexcept;

[[nodiscard]] TiffProbeStatus read_scalar(
    const TiffRandomAccessReader& file,
    TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    std::uint64_t& value) noexcept;

}  // namespace negaflow::core::tiff_probe_detail
