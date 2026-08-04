#include "synthetic_wic_tiff.h"

#include <array>
#include <cstdint>
#include <vector>

namespace negaflow::test_fixtures {
namespace {

constexpr std::uint32_t bits_offset = 158U;
constexpr std::uint32_t sample_format_offset = 164U;
constexpr std::uint32_t pixel_offset = 170U;

void append_u16(std::vector<std::uint8_t>& bytes, const std::uint16_t value) {
    bytes.push_back(static_cast<std::uint8_t>(value & 0xffU));
    bytes.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xffU));
}

void append_u32(std::vector<std::uint8_t>& bytes, const std::uint32_t value) {
    for (std::uint32_t index = 0U; index < 4U; ++index) {
        bytes.push_back(static_cast<std::uint8_t>((value >> (index * 8U)) & 0xffU));
    }
}

void append_entry(
    std::vector<std::uint8_t>& bytes,
    const std::uint16_t tag,
    const std::uint16_t type,
    const std::uint32_t count,
    const std::uint32_t value) {
    append_u16(bytes, tag);
    append_u16(bytes, type);
    append_u32(bytes, count);
    append_u32(bytes, value);
}

[[nodiscard]] std::vector<std::uint8_t> pack_lzw_codes(
    const std::vector<std::uint16_t>& codes) {
    std::vector<std::uint8_t> bytes{};
    std::uint64_t pending = 0U;
    std::uint32_t pending_bits = 0U;
    std::uint16_t next_dictionary_code = 258U;
    std::uint8_t code_width = 9U;
    bool has_previous_code = false;

    for (const std::uint16_t code : codes) {
        pending = (pending << code_width) | code;
        pending_bits += code_width;
        while (pending_bits >= 8U) {
            const std::uint32_t shift = pending_bits - 8U;
            bytes.push_back(static_cast<std::uint8_t>((pending >> shift) & 0xffU));
            pending_bits -= 8U;
            pending = pending_bits == 0U ? 0U : pending & ((1ULL << pending_bits) - 1U);
        }

        if (code == 256U) {
            next_dictionary_code = 258U;
            code_width = 9U;
            has_previous_code = false;
        } else if (code != 257U) {
            if (!has_previous_code) {
                has_previous_code = true;
            } else if (next_dictionary_code <= 4094U) {
                ++next_dictionary_code;
                if (next_dictionary_code == 511U) {
                    code_width = 10U;
                } else if (next_dictionary_code == 1023U) {
                    code_width = 11U;
                } else if (next_dictionary_code == 2047U) {
                    code_width = 12U;
                }
            }
        }
    }

    if (pending_bits != 0U) {
        bytes.push_back(static_cast<std::uint8_t>(pending << (8U - pending_bits)));
    }
    return bytes;
}

[[nodiscard]] std::vector<std::uint8_t> make_tiff(
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint16_t compression,
    const std::vector<std::uint8_t>& compressed) {
    constexpr std::uint16_t entry_count = 12U;

    std::vector<std::uint8_t> bytes{};
    bytes.push_back('I');
    bytes.push_back('I');
    append_u16(bytes, 42U);
    append_u32(bytes, 8U);
    append_u16(bytes, entry_count);
    append_entry(bytes, 256U, 4U, 1U, width);
    append_entry(bytes, 257U, 4U, 1U, height);
    append_entry(bytes, 258U, 3U, 3U, bits_offset);
    append_entry(bytes, 259U, 3U, 1U, compression);
    append_entry(bytes, 262U, 3U, 1U, 2U);
    append_entry(bytes, 273U, 4U, 1U, pixel_offset);
    append_entry(bytes, 274U, 3U, 1U, 1U);
    append_entry(bytes, 277U, 3U, 1U, 3U);
    append_entry(bytes, 278U, 4U, 1U, height);
    append_entry(
        bytes,
        279U,
        4U,
        1U,
        static_cast<std::uint32_t>(compressed.size()));
    append_entry(bytes, 284U, 3U, 1U, 1U);
    append_entry(bytes, 339U, 3U, 3U, sample_format_offset);
    append_u32(bytes, 0U);
    for (std::uint32_t index = 0U; index < 3U; ++index) {
        append_u16(bytes, 16U);
    }
    for (std::uint32_t index = 0U; index < 3U; ++index) {
        append_u16(bytes, 1U);
    }
    bytes.insert(bytes.end(), compressed.begin(), compressed.end());
    return bytes;
}

