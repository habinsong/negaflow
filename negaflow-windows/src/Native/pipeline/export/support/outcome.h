#pragma once

#include "negaflow/pipeline/develop_export.h"

#include <cstdint>
#include <optional>

#include "negaflow/imaging/scanner_to_working.h"

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

// **단계가 화소 버퍼를 들고 죽는 자리마다 이것을 지나가야 합니다.**
//
// 상주 프레임은 **남의 버퍼를 가리키는 생포인터**입니다. 단계가 실패·취소로 일찍
// 돌아가면 그 버퍼는 단계가 끝나며 사라지는데 묶음은 남고, 스코프가 끝날 때
// `flush_unlocked` 가 **해제된 메모리에 memcpy** 합니다 — 2026-08-20 크래시
// (스택: `~GpuResidentScope` → `end_resident` → `flush_unlocked` → `copy_rows`).
//
// 예전에는 `develop_export.cpp` 가 단계에 **넘기기 전에** 무조건 내려서 이 문제를
// 피했습니다. 그런데 `std::vector` 이동은 버퍼 주소를 그대로 두므로, 항등 단계를
// 지나는 흔한 경우에도 매번 내렸다가 다시 올렸습니다. 실측(1536 슬라이더 한 틱):
// 업로드 2회 + 다운로드 3회 = 약 125 MB. 게다가 그 때문에 grain·finish·publish 의
// **상주 갈래가 한 번도 안 돌았습니다.**
//
// 그래서 지금은 **버퍼가 실제로 죽는 자리에서만** 내립니다. 인자로 받은 이미지는
// 아직 살아 있으므로(반환값을 만든 뒤에 소멸합니다) 여기서 내리는 것이 안전합니다.
[[nodiscard]] std::optional<DevelopExportOutcome> unbind_resident_and(
    const negaflow::imaging::WorkingImage& image,
    std::optional<DevelopExportOutcome> outcome) noexcept;

} // namespace negaflow::pipeline::develop_export_detail
