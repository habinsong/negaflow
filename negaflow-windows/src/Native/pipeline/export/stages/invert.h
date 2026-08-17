#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/support/progress.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <optional>

namespace negaflow::pipeline::develop_export_detail {

// 자동·프리셋·수동 베이스와 음성 반전. 양화는 화상을 그대로 넘긴다.
struct InvertStageOutput final {
    negaflow::imaging::WorkingImage image{};
    negaflow::imaging::ManualNegativeDevelopParameters negative{};
    DevelopBaseSource base_source{DevelopBaseSource::manual};
    negaflow::imaging::ManualNegativeDevelopInfo developed_info{};
    bool negative_source{false};
    bool positive{false};
};

[[nodiscard]] std::optional<DevelopExportOutcome> invert_source(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    negaflow::imaging::WorkingImage decoded,
    InvertStageOutput& out) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