[[nodiscard]] std::vector<std::uint8_t> make_lzw_tiff(
    const std::uint32_t width,
    const std::uint32_t height,
    const std::vector<std::uint16_t>& codes) {
    return make_tiff(width, height, 5U, pack_lzw_codes(codes));
}

[[nodiscard]] std::uint32_t adler32(const std::array<std::uint8_t, 6>& bytes) noexcept {
    constexpr std::uint32_t modulus = 65'521U;
    std::uint32_t first = 1U;
    std::uint32_t second = 0U;
    for (const std::uint8_t byte : bytes) {
        first = (first + byte) % modulus;
        second = (second + first) % modulus;
    }
    return (second << 16U) | first;
}

[[nodiscard]] std::vector<std::uint8_t> make_stored_zlib_stream(
    const bool malformed) {
    constexpr std::array<std::uint8_t, 6> pixel_bytes{
        0x34U,
        0x12U,
        0x78U,
        0x56U,
        0xbcU,
        0x9aU,
    };
    std::vector<std::uint8_t> bytes{
        0x78U,
        0x01U,
        0x01U,
        0x06U,
        0x00U,
        0xf9U,
        0xffU,
    };
    if (malformed) {
        // Claim a 65,535-byte stored block while retaining the small bounded segment.
        bytes[3U] = 0xffU;
        bytes[4U] = 0xffU;
        bytes[5U] = 0x00U;
        bytes[6U] = 0x00U;
    }
    bytes.insert(bytes.end(), pixel_bytes.begin(), pixel_bytes.end());
    const std::uint32_t checksum = adler32(pixel_bytes);
    for (std::uint32_t shift = 24U;; shift -= 8U) {
        bytes.push_back(static_cast<std::uint8_t>((checksum >> shift) & 0xffU));
        if (shift == 0U) {
            break;
        }
    }
    return bytes;
}

}  // namespace

std::vector<std::uint8_t> make_lzw_rgb16_rows_tiff(const std::uint32_t row_count) {
    if (row_count == 0U || row_count > 16U) {
        return {};
    }
    constexpr std::array<std::uint8_t, 6> pixel_bytes{
        0x34U,
        0x12U,
        0x78U,
        0x56U,
        0xbcU,
        0x9aU,
    };
    std::vector<std::uint16_t> codes{256U};
    for (std::uint32_t row = 0U; row < row_count; ++row) {
        for (const std::uint8_t value : pixel_bytes) {
            codes.push_back(value);
        }
    }
    codes.push_back(257U);
    return make_lzw_tiff(1U, row_count, codes);
}

std::vector<std::uint8_t> make_lzw_rgb16_tiff() {
    return make_lzw_rgb16_rows_tiff(1U);
}

std::vector<std::uint8_t> make_lzw_code_width_transition_rgb16_tiff() {
    constexpr std::uint32_t row_count = 300U;
    constexpr std::array<std::uint8_t, 6> pixel_bytes{
        0x34U,
        0x12U,
        0x78U,
        0x56U,
        0xbcU,
        0x9aU,
    };
    std::vector<std::uint16_t> codes{256U};
    for (std::uint32_t row = 0U; row < row_count; ++row) {
        for (const std::uint8_t byte : pixel_bytes) {
            codes.push_back(byte);
        }
    }
    codes.push_back(257U);
    return make_lzw_tiff(1U, row_count, codes);
}

