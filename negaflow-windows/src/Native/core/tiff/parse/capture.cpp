#include "capture.h"

#include "tiff/io/endian.h"
#include "tiff/parse/tags.h"

#include <limits>

namespace negaflow::core::tiff_probe_detail {
namespace {

[[nodiscard]] bool mark_once(bool& seen) noexcept {
    if (seen) {
        return false;
    }
    seen = true;
    return true;
}

[[nodiscard]] TiffProbeStatus assign_u16(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    std::uint16_t& target) noexcept {
    std::uint64_t value = 0;
    const TiffProbeStatus status = read_scalar(file, byte_order, entry, value);
    if (status != TiffProbeStatus::ok || value > std::numeric_limits<std::uint16_t>::max()) {
        return TiffProbeStatus::invalid_tag;
    }
    target = static_cast<std::uint16_t>(value);
    return TiffProbeStatus::ok;
}

}  // namespace

TiffProbeStatus capture_entry(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    CapturedEntries& captured,
    TiffProbeInfo& info) noexcept {
    switch (entry.tag) {
        case tag_image_width:
            if (!mark_once(captured.has_width)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            return read_scalar(file, byte_order, entry, info.width);
        case tag_image_length:
            if (!mark_once(captured.has_height)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            return read_scalar(file, byte_order, entry, info.height);
        case tag_bits_per_sample:
            if (!mark_once(captured.has_bits_per_sample)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.bits_per_sample = entry;
            return TiffProbeStatus::ok;
        case tag_compression:
            if (!mark_once(captured.has_compression)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            return assign_u16(file, byte_order, entry, info.compression);
        case tag_photometric:
            if (!mark_once(captured.has_photometric)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            return assign_u16(file, byte_order, entry, info.photometric_interpretation);
        case tag_strip_offsets:
            if (!mark_once(captured.has_strip_offsets)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.strip_offsets = entry;
            return TiffProbeStatus::ok;
        case tag_orientation:
            if (!mark_once(captured.has_orientation)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            return assign_u16(file, byte_order, entry, info.orientation);
        case tag_samples_per_pixel:
            if (!mark_once(captured.has_samples_per_pixel)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            return assign_u16(file, byte_order, entry, info.samples_per_pixel);
        case tag_rows_per_strip:
            if (!mark_once(captured.has_rows_per_strip)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            return read_scalar(file, byte_order, entry, captured.rows_per_strip);
        case tag_strip_byte_counts:
            if (!mark_once(captured.has_strip_byte_counts)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.strip_byte_counts = entry;
            return TiffProbeStatus::ok;
        case tag_planar_configuration:
            if (!mark_once(captured.has_planar_configuration)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            return assign_u16(file, byte_order, entry, info.planar_configuration);
        case tag_tile_width:
            if (!mark_once(captured.has_tile_width)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            return read_scalar(file, byte_order, entry, captured.tile_width);
        case tag_tile_length:
            if (!mark_once(captured.has_tile_length)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            return read_scalar(file, byte_order, entry, captured.tile_length);
        case tag_tile_offsets:
            if (!mark_once(captured.has_tile_offsets)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.tile_offsets = entry;
            return TiffProbeStatus::ok;
        case tag_tile_byte_counts:
            if (!mark_once(captured.has_tile_byte_counts)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.tile_byte_counts = entry;
            return TiffProbeStatus::ok;
        case tag_sample_format:
            if (!mark_once(captured.has_sample_format)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.sample_format = entry;
            return TiffProbeStatus::ok;
        case tag_extra_samples:
            if (!mark_once(captured.has_extra_samples)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.extra_samples = entry;
            return TiffProbeStatus::ok;
        case tag_icc_profile:
            if (!mark_once(captured.has_icc_profile)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_byte && entry.type != type_undefined) {
                return TiffProbeStatus::invalid_tag;
            }
            info.icc_profile_bytes = entry.total_bytes;
            return TiffProbeStatus::ok;
        default:
            return TiffProbeStatus::ok;
    }
}

}  // namespace negaflow::core::tiff_probe_detail
