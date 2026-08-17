#pragma once

#include "negaflow/core/tiff_probe.h"

#include "tiff/parse/entry.h"

#include <array>
#include <cstdint>

namespace negaflow::core::tiff_probe_detail {

[[nodiscard]] TiffProbeStatus read_extra_sample_values(
    const TiffRandomAccessReader& file,
    TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    std::uint16_t samples_per_pixel,
    std::array<std::uint16_t, 8>& values,
    std::uint8_t& value_count) noexcept;

[[nodiscard]] TiffProbeStatus read_short_values(
    const TiffRandomAccessReader& file,
    TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    std::uint16_t samples_per_pixel,
    std::array<std::uint16_t, 8>& values,
    std::uint8_t& value_count) noexcept;

}  // namespace negaflow::core::tiff_probe_detail
