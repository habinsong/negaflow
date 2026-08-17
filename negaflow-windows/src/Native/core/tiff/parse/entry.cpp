#include "entry.h"

#include "tiff/io/endian.h"
#include "tiff/io/math.h"
#include "tiff/parse/tags.h"

#include <algorithm>
#include <array>
#include <cstddef>

namespace negaflow::core::tiff_probe_detail {

bool is_segment_array_tag(const std::uint16_t tag) noexcept {
    return tag == tag_strip_offsets || tag == tag_strip_byte_counts ||
           tag == tag_tile_offsets || tag == tag_tile_byte_counts;
}

TiffProbeStatus parse_entry(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const TiffVariant variant,
    const std::uint64_t entry_offset,
    const std::uint64_t header_bytes,
    const TiffProbeLimits& limits,
    DirectoryEntry& entry) noexcept {
    std::array<std::uint8_t, 20> bytes{};
    const std::size_t entry_bytes = variant == TiffVariant::classic ? 12U : 20U;
    if (!file.read(entry_offset, bytes.data(), entry_bytes)) {
        return TiffProbeStatus::truncated_ifd;
    }

    entry.tag = read_u16(bytes.data(), byte_order);
    entry.type = read_u16(bytes.data() + 2U, byte_order);
    if (variant == TiffVariant::classic && entry.type >= type_long8) {
        return TiffProbeStatus::invalid_tag;
    }
    const std::uint8_t width = type_width(entry.type);
    if (width == 0U) {
        return TiffProbeStatus::invalid_tag;
    }

    const std::size_t value_position = variant == TiffVariant::classic ? 8U : 12U;
    entry.inline_capacity = variant == TiffVariant::classic ? 4U : 8U;
    entry.count = variant == TiffVariant::classic
                      ? static_cast<std::uint64_t>(read_u32(bytes.data() + 4U, byte_order))
                      : read_u64(bytes.data() + 4U, byte_order);
    if (entry.count == 0U ||
        !checked_multiply(entry.count, static_cast<std::uint64_t>(width), entry.total_bytes)) {
        return TiffProbeStatus::invalid_tag;
    }

    std::copy_n(
        bytes.data() + value_position,
        static_cast<std::size_t>(entry.inline_capacity),
        entry.inline_bytes.data());
    entry.value_offset = variant == TiffVariant::classic
                             ? static_cast<std::uint64_t>(
                                   read_u32(entry.inline_bytes.data(), byte_order))
                             : read_u64(entry.inline_bytes.data(), byte_order);

    if (entry.tag == tag_icc_profile && entry.total_bytes > limits.max_icc_profile_bytes) {
        return TiffProbeStatus::tag_limit_exceeded;
    }
    if (!is_segment_array_tag(entry.tag) &&
        entry.total_bytes > limits.max_single_tag_bytes) {
        return TiffProbeStatus::tag_limit_exceeded;
    }

    if (entry.total_bytes > entry.inline_capacity) {
        std::uint64_t value_end = 0;
        if (entry.value_offset < header_bytes || (entry.value_offset & 1U) != 0U ||
            !checked_add(entry.value_offset, entry.total_bytes, value_end) ||
            value_end > file.size()) {
            return TiffProbeStatus::tag_data_out_of_bounds;
        }
    }
    return TiffProbeStatus::ok;
}

TiffProbeStatus read_unsigned_element(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    const std::uint64_t index,
    std::uint64_t& value) noexcept {
    if (!is_unsigned_integer_type(entry.type) || index >= entry.count) {
        return TiffProbeStatus::invalid_tag;
    }

    const std::uint8_t width = type_width(entry.type);
    std::uint64_t element_byte_offset = 0;
    if (!checked_multiply(index, static_cast<std::uint64_t>(width), element_byte_offset)) {
        return TiffProbeStatus::invalid_tag;
    }

    std::array<std::uint8_t, 8> bytes{};
    const std::uint8_t* source = nullptr;
    if (entry.total_bytes <= entry.inline_capacity) {
        source = entry.inline_bytes.data() + static_cast<std::size_t>(element_byte_offset);
    } else {
        std::uint64_t file_offset = 0;
        if (!checked_add(entry.value_offset, element_byte_offset, file_offset) ||
            !file.read(file_offset, bytes.data(), width)) {
            return TiffProbeStatus::tag_data_out_of_bounds;
        }
        source = bytes.data();
    }

    switch (width) {
        case 1U:
            value = source[0];
            return TiffProbeStatus::ok;
        case 2U:
            value = read_u16(source, byte_order);
            return TiffProbeStatus::ok;
        case 4U:
            value = read_u32(source, byte_order);
            return TiffProbeStatus::ok;
        case 8U:
            value = read_u64(source, byte_order);
            return TiffProbeStatus::ok;
        default:
            return TiffProbeStatus::invalid_tag;
    }
}

TiffProbeStatus read_scalar(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    std::uint64_t& value) noexcept {
    if (entry.count != 1U) {
        return TiffProbeStatus::invalid_tag;
    }
    return read_unsigned_element(file, byte_order, entry, 0U, value);
}

}  // namespace negaflow::core::tiff_probe_detail
