#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/support/preview.h"
#include "export/support/progress.h"
#include "negaflow/imaging/grain_mend.h"

#include <optional>

namespace negaflow::pipeline::develop_export_detail {

// 검출 호출은 여기서 끝나고, 적용 호출은 수리된 화상을 넘긴다.
struct GrainStageOutput final {
    bool detect_complete{false};
    DevelopExportOutcome detect_outcome{};
    negaflow::imaging::GrainMendResult applied{};
};

[[nodiscard]] std::optional<DevelopExportOutcome> apply_grain_stage(
    const DevelopExportRequest& request,
    const DevelopRunControl& control,
    const DetectTarget* detect,
    RunTracker& tracker,
    negaflow::imaging::WorkingImage image,
    GrainStageOutput& out) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
