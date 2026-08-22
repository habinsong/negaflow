#pragma once

// 단계별 소요 시간입니다. **재기 전에는 "빨라졌다" 고 말할 수 없습니다.**
//
// 왜 이것이 먼저인가 — `docs/audit/13-performance-playbook.md` 0절:
// 이 저장소에는 오랫동안 단계별 계측기가 없었고, 그래서 "우측탭이 수 초" 라는 보고의
// 내역을 아무도 몰랐습니다. GPU 를 붙인 지금도 **검출 8,932 ms 가 얼마가 됐는지**
// 재지 않으면 알 수 없습니다.
//
// 켜는 법 — 둘 다 됩니다:
// · 환경 변수 `NEGA_TIMING=1` — 실행이 끝날 때 표를 stderr 로 찍습니다.
// 릴리스에서도 됩니다. 사용자 기계의 느림을 잡으려면 그래야 합니다.
// · `stage_timings()` 를 직접 읽습니다. CLI 가 그렇게 씁니다.
//
// **계측이 결과 화소를 바꾸면 안 됩니다.** 여기서 하는 일은 `QueryPerformanceCounter`
// 두 번과 덧셈뿐이고, 단계 안쪽에는 손대지 않습니다.
//
// 주의 이것은 **CPU 벽시계**입니다. GPU 디스패치는 비동기라 커널이 실제로 GPU 에서
// 얼마나 걸렸는지는 이 숫자에 안 나옵니다. 그것은 `ID3D11Query` 의
// `D3D11_QUERY_TIMESTAMP` 로 따로 재야 합니다(13 2.2절). 다만 **파이프라인이
// 다운로드에서 기다리므로**, 벽시계도 실제 체감과 크게 어긋나지 않습니다.

#include <cstdint>

#include "negaflow/pipeline/develop_export.h"

namespace negaflow::pipeline {

// `DevelopExportStage` 의 값 하나마다 한 칸입니다.
inline constexpr std::size_t stage_timing_slot_count = 32U;

struct StageTiming final {
    // 이 단계가 몇 번 돌았는지. 타일·반복이 있는 단계는 1보다 큽니다.
    std::uint32_t runs{0};
    // 누적 마이크로초.
    std::uint64_t elapsed_microseconds{0};
};

struct StageTimings final {
    StageTiming slots[stage_timing_slot_count]{};

    [[nodiscard]] std::uint64_t total_microseconds() const noexcept;
};

// 프로세스 전체 누적입니다. 여러 스레드가 더할 수 있어 원자로 쌓습니다.
[[nodiscard]] StageTimings stage_timings() noexcept;

// 다음 측정을 위해 0 으로 되돌립니다. CLI 가 한 번 돌리기 전에 부릅니다.
void reset_stage_timings() noexcept;

// 한 단계의 소요를 더합니다. `RunTracker` 가 부릅니다.
void record_stage_timing(DevelopExportStage stage, std::uint64_t microseconds) noexcept;

// 표를 stderr 로 찍습니다. `NEGA_TIMING` 이 켜져 있으면 실행 끝에 저절로 불립니다.
void dump_stage_timings() noexcept;

// `NEGA_TIMING` 이 켜져 있는지.
[[nodiscard]] bool stage_timing_enabled() noexcept;

} // namespace negaflow::pipeline
