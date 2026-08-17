#include "compressed.h"

#include "tiff/io/math.h"
#include "tiff/layout/segments.h"
#include "tiff_deflate_validator.h"
#include "tiff_lzw_validator.h"

#include <algorithm>

namespace negaflow::core::tiff_probe_detail {

TiffProbeStatus validate_compressed_segments(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const TiffProbeLimits& limits,
    const TiffProbeControl& control,
    const CapturedEntries& captured,
    TiffProbeInfo& info) noexcept {
    const bool validate_lzw =
        info.compression == 5U && control.validate_lzw_code_streams;
    const bool validate_deflate =
        info.compression == 8U && control.validate_deflate_streams;
    if (!validate_lzw && !validate_deflate) {
        return TiffProbeStatus::ok;
    }
    if (control.stop_token.stop_requested()) {
        return TiffProbeStatus::cancelled;
    }
    const std::uint64_t compressed_limit = validate_lzw
                                               ? limits.max_lzw_compressed_bytes
                                               : limits.max_deflate_compressed_bytes;
    if (info.compressed_segment_bytes > compressed_limit) {
        return TiffProbeStatus::compressed_data_limit_exceeded;
    }

    const DirectoryEntry& offsets = info.organization == TiffOrganization::stripped
                                        ? captured.strip_offsets
                                        : captured.tile_offsets;
    const DirectoryEntry& byte_counts = info.organization == TiffOrganization::stripped
                                            ? captured.strip_byte_counts
                                            : captured.tile_byte_counts;
    const std::uint64_t plane_count =
        info.planar_configuration == 2U ? info.samples_per_pixel : 1U;
    if (plane_count == 0U || offsets.count % plane_count != 0U) {
        return TiffProbeStatus::invalid_layout;
    }
    const std::uint64_t segments_per_plane = offsets.count / plane_count;

    for (std::uint64_t index = 0U; index < offsets.count; ++index) {
        if (control.stop_token.stop_requested()) {
            return TiffProbeStatus::cancelled;
        }

        std::uint64_t offset = 0U;
        std::uint64_t compressed_bytes = 0U;
        TiffProbeStatus status =
            read_unsigned_element(file, byte_order, offsets, index, offset);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
        status = read_unsigned_element(
            file,
            byte_order,
            byte_counts,
            index,
            compressed_bytes);
        if (status != TiffProbeStatus::ok) {
            return status;
        }

        const std::uint16_t plane = info.planar_configuration == 2U
                                        ? static_cast<std::uint16_t>(
                                              index / segments_per_plane)
                                        : 0U;
        std::uint64_t segment_width = info.width;
        std::uint64_t segment_rows = 0U;
        if (info.organization == TiffOrganization::stripped) {
            const std::uint64_t rows_per_strip = captured.has_rows_per_strip
                                                     ? captured.rows_per_strip
                                                     : info.height;
            const std::uint64_t strip_index = index % segments_per_plane;
            std::uint64_t first_row = 0U;
            if (!checked_multiply(strip_index, rows_per_strip, first_row) ||
                first_row >= info.height) {
                return TiffProbeStatus::invalid_layout;
            }
            segment_rows = std::min(rows_per_strip, info.height - first_row);
        } else {
            segment_width = captured.tile_width;
            segment_rows = captured.tile_length;
        }

        std::uint64_t row_bytes = 0U;
        std::uint64_t expected_decoded_bytes = 0U;
        if (!compute_segment_row_bytes(info, segment_width, plane, row_bytes) ||
            !checked_multiply(row_bytes, segment_rows, expected_decoded_bytes)) {
            return TiffProbeStatus::invalid_dimensions;
        }

        if (validate_lzw) {
            const detail::TiffLzwValidationResult validation =
                detail::validate_tiff_lzw_segment(
                    file,
                    offset,
                    compressed_bytes,
                    expected_decoded_bytes,
                    control.stop_token);
            if (validation.status == detail::TiffLzwValidationStatus::cancelled) {
                return TiffProbeStatus::cancelled;
            }
            if (validation.status == detail::TiffLzwValidationStatus::io_error) {
                return TiffProbeStatus::io_error;
            }
            if (validation.status != detail::TiffLzwValidationStatus::ok) {
                return TiffProbeStatus::invalid_compressed_data;
            }
            if (!checked_add(
                    info.compressed_bytes_validated,
                    validation.compressed_bytes_read,
                    info.compressed_bytes_validated) ||
                !checked_add(
                    info.lzw_code_count,
                    validation.code_count,
                    info.lzw_code_count) ||
                !checked_add(
                    info.lzw_decoded_bytes_validated,
                    validation.decoded_bytes,
                    info.lzw_decoded_bytes_validated)) {
                return TiffProbeStatus::invalid_dimensions;
            }
        } else {
            const detail::TiffDeflateValidationResult validation =
                detail::validate_tiff_deflate_segment(
                    file,
                    offset,
                    compressed_bytes,
                    expected_decoded_bytes,
                    control.stop_token);
            if (validation.status == detail::TiffDeflateValidationStatus::cancelled) {
                return TiffProbeStatus::cancelled;
            }
            if (validation.status == detail::TiffDeflateValidationStatus::io_error) {
                return TiffProbeStatus::io_error;
            }
            if (validation.status != detail::TiffDeflateValidationStatus::ok) {
                return TiffProbeStatus::invalid_compressed_data;
            }
            if (!checked_add(
                    info.compressed_bytes_validated,
                    validation.compressed_bytes_read,
                    info.compressed_bytes_validated) ||
                !checked_add(
                    info.deflate_decoded_bytes_validated,
                    validation.decoded_bytes,
                    info.deflate_decoded_bytes_validated)) {
                return TiffProbeStatus::invalid_dimensions;
            }
        }
    }
    info.lzw_code_streams_validated = validate_lzw;
    info.deflate_streams_validated = validate_deflate;
    return TiffProbeStatus::ok;
}

}  // namespace negaflow::core::tiff_probe_detail
