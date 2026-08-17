#pragma once

#include "negaflow/core/tiff_probe.h"

#include "tiff/parse/capture.h"

namespace negaflow::core::tiff_probe_detail {

// 켜진 경우에만 LZW·Deflate 스트림을 한 세그먼트씩 검증한다.
[[nodiscard]] TiffProbeStatus validate_compressed_segments(
    const TiffRandomAccessReader& file,
    TiffByteOrder byte_order,
    const TiffProbeLimits& limits,
    const TiffProbeControl& control,
    const CapturedEntries& captured,
    TiffProbeInfo& info) noexcept;

}  // namespace negaflow::core::tiff_probe_detail
