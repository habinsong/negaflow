#include "negaflow/core/tiff_probe.h"

#include "tiff/io/endian.h"
#include "tiff/io/file.h"
#include "tiff/io/math.h"
#include "tiff/layout/finalize.h"
#include "tiff/parse/capture.h"
#include "tiff/parse/directory.h"
#include "tiff/parse/entry.h"

#include <array>
#include <cstddef>
#include <cstdint>

namespace negaflow::core {

using tiff_probe_detail::CapturedEntries;
using tiff_probe_detail::DirectoryEntry;
using tiff_probe_detail::ReadOnlyFile;
using tiff_probe_detail::capture_entry;
using tiff_probe_detail::checked_add;
using tiff_probe_detail::checked_multiply;
using tiff_probe_detail::finalize_info;
using tiff_probe_detail::parse_entry;
using tiff_probe_detail::read_u16;
using tiff_probe_detail::read_u32;
using tiff_probe_detail::read_u64;
using tiff_probe_detail::select_primary_directory;

TiffProbeResult probe_tiff(
    const TiffRandomAccessReader& file,
    const TiffProbeLimits& limits,
    const TiffProbeControl& control) noexcept {
    TiffProbeResult result{};
    try {
        result.info.file_bytes = file.size();
        if (file.size() > limits.max_file_bytes) {
            result.status = TiffProbeStatus::file_limit_exceeded;
            return result;
        }
        if (file.size() < 8U) {
            result.status = TiffProbeStatus::truncated_header;
            return result;
        }

        std::array<std::uint8_t, 16> header{};
        if (!file.read(0U, header.data(), 8U)) {
            result.status = TiffProbeStatus::truncated_header;
            return result;
        }
        if (header[0] == 'I' && header[1] == 'I') {
            result.info.byte_order = TiffByteOrder::little_endian;
        } else if (header[0] == 'M' && header[1] == 'M') {
            result.info.byte_order = TiffByteOrder::big_endian;
        } else {
            result.status = TiffProbeStatus::invalid_header;
            return result;
        }

        const std::uint16_t version = read_u16(header.data() + 2U, result.info.byte_order);
        std::uint64_t header_bytes = 0;
        std::uint64_t directory_count_bytes = 0;
        std::uint64_t directory_entry_bytes = 0;
        std::uint64_t next_directory_bytes = 0;
        if (version == 42U) {
            result.info.variant = TiffVariant::classic;
            header_bytes = 8U;
            directory_count_bytes = 2U;
            directory_entry_bytes = 12U;
            next_directory_bytes = 4U;
            result.info.first_ifd_offset = read_u32(header.data() + 4U, result.info.byte_order);
        } else if (version == 43U) {
            if (file.size() < 16U || !file.read(0U, header.data(), header.size())) {
                result.status = TiffProbeStatus::truncated_header;
                return result;
            }
            if (read_u16(header.data() + 4U, result.info.byte_order) != 8U ||
                read_u16(header.data() + 6U, result.info.byte_order) != 0U) {
                result.status = TiffProbeStatus::invalid_bigtiff_header;
                return result;
            }
            result.info.variant = TiffVariant::big;
            header_bytes = 16U;
            directory_count_bytes = 8U;
            directory_entry_bytes = 20U;
            next_directory_bytes = 8U;
            result.info.first_ifd_offset = read_u64(header.data() + 8U, result.info.byte_order);
        } else {
            result.status = TiffProbeStatus::invalid_header;
            return result;
        }

        if (result.info.first_ifd_offset < header_bytes ||
            (result.info.first_ifd_offset & 1U) != 0U) {
            result.status = TiffProbeStatus::invalid_ifd_offset;
            return result;
        }

        // Walk the directory chain and pick the one full-resolution image before parsing
        // anything. A reduced-resolution preview page has the same tags as the real
        // image, so classifying first is what keeps the probe from validating a 1500px
        // thumbnail and reporting it as the scan.
        const TiffProbeStatus selection_status = select_primary_directory(
            file,
            result.info.byte_order,
            result.info.variant,
            result.info.first_ifd_offset,
            header_bytes,
            directory_count_bytes,
            directory_entry_bytes,
            next_directory_bytes,
            limits,
            control.select_first_directory,
            result.info);
        if (selection_status != TiffProbeStatus::ok) {
            result.status = selection_status;
            return result;
        }

        std::array<std::uint8_t, 8> count_bytes{};
        if (!file.read(
                result.info.primary_ifd_offset,
                count_bytes.data(),
                static_cast<std::size_t>(directory_count_bytes))) {
            result.status = TiffProbeStatus::truncated_ifd;
            return result;
        }
        result.info.ifd_entry_count = result.info.variant == TiffVariant::classic
                                          ? read_u16(count_bytes.data(), result.info.byte_order)
                                          : read_u64(count_bytes.data(), result.info.byte_order);
        if (result.info.ifd_entry_count == 0U) {
            result.status = TiffProbeStatus::invalid_header;
            return result;
        }
        if (result.info.ifd_entry_count > limits.max_ifd_entries) {
            result.status = TiffProbeStatus::ifd_entry_limit_exceeded;
            return result;
        }

        std::uint64_t entries_bytes = 0;
        std::uint64_t entries_offset = 0;
        std::uint64_t next_ifd_offset_position = 0;
        std::uint64_t directory_end = 0;
        if (!checked_multiply(
                result.info.ifd_entry_count, directory_entry_bytes, entries_bytes) ||
            !checked_add(
                result.info.primary_ifd_offset, directory_count_bytes, entries_offset) ||
            !checked_add(entries_offset, entries_bytes, next_ifd_offset_position) ||
            !checked_add(next_ifd_offset_position, next_directory_bytes, directory_end) ||
            directory_end > file.size()) {
            result.status = TiffProbeStatus::truncated_ifd;
            return result;
        }

        CapturedEntries captured{};
        for (std::uint64_t index = 0; index < result.info.ifd_entry_count; ++index) {
            std::uint64_t entry_delta = 0;
            std::uint64_t entry_offset = 0;
            if (!checked_multiply(index, directory_entry_bytes, entry_delta) ||
                !checked_add(entries_offset, entry_delta, entry_offset)) {
                result.status = TiffProbeStatus::truncated_ifd;
                return result;
            }

            DirectoryEntry entry{};
            TiffProbeStatus status = parse_entry(
                file,
                result.info.byte_order,
                result.info.variant,
                entry_offset,
                header_bytes,
                limits,
                entry);
            if (status != TiffProbeStatus::ok) {
                result.status = status;
                return result;
            }
            status = capture_entry(file, result.info.byte_order, entry, captured, result.info);
            if (status != TiffProbeStatus::ok) {
                result.status = status;
                return result;
            }
        }

        result.status = finalize_info(
            file,
            result.info.byte_order,
            limits,
            control,
            captured,
            result.info);
        return result;
    } catch (...) {
        result.status = TiffProbeStatus::io_error;
        return result;
    }
}

TiffProbeResult probe_tiff_file(
    const std::filesystem::path& path,
    const TiffProbeLimits& limits,
    const TiffProbeControl& control) noexcept {
    TiffProbeResult result{};
    try {
        ReadOnlyFile file{};
        if (!file.open(path)) {
            result.status = TiffProbeStatus::io_error;
            return result;
        }
        return probe_tiff(file, limits, control);
    } catch (...) {
        result.status = TiffProbeStatus::io_error;
        return result;
    }
}

const char* tiff_probe_status_name(const TiffProbeStatus status) noexcept {
    switch (status) {
        case TiffProbeStatus::ok:
            return "ok";
        case TiffProbeStatus::io_error:
            return "io_error";
        case TiffProbeStatus::file_limit_exceeded:
            return "file_limit_exceeded";
        case TiffProbeStatus::truncated_header:
            return "truncated_header";
        case TiffProbeStatus::invalid_header:
            return "invalid_tiff_header";
        case TiffProbeStatus::invalid_bigtiff_header:
            return "invalid_bigtiff_header";
        case TiffProbeStatus::invalid_ifd_offset:
            return "invalid_ifd_offset";
        case TiffProbeStatus::ifd_entry_limit_exceeded:
            return "ifd_entry_limit_exceeded";
        case TiffProbeStatus::truncated_ifd:
            return "truncated_ifd";
        case TiffProbeStatus::invalid_tag:
            return "invalid_tiff_tag";
        case TiffProbeStatus::duplicate_tag:
            return "duplicate_tiff_tag";
        case TiffProbeStatus::tag_data_out_of_bounds:
            return "tag_data_out_of_bounds";
        case TiffProbeStatus::tag_limit_exceeded:
            return "tag_limit_exceeded";
        case TiffProbeStatus::invalid_dimensions:
            return "invalid_tiff_dimensions";
        case TiffProbeStatus::invalid_layout:
            return "invalid_tiff_layout";
        case TiffProbeStatus::segment_limit_exceeded:
            return "segment_limit_exceeded";
        case TiffProbeStatus::compressed_data_limit_exceeded:
            return "compressed_data_limit_exceeded";
        case TiffProbeStatus::invalid_compressed_data:
            return "invalid_compressed_data";
        case TiffProbeStatus::working_memory_limit_exceeded:
            return "working_memory_limit_exceeded";
        case TiffProbeStatus::multiple_directories_unsupported:
            return "multiple_directories_unsupported";
        case TiffProbeStatus::directory_limit_exceeded:
            return "directory_limit_exceeded";
        case TiffProbeStatus::cancelled:
            return "cancelled";
    }
    return "unknown_tiff_probe_status";
}

const char* tiff_variant_name(const TiffVariant variant) noexcept {
    return variant == TiffVariant::classic ? "classic" : "big";
}

const char* tiff_byte_order_name(const TiffByteOrder byte_order) noexcept {
    return byte_order == TiffByteOrder::little_endian ? "little" : "big";
}

const char* tiff_organization_name(const TiffOrganization organization) noexcept {
    return organization == TiffOrganization::stripped ? "stripped" : "tiled";
}

}  // namespace negaflow::core