std::vector<std::uint8_t> make_lzw_dictionary_limit_rgb16_tiff() {
    constexpr std::uint32_t row_count = 640U;
    constexpr std::uint32_t code_count_before_clear = 3'838U;
    constexpr std::array<std::uint8_t, 6> pixel_bytes{
        0x34U,
        0x12U,
        0x78U,
        0x56U,
        0xbcU,
        0x9aU,
    };
    constexpr std::uint32_t decoded_byte_count =
        row_count * static_cast<std::uint32_t>(pixel_bytes.size());
    std::vector<std::uint16_t> codes{256U};
    for (std::uint32_t index = 0U; index < decoded_byte_count; ++index) {
        if (index == code_count_before_clear) {
            codes.push_back(256U);
        }
        codes.push_back(pixel_bytes[index % pixel_bytes.size()]);
    }
    codes.push_back(257U);
    return make_lzw_tiff(1U, row_count, codes);
}

std::vector<std::uint8_t> make_lzw_forward_reference_rgb16_tiff() {
    return make_lzw_tiff(1U, 1U, {256U, 0x34U, 258U, 259U, 257U});
}

std::vector<std::uint8_t> make_nonzero_fill_bits_lzw_rgb16_tiff() {
    std::vector<std::uint8_t> compressed =
        pack_lzw_codes({256U, 0x34U, 258U, 259U, 257U});
    compressed.back() |= 0x07U;
    return make_tiff(1U, 1U, 5U, compressed);
}

std::vector<std::uint8_t> make_claimed_expansion_lzw_rgb16_tiff(
    const std::uint32_t width,
    const std::uint32_t height) {
    return make_lzw_tiff(
        width,
        height,
        {256U, 0x34U, 0x12U, 0x78U, 0x56U, 0xbcU, 0x9aU, 257U});
}

std::vector<std::uint8_t> make_malformed_lzw_rgb16_tiff() {
    std::vector<std::uint8_t> bytes = make_lzw_rgb16_tiff();
    // Keep StripByteCounts unchanged while truncating the compressed segment itself.
    bytes.pop_back();
    return bytes;
}

std::vector<std::uint8_t> make_missing_clear_lzw_rgb16_tiff() {
    return make_lzw_tiff(
        1U,
        1U,
        {0x34U, 0x12U, 0x78U, 0x56U, 0xbcU, 0x9aU, 257U});
}

std::vector<std::uint8_t> make_missing_eoi_lzw_rgb16_tiff() {
    return make_lzw_tiff(
        1U,
        1U,
        {256U, 0x34U, 0x12U, 0x78U, 0x56U, 0xbcU, 0x9aU});
}

std::vector<std::uint8_t> make_short_decoded_lzw_rgb16_tiff() {
    return make_lzw_tiff(
        1U,
        1U,
        {256U, 0x34U, 0x12U, 0x78U, 0x56U, 0xbcU, 257U});
}

std::vector<std::uint8_t> make_long_decoded_lzw_rgb16_tiff() {
    return make_lzw_tiff(
        1U,
        1U,
        {256U, 0x34U, 0x12U, 0x78U, 0x56U, 0xbcU, 0x9aU, 0xffU, 257U});
}

std::vector<std::uint8_t> make_invalid_forward_code_lzw_rgb16_tiff() {
    return make_lzw_tiff(1U, 1U, {256U, 300U, 257U});
}

std::vector<std::uint8_t> make_trailing_data_lzw_rgb16_tiff() {
    std::vector<std::uint8_t> compressed = pack_lzw_codes(
        {256U, 0x34U, 0x12U, 0x78U, 0x56U, 0xbcU, 0x9aU, 257U});
    compressed.push_back(0U);
    return make_tiff(1U, 1U, 5U, compressed);
}

std::vector<std::uint8_t> make_deflate_rgb16_tiff() {
    return make_tiff(1U, 1U, 8U, make_stored_zlib_stream(false));
}

std::vector<std::uint8_t> make_malformed_deflate_rgb16_tiff() {
    return make_tiff(1U, 1U, 8U, make_stored_zlib_stream(true));
}

}  // namespace negaflow::test_fixtures
