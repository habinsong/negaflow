#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/support/progress.h"
#include "negaflow/imaging/scanner_to_working.h"
#include "negaflow/imaging/working_film_look.h"
#include "negaflow/pipeline/film_look_workspace.h"
#include "negaflow/pipeline/gpu_accelerator.h"
#include "negaflow/pipeline/gpu_accelerator.h"

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
// `gpu_policy` 는 톤 7단계를 GPU 로 돌려도 되는 경로인지입니다. 내보내기·골든은
// `cpu_only` 여야 합니다 — GPU 값이 CPU 와 바이트까지 같지는 않습니다
// (`gpu_accelerator.h` 의 표).
[[nodiscard]] std::optional<DevelopExportOutcome> apply_look_stages(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    LookWorkspaceOutput& workspace,
    negaflow::imaging::WorkingImage developed,
    GpuUsePolicy gpu_policy,
    LookStageOutput& out) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
