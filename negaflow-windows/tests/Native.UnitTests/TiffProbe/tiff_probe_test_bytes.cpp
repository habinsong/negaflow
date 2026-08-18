#include "tiff_probe_test_support.h"

#include <fstream>
#include <iostream>

namespace tiff_probe_tests {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

void append_u16(
    std::vector<std::uint8_t>& bytes,
    const std::uint16_t value,
    const TiffByteOrder order) {
    if (order == TiffByteOrder::little_endian) {
        bytes.push_back(static_cast<std::uint8_t>(value & 0xffU));
        bytes.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xffU));
    } else {
        bytes.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xffU));
        bytes.push_back(static_cast<std::uint8_t>(value & 0xffU));
    }
}

void append_u32(
    std::vector<std::uint8_t>& bytes,
    const std::uint32_t value,
    const TiffByteOrder order) {
    if (order == TiffByteOrder::little_endian) {
        for (std::uint32_t index = 0U; index < 4U; ++index) {
            bytes.push_back(static_cast<std::uint8_t>((value >> (index * 8U)) & 0xffU));
        }
    } else {
        for (std::uint32_t index = 0U; index < 4U; ++index) {
            const std::uint32_t shift = (3U - index) * 8U;
            bytes.push_back(static_cast<std::uint8_t>((value >> shift) & 0xffU));
        }
    }
}

void append_u64(
    std::vector<std::uint8_t>& bytes,
    const std::uint64_t value,
    const TiffByteOrder order) {
    if (order == TiffByteOrder::little_endian) {
        for (std::uint32_t index = 0U; index < 8U; ++index) {
            bytes.push_back(static_cast<std::uint8_t>((value >> (index * 8U)) & 0xffU));
        }
    } else {
        for (std::uint32_t index = 0U; index < 8U; ++index) {
            const std::uint32_t shift = (7U - index) * 8U;
            bytes.push_back(static_cast<std::uint8_t>((value >> shift) & 0xffU));
        }
    }
}

[[nodiscard]] std::array<std::uint8_t, 8> inline_short(
    const std::uint16_t value,
    const TiffByteOrder order) {
    std::vector<std::uint8_t> encoded{};
    append_u16(encoded, value, order);
    std::array<std::uint8_t, 8> result{};
    result[0] = encoded[0];
    result[1] = encoded[1];
    return result;
}

[[nodiscard]] std::array<std::uint8_t, 8> inline_u32(
    const std::uint32_t value,
    const TiffByteOrder order) {
    std::vector<std::uint8_t> encoded{};
    append_u32(encoded, value, order);
    std::array<std::uint8_t, 8> result{};
    for (std::size_t index = 0; index < 4U; ++index) {
        result[index] = encoded[index];
    }
    return result;
}

[[nodiscard]] std::array<std::uint8_t, 8> inline_u64(
    const std::uint64_t value,
    const TiffByteOrder order) {
    std::vector<std::uint8_t> encoded{};
    append_u64(encoded, value, order);
    std::array<std::uint8_t, 8> result{};
    for (std::size_t index = 0; index < result.size(); ++index) {
        result[index] = encoded[index];
    }
    return result;
}

[[nodiscard]] std::array<std::uint8_t, 8> inline_three_shorts(
    const std::uint16_t value,
    const TiffByteOrder order) {
    std::vector<std::uint8_t> encoded{};
    append_u16(encoded, value, order);
    append_u16(encoded, value, order);
    append_u16(encoded, value, order);
    std::array<std::uint8_t, 8> result{};
    for (std::size_t index = 0; index < encoded.size(); ++index) {
        result[index] = encoded[index];
    }
    return result;
}

void append_classic_entry(
    std::vector<std::uint8_t>& bytes,
    const TiffByteOrder order,
    const std::uint16_t tag,
    const std::uint16_t type,
    const std::uint32_t count,
    const std::array<std::uint8_t, 8>& value) {
    append_u16(bytes, tag, order);
    append_u16(bytes, type, order);
    append_u32(bytes, count, order);
    bytes.insert(bytes.end(), value.begin(), value.begin() + 4);
}

void append_big_entry(
    std::vector<std::uint8_t>& bytes,
    const TiffByteOrder order,
    const std::uint16_t tag,
    const std::uint16_t type,
    const std::uint64_t count,
    const std::array<std::uint8_t, 8>& value) {
    append_u16(bytes, tag, order);
    append_u16(bytes, type, order);
    append_u64(bytes, count, order);
    bytes.insert(bytes.end(), value.begin(), value.end());
}

}  // namespace tiff_probe_tests
