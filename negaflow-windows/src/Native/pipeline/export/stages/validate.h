#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/support/preview.h"

#include <optional>

namespace negaflow::pipeline::develop_export_detail {

// 요청 필드 불변식만 검사한다. 파일을 열거나 화소를 건드리지 않는다.
[[nodiscard]] std::optional<DevelopExportOutcome> validate_request(
    const DevelopExportRequest& request,
    const PreviewTarget* preview,
    const DetectTarget* detect) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
