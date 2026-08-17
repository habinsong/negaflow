#include "endian.h"

#include "tiff/parse/tags.h"

namespace negaflow::core::tiff_probe_detail {

std::uint16_t read_u16(
    const std::uint8_t* const bytes,
    const TiffByteOrder byte_order) noexcept {
    if (byte_order == TiffByteOrder::little_endian) {
        return static_cast<std::uint16_t>(
            static_cast<std::uint16_t>(bytes[0]) |
            static_cast<std::uint16_t>(static_cast<std::uint16_t>(bytes[1]) << 8U));
    }
    return static_cast<std::uint16_t>(
        static_cast<std::uint16_t>(static_cast<std::uint16_t>(bytes[0]) << 8U) |
        static_cast<std::uint16_t>(bytes[1]));
}

std::uint32_t read_u32(
    const std::uint8_t* const bytes,
    const TiffByteOrder byte_order) noexcept {
    std::uint32_t value = 0U;
    if (byte_order == TiffByteOrder::little_endian) {
        for (std::uint32_t index = 0U; index < 4U; ++index) {
            value |= static_cast<std::uint32_t>(bytes[index]) << (index * 8U);
        }
    } else {
        for (std::uint32_t index = 0U; index < 4U; ++index) {
            value = static_cast<std::uint32_t>((value << 8U) | bytes[index]);
        }
    }
    return value;
}

std::uint64_t read_u64(
    const std::uint8_t* const bytes,
    const TiffByteOrder byte_order) noexcept {
    std::uint64_t value = 0U;
    if (byte_order == TiffByteOrder::little_endian) {
        for (std::uint32_t index = 0U; index < 8U; ++index) {
            value |= static_cast<std::uint64_t>(bytes[index]) << (index * 8U);
        }
    } else {
        for (std::uint32_t index = 0U; index < 8U; ++index) {
            value = (value << 8U) | bytes[index];
        }
    }
    return value;
}

std::uint8_t type_width(const std::uint16_t type) noexcept {
    switch (type) {
        case 1U:
        case 2U:
        case 6U:
        case 7U:
            return 1U;
        case 3U:
        case 8U:
            return 2U;
        case 4U:
        case 9U:
        case 11U:
        case 13U:
            return 4U;
        case 5U:
        case 10U:
        case 12U:
        case 16U:
        case 17U:
        case 18U:
            return 8U;
        default:
            return 0U;
    }
}

bool is_unsigned_integer_type(const std::uint16_t type) noexcept {
    return type == type_byte || type == type_short || type == type_long || type == type_long8;
}

bool is_offset_or_size_type(const std::uint16_t type) noexcept {
    return type == type_short || type == type_long || type == type_long8;
}

}  // namespace negaflow::core::tiff_probe_detail
