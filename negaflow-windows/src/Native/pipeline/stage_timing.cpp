#include "negaflow/pipeline/stage_timing.h"

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

}  // namespace

std::uint64_t StageTimings::total_microseconds() const noexcept {
    std::uint64_t total = 0U;
    for (const StageTiming& slot : slots) {
        total += slot.elapsed_microseconds;
    }
    return total;
}

bool stage_timing_enabled() noexcept {
    // 한 번만 봅니다. 환경 변수를 매 단계 읽으면 그 자체가 계측을 왜곡합니다.
    static const bool enabled = timing_environment_set();
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
    (void)std::fputs("[timing] stage                     runs        ms     share\n", stderr);
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
}

}  // namespace negaflow::pipeline
