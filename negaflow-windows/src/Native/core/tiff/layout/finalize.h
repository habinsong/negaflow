#pragma once

#include "negaflow/core/tiff_probe.h"

#include "tiff/parse/capture.h"

namespace negaflow::core::tiff_probe_detail {

// 캡처한 태그로 샘플·스트립/타일·작업 메모리를 검사하고 압축 검증을 이어 준다.
[[nodiscard]] TiffProbeStatus finalize_info(
    const TiffRandomAccessReader& file,
    TiffByteOrder byte_order,
    const TiffProbeLimits& limits,
    const TiffProbeControl& control,
    const CapturedEntries& captured,
    TiffProbeInfo& info) noexcept;

}  // namespace negaflow::core::tiff_probe_detail
