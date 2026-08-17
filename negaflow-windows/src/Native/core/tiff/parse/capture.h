#pragma once

#include "negaflow/core/tiff_probe.h"

#include "tiff/parse/entry.h"

namespace negaflow::core::tiff_probe_detail {

// 한 디렉터리에서 나중에 레이아웃을 재구성할 태그만 모아 둔다.
struct CapturedEntries final {
    DirectoryEntry bits_per_sample{};
    DirectoryEntry sample_format{};
    DirectoryEntry extra_samples{};
    DirectoryEntry strip_offsets{};
    DirectoryEntry strip_byte_counts{};
    DirectoryEntry tile_offsets{};
    DirectoryEntry tile_byte_counts{};
    bool has_bits_per_sample{false};
    bool has_sample_format{false};
    bool has_extra_samples{false};
    bool has_strip_offsets{false};
    bool has_strip_byte_counts{false};
    bool has_tile_offsets{false};
    bool has_tile_byte_counts{false};
    bool has_width{false};
    bool has_height{false};
    bool has_compression{false};
    bool has_photometric{false};
    bool has_orientation{false};
    bool has_samples_per_pixel{false};
    bool has_rows_per_strip{false};
    bool has_planar_configuration{false};
    bool has_tile_width{false};
    bool has_tile_length{false};
    bool has_icc_profile{false};
    std::uint64_t rows_per_strip{0};
    std::uint64_t tile_width{0};
    std::uint64_t tile_length{0};
};

[[nodiscard]] TiffProbeStatus capture_entry(
    const TiffRandomAccessReader& file,
    TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    CapturedEntries& captured,
    TiffProbeInfo& info) noexcept;

}  // namespace negaflow::core::tiff_probe_detail
