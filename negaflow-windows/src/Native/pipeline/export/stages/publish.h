#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/stages/finish.h"
#include "export/stages/grain.h"
#include "export/stages/invert.h"
#include "export/stages/look.h"
#include "export/stages/observe.h"
#include "export/support/preview.h"
#include "export/support/progress.h"
#include "negaflow/pipeline/defect_recipe_stage.h"

namespace negaflow::pipeline::develop_export_detail {

// 미리보기 버퍼 또는 PNG/JPEG/TIFF 파일로 게시한다. 성공 시에만 outcome 필드를 채운다.
[[nodiscard]] DevelopExportOutcome publish_developed(
    const DevelopExportRequest& request,
    const PreviewTarget* preview,
    RunTracker& tracker,
    const ObservedSource& observed,
    const DefectRecipeStageResult& defect_recipe,
    const InvertStageOutput& invert,
    const LookStageOutput& look,
    const GrainStageOutput& grain,
    const FinishStageOutput& finish) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
