#include "row_block_pool.h"

#include <atomic>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <thread>
#include <vector>

namespace negaflow::core::row_block_pool_detail {
namespace {

struct Task final {
    BlockFunction function{nullptr};
    void* context{nullptr};
    std::uint32_t first_row{0U};
    std::uint32_t row_count{0U};
    PendingCounter* pending{nullptr};
};

[[nodiscard]] std::uint32_t hardware_threads() noexcept {
    const unsigned reported = std::thread::hardware_concurrency();
    return reported == 0U ? 1U : static_cast<std::uint32_t>(reported);
}

class Pool final {
public:
    Pool() {
        // 호출한 스레드가 언제나 블록 하나를 맡으므로 워커는 `hardware - 1` 개입니다.
        // `run_row_blocks` 의 예약 예산과 **같은 수**여야 합니다 — 예약이 잡혔다는 것이
        // 곧 놀고 있는 워커가 있다는 뜻이 되도록.
        const std::uint32_t hardware = hardware_threads();
        const std::uint32_t wanted = hardware > 1U ? hardware - 1U : 0U;
        workers_.reserve(wanted);
        for (std::uint32_t index = 0U; index < wanted; ++index) {
            try {
                workers_.emplace_back([this]() noexcept { run(); });
            } catch (...) {
                // 만들 수 있는 만큼만 씁니다. 모자라면 호출부가 직접 돕니다.
                break;
            }
        }
    }

    ~Pool() {
        {
            const std::lock_guard<std::mutex> guard{lock_};
            stopping_ = true;
        }
        available_.notify_all();
        for (std::thread& worker : workers_) {
            if (worker.joinable()) {
                worker.join();
            }
        }
    }

    Pool(const Pool&) = delete;
    Pool& operator=(const Pool&) = delete;

    [[nodiscard]] bool submit(Task task) noexcept {
        if (workers_.empty()) {
            return false;
        }
        {
            const std::lock_guard<std::mutex> guard{lock_};
            if (stopping_) {
                return false;
            }
            try {
                queue_.push_back(task);
            } catch (...) {
                return false;
            }
        }
        available_.notify_one();
        return true;
    }

    [[nodiscard]] std::uint32_t size() const noexcept {
        return static_cast<std::uint32_t>(workers_.size());
    }

private:
    void run() noexcept {
        for (;;) {
            Task task{};
            {
                std::unique_lock<std::mutex> guard{lock_};
                available_.wait(guard, [this]() noexcept {
                    return stopping_ || !queue_.empty();
                });
                if (stopping_ && queue_.empty()) {
                    return;
                }
                task = queue_.front();
                queue_.pop_front();
            }
            task.function(task.context, task.first_row, task.row_count);
            // ☠️ **여기가 호출부 계수기를 만지는 마지막 순간입니다.**
            //    원자값 하나만 줄이고, 그 뒤로는 계수기를 두 번 다시 만지지 않습니다.
            //    알림에 쓰는 뮤텍스·조건변수는 **풀의 것**이라 프로세스가 끝날 때까지
            //    살아 있습니다. 그래서 대기자가 0 을 보고 곧바로 스택의 계수기를
            //    없애도 워커가 사라진 객체를 만질 일이 없습니다.
            //
            //    예전에는 계수기 안에 뮤텍스·조건변수가 있었고, 그것이
            //    `native.gpu_film_scan` 이 27회 중 3회 SegFault 로 죽던 자리였습니다
            //    (docs/audit/01-backend-gaps.md 9.4).
            task.pending->remaining.fetch_sub(1U, std::memory_order_acq_rel);
            notify_completed();
        }
    }

    // 어떤 계수기가 0 이 됐는지 구분하지 않습니다 — 깨어난 대기자가 **자기 원자값**을
    // 다시 봅니다. 한 번에 도는 블록 수가 `hardware - 1` 을 넘지 않으므로 헛깨움 비용은
    // 작습니다.
    void notify_completed() noexcept {
        // 잠금을 잡은 채 알립니다. 대기자가 술어를 보고 기다림에 들어가는 사이에
        // 알림이 새어 나가지 않게 하는 가장 단순한 형태입니다 — 이 잠금은 **풀의 것**이라
        // 없어질 걱정이 없습니다.
        const std::lock_guard<std::mutex> guard{completion_lock_};
        completed_.notify_all();
    }

public:
    // 계수기가 0 이 될 때까지 기다립니다. 술어는 **대기자 자신의 원자값**만 읽습니다.
    void wait_until_zero(PendingCounter& pending) noexcept {
        if (pending.remaining.load(std::memory_order_acquire) == 0U) {
            return;
        }
        std::unique_lock<std::mutex> guard{completion_lock_};
        completed_.wait(guard, [&pending]() noexcept {
            return pending.remaining.load(std::memory_order_acquire) == 0U;
        });
    }

private:
    mutable std::mutex lock_{};
    std::condition_variable available_{};
    // 완료를 알리는 자리입니다. **풀이 소유**하므로 호출부 스택이 사라져도 살아 있습니다.
    std::mutex completion_lock_{};
    std::condition_variable completed_{};
    std::deque<Task> queue_{};
    std::vector<std::thread> workers_{};
    bool stopping_{false};
};

// 프로세스 수명 동안 하나입니다. 첫 사용에서 만들어집니다.
//
// ☠️ **일부러 지우지 않습니다.** 정적 소멸 순서에서 워커가 이미 정리된 다른 정적을 만지면
//    종료가 깨집니다. 프로세스가 끝나면 OS 가 회수합니다.
[[nodiscard]] Pool& pool() noexcept {
    static Pool* const instance = new Pool{};
    return *instance;
}

}  // namespace

bool submit(
    const BlockFunction function,
    void* const context,
    const std::uint32_t first_row,
    const std::uint32_t row_count,
    PendingCounter& pending) noexcept {
    if (function == nullptr || row_count == 0U) {
        return false;
    }
    PendingCounter* const counter = &pending;
    counter->remaining.fetch_add(1U, std::memory_order_relaxed);
    const Task task{function, context, first_row, row_count, counter};
    if (pool().submit(task)) {
        return true;
    }
    // 못 넣었으면 올린 수를 되돌립니다 — 안 그러면 아래 `wait_for` 가 영원히 기다립니다.
    counter->remaining.fetch_sub(1U, std::memory_order_acq_rel);
    return false;
}

void wait_for(PendingCounter& pending) noexcept { pool().wait_until_zero(pending); }

std::uint32_t worker_count() noexcept { return pool().size(); }

}  // namespace negaflow::core::row_block_pool_detail
