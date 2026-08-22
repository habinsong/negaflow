#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/stages/invert.h"
#include "export/support/progress.h"

#include "negaflow/pipeline/gpu_accelerator.h"

#include <optional>

namespace negaflow::pipeline::develop_export_detail {

// 장면 보정, 스캐너 타깃/구조/프로파일 그레이드, 색 모델. 화상을 제자리에서 고친다.
[[nodiscard]] std::optional<DevelopExportOutcome> apply_grade_stages(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    GpuUsePolicy gpu_policy,
    InvertStageOutput& invert) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
