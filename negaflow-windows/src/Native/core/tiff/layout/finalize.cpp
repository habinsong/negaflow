#include "finalize.h"

#include "tiff/io/math.h"
#include "tiff/layout/compressed.h"
#include "tiff/layout/samples.h"
#include "tiff/layout/segments.h"

namespace negaflow::core::tiff_probe_detail {

TiffProbeStatus finalize_info(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const TiffProbeLimits& limits,
    const TiffProbeControl& control,
    const CapturedEntries& captured,
    TiffProbeInfo& info) noexcept {
    if (!captured.has_width || !captured.has_height || info.width == 0U || info.height == 0U) {
        return TiffProbeStatus::invalid_dimensions;
    }
    if (info.samples_per_pixel == 0U || info.samples_per_pixel > info.bits_per_sample.size() ||
        info.orientation == 0U || info.orientation > 8U ||
        (info.planar_configuration != 1U && info.planar_configuration != 2U)) {
        return TiffProbeStatus::invalid_layout;
    }

    if (captured.has_bits_per_sample) {
        const TiffProbeStatus status = read_short_values(
            file,
            byte_order,
            captured.bits_per_sample,
            info.samples_per_pixel,
            info.bits_per_sample,
            info.bits_per_sample_count);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
    }
    if (captured.has_sample_format) {
        const TiffProbeStatus status = read_short_values(
            file,
            byte_order,
            captured.sample_format,
            info.samples_per_pixel,
            info.sample_format,
            info.sample_format_count);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
        for (std::uint8_t index = 0; index < info.sample_format_count; ++index) {
            if (info.sample_format[index] > 6U) {
                return TiffProbeStatus::invalid_layout;
            }
        }
    }
    if (captured.has_extra_samples) {
        const TiffProbeStatus status = read_extra_sample_values(
            file,
            byte_order,
            captured.extra_samples,
            info.samples_per_pixel,
            info.extra_samples,
            info.extra_samples_count);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
    }

    const bool has_any_strip = captured.has_strip_offsets || captured.has_strip_byte_counts ||
                               captured.has_rows_per_strip;
    const bool has_any_tile = captured.has_tile_offsets || captured.has_tile_byte_counts ||
                              captured.has_tile_width || captured.has_tile_length;
    if (has_any_strip == has_any_tile) {
        return TiffProbeStatus::invalid_layout;
    }

    TiffProbeStatus segment_status = TiffProbeStatus::invalid_layout;
    const std::uint64_t plane_count =
        info.planar_configuration == 2U ? info.samples_per_pixel : 1U;
    std::uint64_t expected_segment_count = 0;
    const std::uint64_t minimum_data_offset =
        info.variant == TiffVariant::classic ? 8U : 16U;
    if (has_any_strip) {
        if (!captured.has_strip_offsets || !captured.has_strip_byte_counts ||
            (captured.has_rows_per_strip && captured.rows_per_strip == 0U)) {
            return TiffProbeStatus::invalid_layout;
        }
        const std::uint64_t rows_per_strip =
            captured.has_rows_per_strip ? captured.rows_per_strip : info.height;
        std::uint64_t rounded_height = 0;
        if (!checked_add(info.height, rows_per_strip - 1U, rounded_height) ||
            !checked_multiply(
                rounded_height / rows_per_strip,
                plane_count,
                expected_segment_count)) {
            return TiffProbeStatus::invalid_dimensions;
        }
        info.organization = TiffOrganization::stripped;
        segment_status = validate_segments(
            file,
            byte_order,
            captured.strip_offsets,
            captured.strip_byte_counts,
            limits,
            minimum_data_offset,
            expected_segment_count,
            info);
    } else {
        if (!captured.has_tile_offsets || !captured.has_tile_byte_counts ||
            !captured.has_tile_width || !captured.has_tile_length ||
            captured.tile_width == 0U || captured.tile_length == 0U) {
            return TiffProbeStatus::invalid_layout;
        }
        std::uint64_t rounded_width = 0;
        std::uint64_t rounded_height = 0;
        std::uint64_t tiles_across = 0;
        std::uint64_t tiles_down = 0;
        std::uint64_t tiles_per_plane = 0;
        if (!checked_add(info.width, captured.tile_width - 1U, rounded_width) ||
            !checked_add(info.height, captured.tile_length - 1U, rounded_height)) {
            return TiffProbeStatus::invalid_dimensions;
        }
        tiles_across = rounded_width / captured.tile_width;
        tiles_down = rounded_height / captured.tile_length;
        if (!checked_multiply(tiles_across, tiles_down, tiles_per_plane) ||
            !checked_multiply(tiles_per_plane, plane_count, expected_segment_count)) {
            return TiffProbeStatus::invalid_dimensions;
        }
        info.organization = TiffOrganization::tiled;
        segment_status = validate_segments(
            file,
            byte_order,
            captured.tile_offsets,
            captured.tile_byte_counts,
            limits,
            minimum_data_offset,
            expected_segment_count,
            info);
    }
    if (segment_status != TiffProbeStatus::ok) {
        return segment_status;
    }

    if (info.planar_configuration == 1U) {
        std::uint64_t row_bytes = 0U;
        if (!compute_segment_row_bytes(info, info.width, 0U, row_bytes) ||
            !checked_multiply(row_bytes, info.height, info.packed_raster_bytes)) {
            return TiffProbeStatus::invalid_dimensions;
        }
    } else {
        for (std::uint16_t channel = 0; channel < info.samples_per_pixel; ++channel) {
            std::uint64_t row_bytes = 0U;
            std::uint64_t plane_bytes = 0;
            if (!compute_segment_row_bytes(info, info.width, channel, row_bytes) ||
                !checked_multiply(row_bytes, info.height, plane_bytes) ||
                !checked_add(info.packed_raster_bytes, plane_bytes, info.packed_raster_bytes)) {
                return TiffProbeStatus::invalid_dimensions;
            }
        }
    }

    std::uint64_t pixels = 0;
    if (!checked_multiply(info.width, info.height, pixels) ||
        !checked_multiply(pixels, 16U, info.working_rgba32f_bytes)) {
        return TiffProbeStatus::invalid_dimensions;
    }
    if (info.working_rgba32f_bytes > limits.max_working_rgba32f_bytes) {
        return TiffProbeStatus::working_memory_limit_exceeded;
    }
    return validate_compressed_segments(file, byte_order, limits, control, captured, info);
}

}  // namespace negaflow::core::tiff_probe_detail
