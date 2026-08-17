#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/stages/observe.h"
#include "export/support/progress.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <optional>
#include <stop_token>

namespace negaflow::pipeline::develop_export_detail {

// TIFF 는 스캐너 경로, 그 외는 WIC 표준 화상. 디코드 직후 파일이 바뀌었는지도 확인한다.
[[nodiscard]] std::optional<DevelopExportOutcome> decode_source(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    std::stop_source& stop,
    const ObservedSource& observed,
    negaflow::imaging::WorkingImage& image) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
