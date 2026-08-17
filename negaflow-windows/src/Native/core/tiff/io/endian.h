#pragma once

#include "negaflow/core/tiff_probe.h"

#include <cstdint>

namespace negaflow::core::tiff_probe_detail {

// TIFF 헤더·IFD 필드를 엔디안에 맞게 읽는다. 파일 I/O 는 하지 않는다.
[[nodiscard]] std::uint16_t read_u16(
    const std::uint8_t* bytes,
    TiffByteOrder byte_order) noexcept;

[[nodiscard]] std::uint32_t read_u32(
    const std::uint8_t* bytes,
    TiffByteOrder byte_order) noexcept;

[[nodiscard]] std::uint64_t read_u64(
    const std::uint8_t* bytes,
    TiffByteOrder byte_order) noexcept;

[[nodiscard]] std::uint8_t type_width(std::uint16_t type) noexcept;

[[nodiscard]] bool is_unsigned_integer_type(std::uint16_t type) noexcept;

[[nodiscard]] bool is_offset_or_size_type(std::uint16_t type) noexcept;

}  // namespace negaflow::core::tiff_probe_detail
