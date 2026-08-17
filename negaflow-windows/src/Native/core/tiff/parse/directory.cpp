#include "directory.h"

#include "tiff/io/endian.h"
#include "tiff/io/math.h"
#include "tiff/parse/entry.h"
#include "tiff/parse/tags.h"

#include <array>
#include <cstddef>

namespace negaflow::core::tiff_probe_detail {
namespace {

// Bit 0 of NewSubfileType marks a reduced-resolution page and bit 2 a transparency
// mask. Both are companions to some other image, never the image itself. A directory
// without the tag is a full image, which is what a plain single-page scan looks like.
constexpr std::uint64_t subfile_reduced_resolution = 0x1ULL;
constexpr std::uint64_t subfile_transparency_mask = 0x4ULL;

[[nodiscard]] bool is_auxiliary_subfile(const std::uint64_t new_subfile_type) noexcept {
    return (new_subfile_type &
            (subfile_reduced_resolution | subfile_transparency_mask)) != 0U;
}

// Reads one directory's entry count and its NewSubfileType, and follows the chain.
// Deliberately parses nothing else: the point is to decide which directory is worth
// parsing before spending any validation on it.
[[nodiscard]] TiffProbeStatus classify_directory(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const TiffVariant variant,
    const std::uint64_t directory_offset,
    const std::uint64_t header_bytes,
    const std::uint64_t directory_count_bytes,
    const std::uint64_t directory_entry_bytes,
    const std::uint64_t next_directory_bytes,
    const TiffProbeLimits& limits,
    bool& auxiliary,
    std::uint64_t& next_directory_offset) noexcept {
    if (directory_offset < header_bytes || (directory_offset & 1U) != 0U) {
        return TiffProbeStatus::invalid_ifd_offset;
    }

    std::array<std::uint8_t, 8> count_bytes{};
    if (!file.read(
            directory_offset,
            count_bytes.data(),
            static_cast<std::size_t>(directory_count_bytes))) {
        return TiffProbeStatus::truncated_ifd;
    }
    const std::uint64_t entry_count = variant == TiffVariant::classic
                                          ? read_u16(count_bytes.data(), byte_order)
                                          : read_u64(count_bytes.data(), byte_order);
    if (entry_count == 0U) {
        return TiffProbeStatus::invalid_header;
    }
    if (entry_count > limits.max_ifd_entries) {
        return TiffProbeStatus::ifd_entry_limit_exceeded;
    }

    std::uint64_t entries_bytes = 0;
    std::uint64_t entries_offset = 0;
    std::uint64_t next_offset_position = 0;
    std::uint64_t directory_end = 0;
    if (!checked_multiply(entry_count, directory_entry_bytes, entries_bytes) ||
        !checked_add(directory_offset, directory_count_bytes, entries_offset) ||
        !checked_add(entries_offset, entries_bytes, next_offset_position) ||
        !checked_add(next_offset_position, next_directory_bytes, directory_end) ||
        directory_end > file.size()) {
        return TiffProbeStatus::truncated_ifd;
    }

    auxiliary = false;
    for (std::uint64_t index = 0; index < entry_count; ++index) {
        std::uint64_t entry_delta = 0;
        std::uint64_t entry_offset = 0;
        if (!checked_multiply(index, directory_entry_bytes, entry_delta) ||
            !checked_add(entries_offset, entry_delta, entry_offset)) {
            return TiffProbeStatus::truncated_ifd;
        }
        DirectoryEntry entry{};
        const TiffProbeStatus status = parse_entry(
            file, byte_order, variant, entry_offset, header_bytes, limits, entry);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
        if (entry.tag != tag_new_subfile_type) {
            continue;
        }
        std::uint64_t value = 0;
        const TiffProbeStatus value_status =
            read_unsigned_element(file, byte_order, entry, 0U, value);
        if (value_status != TiffProbeStatus::ok) {
            return value_status;
        }
        auxiliary = is_auxiliary_subfile(value);
        break;
    }

    std::array<std::uint8_t, 8> next_bytes{};
    if (!file.read(
            next_offset_position,
            next_bytes.data(),
            static_cast<std::size_t>(next_directory_bytes))) {
        return TiffProbeStatus::truncated_ifd;
    }
    next_directory_offset = variant == TiffVariant::classic
                                ? read_u32(next_bytes.data(), byte_order)
                                : read_u64(next_bytes.data(), byte_order);
    return TiffProbeStatus::ok;
}

}  // namespace

// Chooses the single full-resolution image in the directory chain. Exactly one has to
// qualify: none means the file carries only companion pages, and several means the file
// is a multi-page document whose "the image" is not ours to guess. Both are refused.
TiffProbeStatus select_primary_directory(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const TiffVariant variant,
    const std::uint64_t first_ifd_offset,
    const std::uint64_t header_bytes,
    const std::uint64_t directory_count_bytes,
    const std::uint64_t directory_entry_bytes,
    const std::uint64_t next_directory_bytes,
    const TiffProbeLimits& limits,
    TiffProbeInfo& info) noexcept {
    std::uint64_t offset = first_ifd_offset;
    std::uint64_t index = 0;
    std::uint64_t primary_count = 0;

    while (offset != 0U) {
        if (index >= limits.max_directories) {
            return TiffProbeStatus::directory_limit_exceeded;
        }
        bool auxiliary = false;
        std::uint64_t next_offset = 0;
        const TiffProbeStatus status = classify_directory(
            file,
            byte_order,
            variant,
            offset,
            header_bytes,
            directory_count_bytes,
            directory_entry_bytes,
            next_directory_bytes,
            limits,
            auxiliary,
            next_offset);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
        if (!auxiliary) {
            ++primary_count;
            if (primary_count > 1U) {
                return TiffProbeStatus::multiple_directories_unsupported;
            }
            info.primary_directory_index = index;
            info.primary_ifd_offset = offset;
        }
        offset = next_offset;
        ++index;
    }

    info.directory_count = index;
    if (primary_count != 1U) {
        return TiffProbeStatus::multiple_directories_unsupported;
    }
    return TiffProbeStatus::ok;
}

}  // namespace negaflow::core::tiff_probe_detail
