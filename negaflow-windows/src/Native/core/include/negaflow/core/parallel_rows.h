#pragma once

#include <atomic>
#include <cstdint>
#include <utility>

namespace negaflow::core {

// Row-block execution for passes whose rows are independent.
//
// The body receives a half-open row range and must not read or write outside it, so the
// result is identical to running every row in order on one thread. That is the whole
// contract: this helper exists to spend idle cores, never to change a number.
//
// Callers that report a first failure must record the failing row and pick the smallest
// one across blocks; the blocks themselves finish in an unspecified order.
using RowBlockFunction = void (*)(
    void* context,
    std::uint32_t first_row,
    std::uint32_t row_count) noexcept;

// Below this much estimated work the split is not worth the thread hand-off and the body
// runs inline on the calling thread.
//
// **`work_units` 를 적게 넘기면 병렬화가 조용히 꺼집니다.** 경고도, 실패도, 로그도
// 없습니다 — 그냥 호출한 스레드에서 통째로 돕니다. 출력행 수만 넘기고 각 행이 원본을
// 수십 배로 읽는 단계라면 문턱을 못 넘어 **직렬로 돌면서 "병렬화해도 안 빨라진다" 는
// 거짓 결론**을 냅니다. 실제로 `tone_curve_measurement.cpp` 에서 두 번 그랬습니다
// (`docs/audit/13-performance-playbook.md` 21절).
//
// **넘기는 값은 출력 크기가 아니라 실제로 읽고 쓰는 양이어야 합니다.**
// 쪼개졌는지 확인하려면 `parallel_rows.cpp` 의 `NEGA_ROW_BLOCK_TRACE` 를 켜십시오.
inline constexpr std::uint64_t minimum_parallel_row_work_units = 1ULL << 20U;

// Upper bound on blocks per call, independent of core count. A wider split only adds
// scheduling noise on the image sizes this engine sees.
inline constexpr std::uint32_t maximum_row_blocks = 32U;

// Runs the body over [0, height) split into contiguous blocks and returns once every
// block has finished. `work_units` is the caller's own cost estimate (pixels, or pixels
// times a per-pixel weight); it only decides whether splitting is worthwhile.
//
// The number of extra threads is drawn from a process-wide budget, so developing several
// photos at once does not multiply the thread count by the number of photos in flight.
// If no budget or no thread is available the work still completes — inline, on the
// calling thread.
void run_row_blocks(
    std::uint32_t height,
    std::uint64_t work_units,
    RowBlockFunction function,
    void* context) noexcept;

// Convenience wrapper for a callable. The callable is invoked concurrently from several
// threads with disjoint row ranges, so anything it captures by reference must either be
// read-only or be indexed by row.
template <typename Body>
void for_each_row_block(
    const std::uint32_t height,
    const std::uint64_t work_units,
    Body body) noexcept {
    run_row_blocks(
        height,
        work_units,
        [](void* const context,
           const std::uint32_t first_row,
           const std::uint32_t row_count) noexcept {
            (*static_cast<Body*>(context))(first_row, row_count);
        },
        static_cast<void*>(&body));
}

// Extra threads this process has handed out right now. Test-only observation point.
[[nodiscard]] std::uint32_t active_row_block_threads() noexcept;

// Smallest-row failure reduction.
//
// A single-threaded raster scan reports the first failure it meets. Row blocks finish in
// an unspecified order, so each block records the row it failed on and the smallest row
// wins. Packing the row above the status makes that an integer minimum, and two blocks
// can never record the same row because a block stops at its own first failure.
inline constexpr std::uint64_t no_row_failure = ~std::uint64_t{0};

inline void record_row_failure_value(
    std::atomic<std::uint64_t>& slot,
    const std::uint32_t row,
    const std::uint32_t status_value) noexcept {
    const std::uint64_t candidate =
        (static_cast<std::uint64_t>(row) << 32U) | static_cast<std::uint64_t>(status_value);
    std::uint64_t current = slot.load(std::memory_order_relaxed);
    while (candidate < current &&
           !slot.compare_exchange_weak(
               current,
               candidate,
               std::memory_order_relaxed,
               std::memory_order_relaxed)) {
    }
}

template <typename Status>
void record_row_failure(
    std::atomic<std::uint64_t>& slot,
    const std::uint32_t row,
    const Status status) noexcept {
    record_row_failure_value(slot, row, static_cast<std::uint32_t>(status));
}

[[nodiscard]] inline bool has_row_failure(const std::uint64_t packed) noexcept {
    return packed != no_row_failure;
}

[[nodiscard]] inline std::uint32_t row_failure_status_value(
    const std::uint64_t packed) noexcept {
    return static_cast<std::uint32_t>(packed & 0xFFFFFFFFULL);
}

} // namespace negaflow::core
