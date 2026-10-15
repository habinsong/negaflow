#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/stages/invert.h"
#include "export/support/progress.h"

#include "negaflow/pipeline/gpu_accelerator.h"

#include <optional>

namespace negaflow::pipeline::develop_export_detail {

// 장면 보정, 스캐너 타깃/구조/프로파일 그레이드, 색 모델. 화상을 제자리에서 고친다.
// `stop_before_color_model` 이면 색 모델 직전(화이트밸런스 입력)에서 멈춥니다 — 중립 스포이드가
// 그 값을 잽니다(macOS `negativeWhiteBalanceInput`).
[[nodiscard]] std::optional<DevelopExportOutcome> apply_grade_stages(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    GpuUsePolicy gpu_policy,
    InvertStageOutput& invert,
    bool stop_before_color_model = false) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
