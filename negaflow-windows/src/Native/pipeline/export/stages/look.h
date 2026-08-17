#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/support/progress.h"
#include "negaflow/imaging/scanner_to_working.h"
#include "negaflow/imaging/working_film_look.h"
#include "negaflow/pipeline/film_look_workspace.h"

#include <cstddef>
#include <cstdint>
#include <optional>

namespace negaflow::pipeline::develop_export_detail {

// Film Look 작업 공간은 반전 전에 준비해야 실패 시점이 원래와 같다.
struct LookWorkspaceOutput final {
    negaflow::imaging::WorkingFilmLookParameters parameters{};
    FilmLookWorkspaceStorage workspace{};
    std::size_t workspace_bytes{0};
};

struct LookStageOutput final {
    negaflow::imaging::WorkingImage image{};
    std::size_t workspace_bytes{0};
    negaflow::imaging::WorkingFilmLookInfo info{};
};

[[nodiscard]] std::optional<DevelopExportOutcome> prepare_look_workspace(
    const DevelopExportRequest& request,
    std::uint32_t decoded_width,
    LookWorkspaceOutput& out) noexcept;

// 톤 조정 다음 Film Look. 작업 공간은 이 호출이 끝날 때까지 살아 있어야 한다.
[[nodiscard]] std::optional<DevelopExportOutcome> apply_look_stages(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    LookWorkspaceOutput& workspace,
    negaflow::imaging::WorkingImage developed,
    LookStageOutput& out) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
