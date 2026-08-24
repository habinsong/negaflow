#pragma once

#include "negaflow/core/tiff_probe.h"

#include <cstdint>

namespace negaflow::core::tiff_probe_detail {

// 디렉터리 사슬에서 전체 해상도 화상 하나를 고른다. 미리보기·마스크는 버린다.
[[nodiscard]] TiffProbeStatus select_primary_directory(
    const TiffRandomAccessReader& file,
    TiffByteOrder byte_order,
    TiffVariant variant,
    std::uint64_t first_ifd_offset,
    std::uint64_t header_bytes,
    std::uint64_t directory_count_bytes,
    std::uint64_t directory_entry_bytes,
    std::uint64_t next_directory_bytes,
    const TiffProbeLimits& limits,
    bool select_first_directory,
    TiffProbeInfo& info) noexcept;

}  // namespace negaflow::core::tiff_probe_detail
