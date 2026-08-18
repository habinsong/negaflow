#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/support/preview_proxy.h"
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

// 프록시 축소 전에 원본에서 베이스를 풉니다. macOS 추정은 표시 프록시와 별개입니다.
[[nodiscard]] std::optional<DevelopExportOutcome> resolve_negative_base(
    const DevelopExportRequest& request,
    const negaflow::imaging::WorkingImage& image,
    PreviewProxyHint& hint) noexcept;

[[nodiscard]] std::optional<DevelopExportOutcome> invert_source(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    negaflow::imaging::WorkingImage decoded,
    InvertStageOutput& out,
    const PreviewProxyHint* hint = nullptr) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
