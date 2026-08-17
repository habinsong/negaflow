#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/support/progress.h"
#include "negaflow/imageio/image_file_observation.h"

#include <optional>
#include <stop_token>

namespace negaflow::pipeline::develop_export_detail {

// 디코드 전 파일 관측과, 결함 recipe 가 요구할 때만 하는 내용 해시.
struct ObservedSource final {
    negaflow::imageio::ImageFileObservationResult before{};
};

[[nodiscard]] std::optional<DevelopExportOutcome> observe_source_before(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    std::stop_source& stop,
    ObservedSource& observed) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
