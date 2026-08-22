#include "negaflow/pipeline/stage_timing.h"

#include "negaflow/pipeline/gpu_accelerator.h"

#include <atomic>
#include <cstdio>
#include <cstdlib>

namespace negaflow::pipeline {
namespace {

// 여러 워커가 같은 단계를 동시에 돌 수 있으므로 원자로 쌓습니다. `relaxed` 로 충분합니다 —
// 순서가 아니라 합만 필요하고, 읽는 쪽은 실행이 끝난 뒤입니다.
struct AtomicSlot final {
    std::atomic<std::uint32_t> runs{0};
    std::atomic<std::uint64_t> elapsed{0};
};

AtomicSlot slots[stage_timing_slot_count]{};

[[nodiscard]] bool timing_environment_set() noexcept {
    std::size_t length = 0U;
    return getenv_s(&length, nullptr, 0U, "NEGA_TIMING") == 0 && length > 0U;
}

} // namespace

std::uint64_t StageTimings::total_microseconds() const noexcept {
    std::uint64_t total = 0U;
    for (const StageTiming& slot : slots) {
        total += slot.elapsed_microseconds;
    }
    return total;
}

bool stage_timing_enabled() noexcept {
    // 한 번만 봅니다. 환경 변수를 매 단계 읽으면 그 자체가 계측을 왜곡합니다.
    static const bool enabled = [] {
        const bool on = timing_environment_set();
        if (on) {
            // 헤더가 약속한 "실행이 끝날 때 표를 찍습니다"를 여기서 지킵니다. 지금까지는
            // CLI 만 `dump_stage_timings()` 를 명시적으로 불렀고, **셸과 시험 하네스는
            // 아무 표도 못 봤습니다** — 사용자가 실제로 쓰는 경로가 그쪽인데도.
            // 등록은 켜졌을 때 한 번뿐이고, 꺼져 있으면 아무 일도 하지 않습니다.
            (void)std::atexit([]() noexcept { dump_stage_timings(); });
        }
        return on;
    }();
    return enabled;
}

void record_stage_timing(
    const DevelopExportStage stage,
    const std::uint64_t microseconds) noexcept {
    const auto index = static_cast<std::size_t>(stage);
    if (index >= stage_timing_slot_count) {
        return;
    }
    slots[index].runs.fetch_add(1U, std::memory_order_relaxed);
    slots[index].elapsed.fetch_add(microseconds, std::memory_order_relaxed);
}

StageTimings stage_timings() noexcept {
    StageTimings snapshot{};
    for (std::size_t index = 0U; index < stage_timing_slot_count; ++index) {
        snapshot.slots[index].runs = slots[index].runs.load(std::memory_order_relaxed);
        snapshot.slots[index].elapsed_microseconds =
            slots[index].elapsed.load(std::memory_order_relaxed);
    }
    return snapshot;
}

void reset_stage_timings() noexcept {
    for (AtomicSlot& slot : slots) {
        slot.runs.store(0U, std::memory_order_relaxed);
        slot.elapsed.store(0U, std::memory_order_relaxed);
    }
}

void dump_stage_timings() noexcept {
    const StageTimings snapshot = stage_timings();
    const std::uint64_t total = snapshot.total_microseconds();
    if (total == 0U) {
        return;
    }
    (void)std::fputs("[timing] stage runs ms share\n", stderr);
    for (std::size_t index = 0U; index < stage_timing_slot_count; ++index) {
        const StageTiming& slot = snapshot.slots[index];
        if (slot.runs == 0U) {
            continue;
        }
        const double milliseconds = static_cast<double>(slot.elapsed_microseconds) / 1000.0;
        const double share =
            (static_cast<double>(slot.elapsed_microseconds) * 100.0) / static_cast<double>(total);
        (void)std::fprintf(
            stderr,
            "[timing] %-24s %6u %9.2f %7.1f%%\n",
            develop_export_stage_name(static_cast<DevelopExportStage>(index)),
            slot.runs,
            milliseconds,
            share);
    }
    (void)std::fprintf(
        stderr,
        "[timing] %-24s %6s %9.2f %7s\n",
        "TOTAL",
        "",
        static_cast<double>(total) / 1000.0,
        "");
    // 단계 시간만 보면 **GPU 를 쓰고 있는지 알 수 없습니다.** 사슬이 GPU 에 머물면
    // 왕복이 0 이고, 어느 단계가 호스트로 내리면 그 자리에서 downloads 가 오릅니다.
    // "GPU 를 쓴다"는 말을 숫자로 확인하는 유일한 자리입니다.
    const GpuHostTransferStats transfers = gpu_host_transfer_stats();
    (void)std::fprintf(
        stderr,
        "[timing] gpu round trips up=%llu (%llu px) down=%llu (%llu px, %.1f MB)\n",
        static_cast<unsigned long long>(transfers.uploads),
        static_cast<unsigned long long>(transfers.uploaded_pixels),
        static_cast<unsigned long long>(transfers.downloads),
        static_cast<unsigned long long>(transfers.downloaded_pixels),
        static_cast<double>(transfers.downloaded_bytes) / (1024.0 * 1024.0));
}

} // namespace negaflow::pipeline
