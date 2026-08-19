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
            // ☠️ **알림은 잠금 안에서 합니다.** 밖에서 알리면 그 사이에 대기자가 깨어
            //    `remaining == 0` 을 보고 돌아가 버립니다 — 그러면 호출부 스택의
            //    `PendingCounter`(뮤텍스·조건변수)가 사라진 뒤에 이 스레드가 그것을
            //    만지게 됩니다. 2026-08-20 자동 레벨 크래시가 이 자리였습니다:
            //    사라진 계수기를 줄이는 바람에 다음 호출부의 대기가 일찍 풀렸고,
            //    아직 도는 워커가 이미 없어진 버퍼에 memcpy 했습니다
            //    (0xc0000005, 워커 스택 row_block_pool.cpp:37 → memcpy).
            {
                const std::lock_guard<std::mutex> guard{task.pending->lock};
                --task.pending->remaining;
                task.pending->done.notify_all();
            }
        }
    }

    mutable std::mutex lock_{};
    std::condition_variable available_{};
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
    {
        const std::lock_guard<std::mutex> guard{counter->lock};
        ++counter->remaining;
    }
    const Task task{function, context, first_row, row_count, counter};
    if (pool().submit(task)) {
        return true;
    }
    // 못 넣었으면 올린 수를 되돌립니다 — 안 그러면 아래 `wait_for` 가 영원히 기다립니다.
    {
        const std::lock_guard<std::mutex> guard{counter->lock};
        --counter->remaining;
    }
    return false;
}

void wait_for(PendingCounter& pending) noexcept {
    PendingCounter* const counter = &pending;
    std::unique_lock<std::mutex> guard{counter->lock};
    counter->done.wait(guard, [counter]() noexcept { return counter->remaining == 0U; });
}

std::uint32_t worker_count() noexcept { return pool().size(); }

}  // namespace negaflow::core::row_block_pool_detail
