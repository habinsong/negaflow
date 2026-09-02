#include "negaflow/pipeline/stage_timing.h"

#include "negaflow/pipeline/gpu_accelerator.h"

#include "negaflow/imaging/scanner_target_grade.h"

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <string>

#include <Windows.h>

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

// 표를 stderr 에만 쓰면 **앱에서는 아무도 못 봅니다** — MSIX 셸에는 콘솔이 없습니다.
// CLI 로 대신 재면 같은 자리를 재는 것이 아닙니다(요청 조립도 캐시 상태도 다릅니다).
// 그래서 켜져 있을 때는 로그 폴더에도 같은 줄을 남깁니다. `NEGA_TIMING` 이 없으면
// 이 함수는 아무 일도 하지 않습니다.
std::FILE* timing_log() noexcept {
    static std::FILE* const file = [] () -> std::FILE* {
        char folder[MAX_PATH]{};
        std::size_t length = 0U;
        if (getenv_s(&length, folder, sizeof(folder), "LOCALAPPDATA") != 0 || length == 0U) {
            return nullptr;
        }
        std::string path{folder};
        path += "\\Negaflow\\Logs";
        ::CreateDirectoryA(path.c_str(), nullptr);
        path += "\\stage-timing.txt";
        std::FILE* opened = nullptr;
        if (::fopen_s(&opened, path.c_str(), "ab") != 0) {
            return nullptr;
        }
        return opened;
    }();
    return file;
}

void emit(const char* const line) noexcept {
    (void)std::fputs(line, stderr);
    if (std::FILE* const file = timing_log(); file != nullptr) {
        (void)std::fputs(line, file);
        (void)std::fflush(file);
    }
}

template <typename... Args>
void emitf(const char* const format, Args... args) noexcept {
    char line[512]{};
    (void)std::snprintf(line, sizeof(line), format, args...);
    emit(line);
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
    emit("[timing] stage runs ms share\n");
    for (std::size_t index = 0U; index < stage_timing_slot_count; ++index) {
        const StageTiming& slot = snapshot.slots[index];
        if (slot.runs == 0U) {
            continue;
        }
        const double milliseconds = static_cast<double>(slot.elapsed_microseconds) / 1000.0;
        const double share =
            (static_cast<double>(slot.elapsed_microseconds) * 100.0) / static_cast<double>(total);
        emitf(
            "[timing] %-24s %6u %9.2f %7.1f%%\n",
            develop_export_stage_name(static_cast<DevelopExportStage>(index)),
            slot.runs,
            milliseconds,
            share);
    }
    emitf(
        "[timing] %-24s %6s %9.2f %7s\n",
        "TOTAL",
        "",
        static_cast<double>(total) / 1000.0,
        "");
    // 단계 시간만 보면 **GPU 를 쓰고 있는지 알 수 없습니다.** 사슬이 GPU 에 머물면
    // 왕복이 0 이고, 어느 단계가 호스트로 내리면 그 자리에서 downloads 가 오릅니다.
    // "GPU 를 쓴다"는 말을 숫자로 확인하는 유일한 자리입니다.
    const GpuHostTransferStats transfers = gpu_host_transfer_stats();
    emitf(
        "[timing] gpu round trips up=%llu (%llu px) down=%llu (%llu px, %.1f MB)\n",
        static_cast<unsigned long long>(transfers.uploads),
        static_cast<unsigned long long>(transfers.uploaded_pixels),
        static_cast<unsigned long long>(transfers.downloads),
        static_cast<unsigned long long>(transfers.downloaded_pixels),
        static_cast<double>(transfers.downloaded_bytes) / (1024.0 * 1024.0));
    const GpuAccelerator& accelerator = GpuAccelerator::shared();
    const char* const adapter = accelerator.adapter_description();
    emitf(
        "[timing] gpu adapter=%s available=%s\n",
        adapter != nullptr && adapter[0] != '\0' ? adapter : "none",
        accelerator.available() ? "true" : "false");
    // 가장 비싼 단계가 실제로 어느 쪽으로 갔는지입니다. 커널은 실패해도 조용히 CPU 로
    // 물러나므로, 이 줄이 없으면 "GPU 를 쓴다" 는 말을 확인할 방법이 없습니다.
    const imaging::TargetGradeRouteCounts route = imaging::target_grade_route_counts();
    emitf(
        "[timing] target_grade route gpu=%llu cpu=%llu\n",
        static_cast<unsigned long long>(route.gpu),
        static_cast<unsigned long long>(route.cpu));
}

} // namespace negaflow::pipeline
