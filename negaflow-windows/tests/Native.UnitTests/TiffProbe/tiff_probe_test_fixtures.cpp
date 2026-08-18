#include "tiff_probe_test_support.h"

#include <fstream>
#include <iostream>

namespace tiff_probe_tests {

[[nodiscard]] std::vector<std::uint8_t> make_classic_tiff(const TiffByteOrder order) {
    constexpr std::uint32_t ifd_offset = 8U;
    constexpr std::uint16_t entry_count = 12U;
    constexpr std::uint32_t bits_offset = 158U;
    constexpr std::uint32_t sample_format_offset = 164U;
    constexpr std::uint32_t pixel_offset = 170U;

    std::vector<std::uint8_t> bytes{};
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    append_u16(bytes, 42U, order);
    append_u32(bytes, ifd_offset, order);
    append_u16(bytes, entry_count, order);
    append_classic_entry(bytes, order, 256U, 4U, 1U, inline_u32(2U, order));
    append_classic_entry(bytes, order, 257U, 4U, 1U, inline_u32(1U, order));
    append_classic_entry(bytes, order, 258U, 3U, 3U, inline_u32(bits_offset, order));
    append_classic_entry(bytes, order, 259U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 262U, 3U, 1U, inline_short(2U, order));
    append_classic_entry(bytes, order, 273U, 4U, 1U, inline_u32(pixel_offset, order));
    append_classic_entry(bytes, order, 274U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 277U, 3U, 1U, inline_short(3U, order));
    append_classic_entry(bytes, order, 278U, 4U, 1U, inline_u32(1U, order));
    append_classic_entry(bytes, order, 279U, 4U, 1U, inline_u32(12U, order));
    append_classic_entry(bytes, order, 284U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(
        bytes,
        order,
        339U,
        3U,
        3U,
        inline_u32(sample_format_offset, order));
    append_u32(bytes, 0U, order);
    append_u16(bytes, 16U, order);
    append_u16(bytes, 16U, order);
    append_u16(bytes, 16U, order);
    append_u16(bytes, 1U, order);
    append_u16(bytes, 1U, order);
    append_u16(bytes, 1U, order);
    for (std::uint8_t value = 0U; value < 12U; ++value) {
        bytes.push_back(value);
    }
    return bytes;
}

// One page of a multi-directory file. Photoshop and most scanner software write the full
// image and append a reduced-resolution preview, so the probe has to choose rather than
// take the first directory it meets.


// Builds a chained multi-directory classic TIFF. Every page carries its own bits,
// sample-format and pixel data immediately after its directory, so page sizes differ and
// the offsets are accumulated rather than assumed.
[[nodiscard]] std::vector<std::uint8_t> make_classic_multi_directory_tiff(
    const TiffByteOrder order,
    const std::vector<DirectoryPage>& pages) {
    constexpr std::uint16_t entry_count = 13U;
    constexpr std::uint32_t directory_bytes =
        2U + (static_cast<std::uint32_t>(entry_count) * 12U) + 4U;
    constexpr std::uint32_t header_bytes = 8U;

    std::vector<std::uint32_t> page_offsets{};
    std::uint32_t cursor = header_bytes;
    for (const DirectoryPage& page : pages) {
        page_offsets.push_back(cursor);
        cursor += directory_bytes + 6U + 6U + (page.width * page.height * 6U);
    }

    std::vector<std::uint8_t> bytes{};
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    append_u16(bytes, 42U, order);
    append_u32(bytes, page_offsets.front(), order);

    for (std::size_t index = 0; index < pages.size(); ++index) {
        const DirectoryPage& page = pages[index];
        const std::uint32_t base = page_offsets[index];
        const std::uint32_t bits_offset = base + directory_bytes;
        const std::uint32_t sample_format_offset = bits_offset + 6U;
        const std::uint32_t pixel_offset = sample_format_offset + 6U;
        const std::uint32_t pixel_bytes = page.width * page.height * 6U;
        const std::uint32_t next =
            index + 1U < pages.size() ? page_offsets[index + 1U] : 0U;

        append_u16(bytes, entry_count, order);
        append_classic_entry(
            bytes, order, 254U, 4U, 1U, inline_u32(page.new_subfile_type, order));
        append_classic_entry(bytes, order, 256U, 4U, 1U, inline_u32(page.width, order));
        append_classic_entry(bytes, order, 257U, 4U, 1U, inline_u32(page.height, order));
        append_classic_entry(bytes, order, 258U, 3U, 3U, inline_u32(bits_offset, order));
        append_classic_entry(bytes, order, 259U, 3U, 1U, inline_short(1U, order));
        append_classic_entry(bytes, order, 262U, 3U, 1U, inline_short(2U, order));
        append_classic_entry(bytes, order, 273U, 4U, 1U, inline_u32(pixel_offset, order));
        append_classic_entry(bytes, order, 274U, 3U, 1U, inline_short(1U, order));
        append_classic_entry(bytes, order, 277U, 3U, 1U, inline_short(3U, order));
        append_classic_entry(bytes, order, 278U, 4U, 1U, inline_u32(page.height, order));
        append_classic_entry(bytes, order, 279U, 4U, 1U, inline_u32(pixel_bytes, order));
        append_classic_entry(bytes, order, 284U, 3U, 1U, inline_short(1U, order));
        append_classic_entry(
            bytes, order, 339U, 3U, 3U, inline_u32(sample_format_offset, order));
        append_u32(bytes, next, order);

        append_u16(bytes, 16U, order);
        append_u16(bytes, 16U, order);
        append_u16(bytes, 16U, order);
        append_u16(bytes, 1U, order);
        append_u16(bytes, 1U, order);
        append_u16(bytes, 1U, order);
        for (std::uint32_t value = 0U; value < pixel_bytes; ++value) {
            bytes.push_back(static_cast<std::uint8_t>(value & 0xFFU));
        }
    }
    return bytes;
}

[[nodiscard]] std::vector<std::uint8_t> make_classic_tiled_tiff(
    const TiffByteOrder order) {
    constexpr std::uint32_t ifd_offset = 8U;
    constexpr std::uint16_t entry_count = 13U;
    constexpr std::uint32_t bits_offset = 170U;
    constexpr std::uint32_t sample_format_offset = 176U;
    constexpr std::uint32_t tile_offsets_offset = 182U;
    constexpr std::uint32_t tile_byte_counts_offset = 198U;
    constexpr std::uint32_t pixel_offset = 214U;
    constexpr std::uint32_t tile_bytes = 24U;
    constexpr std::uint32_t tile_count = 4U;

    std::vector<std::uint8_t> bytes{};
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    append_u16(bytes, 42U, order);
    append_u32(bytes, ifd_offset, order);
    append_u16(bytes, entry_count, order);
    append_classic_entry(bytes, order, 256U, 4U, 1U, inline_u32(4U, order));
    append_classic_entry(bytes, order, 257U, 4U, 1U, inline_u32(3U, order));
    append_classic_entry(bytes, order, 258U, 3U, 3U, inline_u32(bits_offset, order));
    append_classic_entry(bytes, order, 259U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 262U, 3U, 1U, inline_short(2U, order));
    append_classic_entry(bytes, order, 274U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 277U, 3U, 1U, inline_short(3U, order));
    append_classic_entry(bytes, order, 284U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 322U, 4U, 1U, inline_u32(2U, order));
    append_classic_entry(bytes, order, 323U, 4U, 1U, inline_u32(2U, order));
    append_classic_entry(
        bytes,
        order,
        324U,
        4U,
        tile_count,
        inline_u32(tile_offsets_offset, order));
    append_classic_entry(
        bytes,
        order,
        325U,
        4U,
        tile_count,
        inline_u32(tile_byte_counts_offset, order));
    append_classic_entry(
        bytes,
        order,
        339U,
        3U,
        3U,
        inline_u32(sample_format_offset, order));
    append_u32(bytes, 0U, order);
    for (std::uint32_t index = 0U; index < 3U; ++index) {
        append_u16(bytes, 16U, order);
    }
    for (std::uint32_t index = 0U; index < 3U; ++index) {
        append_u16(bytes, 1U, order);
    }
    for (std::uint32_t index = 0U; index < tile_count; ++index) {
        append_u32(bytes, pixel_offset + index * tile_bytes, order);
    }
    for (std::uint32_t index = 0U; index < tile_count; ++index) {
        append_u32(bytes, tile_bytes, order);
    }
    for (std::uint32_t index = 0U; index < tile_count * tile_bytes; ++index) {
        bytes.push_back(static_cast<std::uint8_t>(index));
    }
    return bytes;
}

[[nodiscard]] std::vector<std::uint8_t> make_classic_rgba_tiff(
    const TiffByteOrder order) {
    constexpr std::uint32_t ifd_offset = 8U;
    constexpr std::uint16_t entry_count = 13U;
    constexpr std::uint32_t bits_offset = 170U;
    constexpr std::uint32_t sample_format_offset = 178U;
    constexpr std::uint32_t pixel_offset = 186U;

    std::vector<std::uint8_t> bytes{};
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    append_u16(bytes, 42U, order);
    append_u32(bytes, ifd_offset, order);
    append_u16(bytes, entry_count, order);
    append_classic_entry(bytes, order, 256U, 4U, 1U, inline_u32(2U, order));
    append_classic_entry(bytes, order, 257U, 4U, 1U, inline_u32(1U, order));
    append_classic_entry(bytes, order, 258U, 3U, 4U, inline_u32(bits_offset, order));
    append_classic_entry(bytes, order, 259U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 262U, 3U, 1U, inline_short(2U, order));
    append_classic_entry(bytes, order, 273U, 4U, 1U, inline_u32(pixel_offset, order));
    append_classic_entry(bytes, order, 274U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 277U, 3U, 1U, inline_short(4U, order));
    append_classic_entry(bytes, order, 278U, 4U, 1U, inline_u32(1U, order));
    append_classic_entry(bytes, order, 279U, 4U, 1U, inline_u32(16U, order));
    append_classic_entry(bytes, order, 284U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 338U, 3U, 1U, inline_short(2U, order));
    append_classic_entry(
        bytes,
        order,
        339U,
        3U,
        4U,
        inline_u32(sample_format_offset, order));
    append_u32(bytes, 0U, order);
    for (std::uint32_t index = 0U; index < 4U; ++index) {
        append_u16(bytes, 16U, order);
    }
    for (std::uint32_t index = 0U; index < 4U; ++index) {
        append_u16(bytes, 1U, order);
    }
    for (std::uint8_t value = 0U; value < 16U; ++value) {
        bytes.push_back(value);
    }
    return bytes;
}

[[nodiscard]] std::vector<std::uint8_t> make_bigtiff(const TiffByteOrder order) {
    constexpr std::uint64_t ifd_offset = 16U;
    constexpr std::uint64_t entry_count = 12U;
    constexpr std::uint64_t pixel_offset = 272U;

    std::vector<std::uint8_t> bytes{};
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    append_u16(bytes, 43U, order);
    append_u16(bytes, 8U, order);
    append_u16(bytes, 0U, order);
    append_u64(bytes, ifd_offset, order);
    append_u64(bytes, entry_count, order);
    append_big_entry(bytes, order, 256U, 4U, 1U, inline_u32(2U, order));
    append_big_entry(bytes, order, 257U, 4U, 1U, inline_u32(1U, order));
    append_big_entry(bytes, order, 258U, 3U, 3U, inline_three_shorts(16U, order));
    append_big_entry(bytes, order, 259U, 3U, 1U, inline_short(1U, order));
    append_big_entry(bytes, order, 262U, 3U, 1U, inline_short(2U, order));
    append_big_entry(bytes, order, 273U, 16U, 1U, inline_u64(pixel_offset, order));
    append_big_entry(bytes, order, 274U, 3U, 1U, inline_short(1U, order));
    append_big_entry(bytes, order, 277U, 3U, 1U, inline_short(3U, order));
    append_big_entry(bytes, order, 278U, 4U, 1U, inline_u32(1U, order));
    append_big_entry(bytes, order, 279U, 16U, 1U, inline_u64(12U, order));
    append_big_entry(bytes, order, 284U, 3U, 1U, inline_short(1U, order));
    append_big_entry(bytes, order, 339U, 3U, 3U, inline_three_shorts(1U, order));
    append_u64(bytes, 0U, order);
    for (std::uint8_t value = 0U; value < 12U; ++value) {
        bytes.push_back(value);
    }
    return bytes;
}

void patch_u16(
    std::vector<std::uint8_t>& bytes,
    const std::size_t offset,
    const std::uint16_t value,
    const TiffByteOrder order) {
    std::vector<std::uint8_t> encoded{};
    append_u16(encoded, value, order);
    bytes[offset] = encoded[0];
    bytes[offset + 1U] = encoded[1];
}

void patch_u32(
    std::vector<std::uint8_t>& bytes,
    const std::size_t offset,
    const std::uint32_t value,
    const TiffByteOrder order) {
    std::vector<std::uint8_t> encoded{};
    append_u32(encoded, value, order);
    for (std::size_t index = 0; index < encoded.size(); ++index) {
        bytes[offset + index] = encoded[index];
    }
}

void write_fixture(const std::filesystem::path& path, const std::vector<std::uint8_t>& bytes) {
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    output.write(
        reinterpret_cast<const char*>(bytes.data()),
        static_cast<std::streamsize>(bytes.size()));
    output.close();
    expect(output.good(), "synthetic TIFF fixture is written");
}

[[nodiscard]] std::vector<std::uint8_t> read_fixture(const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    return std::vector<std::uint8_t>(
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>());
}

void expect_status(
    const std::filesystem::path& path,
    const std::vector<std::uint8_t>& bytes,
    const TiffProbeStatus expected_status,
    const char* const message,
    const TiffProbeLimits& limits) {
    write_fixture(path, bytes);
    const auto result = negaflow::core::probe_tiff_file(path, limits);
    expect(result.status == expected_status, message);
}

}  // namespace tiff_probe_tests
