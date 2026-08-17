#pragma once

#include "negaflow/pipeline/develop_export.h"

#include <cstdint>

namespace negaflow::pipeline::develop_export_detail {

// 단계 실패를 호출자가 읽을 수 있는 outcome 으로 만든다. 성공 경로는 쓰지 않는다.
[[nodiscard]] DevelopExportOutcome fail(
    DevelopExportStage stage,
    const char* name,
    std::uint32_t native_error_code = 0U,
    std::uint32_t cleanup_error_code = 0U) noexcept;

// 취소 래치가 단계를 끊었을 때 쓴다. `cancelled` 만 추가하고 나머지는 fail 과 같다.
[[nodiscard]] DevelopExportOutcome cancelled_outcome(
    DevelopExportStage stage) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
