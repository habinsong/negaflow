#pragma once

#include "negaflow/core/tiff_probe.h"

#include "tiff/parse/entry.h"

#include <cstdint>

namespace negaflow::core::tiff_probe_detail {

[[nodiscard]] bool compute_segment_row_bytes(
    const TiffProbeInfo& info,
    std::uint64_t width,
    std::uint16_t plane,
    std::uint64_t& row_bytes) noexcept;

[[nodiscard]] TiffProbeStatus validate_segments(
    const TiffRandomAccessReader& file,
    TiffByteOrder byte_order,
    const DirectoryEntry& offsets,
    const DirectoryEntry& byte_counts,
    const TiffProbeLimits& limits,
    std::uint64_t minimum_data_offset,
    std::uint64_t expected_segment_count,
    TiffProbeInfo& info) noexcept;

}  // namespace negaflow::core::tiff_probe_detail
