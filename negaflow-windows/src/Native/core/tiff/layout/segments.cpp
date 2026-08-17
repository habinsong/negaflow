#include "segments.h"

#include "tiff/io/endian.h"
#include "tiff/io/math.h"

namespace negaflow::core::tiff_probe_detail {

bool compute_segment_row_bytes(
    const TiffProbeInfo& info,
    const std::uint64_t width,
    const std::uint16_t plane,
    std::uint64_t& row_bytes) noexcept {
    std::uint64_t bits_per_pixel = 0U;
    if (info.planar_configuration == 1U) {
        if (info.bits_per_sample_count == 1U) {
            if (!checked_multiply(
                    info.bits_per_sample[0],
                    info.samples_per_pixel,
                    bits_per_pixel)) {
                return false;
            }
        } else {
            for (std::uint8_t index = 0U; index < info.bits_per_sample_count; ++index) {
                if (!checked_add(
                        bits_per_pixel,
                        info.bits_per_sample[index],
                        bits_per_pixel)) {
                    return false;
                }
            }
        }
    } else {
        if (plane >= info.samples_per_pixel) {
            return false;
        }
        bits_per_pixel = info.bits_per_sample_count == 1U
                             ? info.bits_per_sample[0]
                             : info.bits_per_sample[plane];
    }

    std::uint64_t row_bits = 0U;
    std::uint64_t rounded_row_bits = 0U;
    if (!checked_multiply(width, bits_per_pixel, row_bits) ||
        !checked_add(row_bits, 7U, rounded_row_bits)) {
        return false;
    }
    row_bytes = rounded_row_bits / 8U;
    return true;
}

TiffProbeStatus validate_segments(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const DirectoryEntry& offsets,
    const DirectoryEntry& byte_counts,
    const TiffProbeLimits& limits,
    const std::uint64_t minimum_data_offset,
    const std::uint64_t expected_segment_count,
    TiffProbeInfo& info) noexcept {
    if (!is_offset_or_size_type(offsets.type) ||
        !is_offset_or_size_type(byte_counts.type) || offsets.count == 0U ||
        offsets.count != byte_counts.count || offsets.count != expected_segment_count) {
        return TiffProbeStatus::invalid_layout;
    }
    if (offsets.count > limits.max_segments) {
        return TiffProbeStatus::segment_limit_exceeded;
    }

    for (std::uint64_t index = 0; index < offsets.count; ++index) {
        std::uint64_t offset = 0;
        std::uint64_t byte_count = 0;
        TiffProbeStatus status = read_unsigned_element(file, byte_order, offsets, index, offset);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
        status = read_unsigned_element(file, byte_order, byte_counts, index, byte_count);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
        std::uint64_t segment_end = 0;
        if (offset < minimum_data_offset || byte_count == 0U ||
            !checked_add(offset, byte_count, segment_end) ||
            segment_end > file.size()) {
            return TiffProbeStatus::tag_data_out_of_bounds;
        }
        if (!checked_add(
                info.compressed_segment_bytes,
                byte_count,
                info.compressed_segment_bytes)) {
            return TiffProbeStatus::invalid_layout;
        }
    }
    info.segment_count = offsets.count;
    return TiffProbeStatus::ok;
}

}  // namespace negaflow::core::tiff_probe_detail
