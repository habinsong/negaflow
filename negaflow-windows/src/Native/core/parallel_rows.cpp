#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <thread>

namespace negaflow::core {
namespace {

// Extra threads currently handed out across the whole process. A second photo being
// developed concurrently sees a smaller budget rather than starting its own full fan-out.
std::atomic<std::uint32_t> g_active_extra_threads{0U};

[[nodiscard]] std::uint32_t hardware_threads() noexcept {
    const unsigned reported = std::thread::hardware_concurrency();
    return reported == 0U ? 1U : static_cast<std::uint32_t>(reported);
}

// The calling thread always runs one block, so the process-wide cap counts only the
// threads this helper creates.
[[nodiscard]] std::uint32_t extra_thread_budget() noexcept {
    const std::uint32_t hardware = hardware_threads();
    return hardware > 1U ? hardware - 1U : 0U;
}

[[nodiscard]] std::uint32_t reserve_extra_threads(const std::uint32_t wanted) noexcept {
    if (wanted == 0U) {
        return 0U;
    }
    const std::uint32_t budget = extra_thread_budget();
    std::uint32_t active = g_active_extra_threads.load(std::memory_order_relaxed);
    for (;;) {
        const std::uint32_t available = budget > active ? budget - active : 0U;
        const std::uint32_t take = std::min(wanted, available);
        if (take == 0U) {
            return 0U;
        }
        if (g_active_extra_threads.compare_exchange_weak(
                active,
                active + take,
                std::memory_order_relaxed,
                std::memory_order_relaxed)) {
            return take;
        }
    }
}

void release_extra_threads(const std::uint32_t count) noexcept {
    if (count != 0U) {
        g_active_extra_threads.fetch_sub(count, std::memory_order_relaxed);
    }
}

struct RowBlock final {
    std::uint32_t first_row{0U};
    std::uint32_t row_count{0U};
};

[[nodiscard]] RowBlock block_at(
    const std::uint32_t height,
    const std::uint32_t block_count,
    const std::uint32_t index) noexcept {
    // Even split with the remainder spread over the leading blocks, so no block is more
    // than one row larger than any other.
    const std::uint32_t base = height / block_count;
    const std::uint32_t remainder = height % block_count;
    const std::uint32_t extra_before = std::min(index, remainder);
    const std::uint32_t first_row = (index * base) + extra_before;
    const std::uint32_t row_count = base + (index < remainder ? 1U : 0U);
    return RowBlock{first_row, row_count};
}

}  // namespace

std::uint32_t active_row_block_threads() noexcept {
    return g_active_extra_threads.load(std::memory_order_relaxed);
}

void run_row_blocks(
    const std::uint32_t height,
    const std::uint64_t work_units,
    const RowBlockFunction function,
    void* const context) noexcept {
    if (height == 0U || function == nullptr) {
        return;
    }

    const bool worth_splitting =
        height > 1U && work_units >= minimum_parallel_row_work_units;
    std::uint32_t desired_blocks = 1U;
    if (worth_splitting) {
        desired_blocks = std::min(hardware_threads(), height);
        desired_blocks = std::min(desired_blocks, maximum_row_blocks);
    }

    const std::uint32_t reserved =
        desired_blocks > 1U ? reserve_extra_threads(desired_blocks - 1U) : 0U;
    if (reserved == 0U) {
        function(context, 0U, height);
        return;
    }

    const std::uint32_t block_count = reserved + 1U;
    std::array<std::thread, maximum_row_blocks> workers{};
    std::uint32_t started = 0U;
    for (std::uint32_t index = 1U; index < block_count; ++index) {
        const RowBlock block = block_at(height, block_count, index);
        if (block.row_count == 0U) {
            continue;
        }
        try {
            workers[started] = std::thread(
                [function, context, block]() noexcept {
                    function(context, block.first_row, block.row_count);
                });
            ++started;
        } catch (...) {
            // Thread creation is the only failure here and it is recoverable: run the
            // block inline so the pass still covers every row.
            function(context, block.first_row, block.row_count);
        }
    }

    const RowBlock own = block_at(height, block_count, 0U);
    if (own.row_count != 0U) {
        function(context, own.first_row, own.row_count);
    }

    for (std::uint32_t index = 0U; index < started; ++index) {
        workers[index].join();
    }
    release_extra_threads(reserved);
}

}  // namespace negaflow::core
