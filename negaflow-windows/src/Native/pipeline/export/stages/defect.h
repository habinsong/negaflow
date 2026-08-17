#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/support/preview.h"
#include "export/support/progress.h"
#include "negaflow/pipeline/defect_recipe_stage.h"

#include <optional>

namespace negaflow::pipeline::develop_export_detail {

// 디코드된 음성/양화 위에 결함 recipe 를 순서대로 적용한다.
[[nodiscard]] std::optional<DevelopExportOutcome> apply_defect_stage(
    const DevelopExportRequest& request,
    const PreviewTarget* preview,
    const DetectTarget* detect,
    RunTracker& tracker,
    negaflow::imaging::WorkingImage& image,
    DefectRecipeStageResult& recipe) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
