#pragma once

// 영속 워커 풀입니다. `run_row_blocks` 가 이것을 씁니다.
//
// 왜 만드나 — 이전에는 **호출마다 `std::thread` 를 새로 만들었습니다.** 큰 이미지 한 장에서는
// 묻히지만 작은 작업에서는 생성 비용이 이득을 먹습니다. 실측
// (`docs/audit/13-performance-playbook.md` 19절): 256×171 표본 격자를 나눴더니
// **25 ms 느려졌습니다.**
//
// ☠️ **교착을 만들지 않는 것이 이 파일의 유일한 어려움입니다.**
//    워커가 돌던 중에 다시 `run_row_blocks` 를 부를 수 있습니다(단계 안에서 단계). 그때
//    자기가 낸 일을 자기가 기다리면 멈춥니다. 그래서 **예약 없이는 절대 큐에 넣지 않고**,
//    예약은 프로세스 전체 예산(`hardware - 1`)을 넘지 못하며, 풀의 스레드 수도 같습니다 —
//    예약이 K 개 잡혔다는 것은 **놀고 있는 워커가 K 개 있다는 뜻**입니다.
//    예약이 0 이면 호출한 스레드가 전부 직접 돕니다(이전과 같은 폴백).

#include <condition_variable>
#include <cstdint>
#include <mutex>

namespace negaflow::core::row_block_pool_detail {

using BlockFunction = void (*)(void* context, std::uint32_t first_row, std::uint32_t row_count);

// 호출부가 스택에 두는 완료 계수기입니다. 워커가 블록을 끝낼 때마다 하나 줄입니다.
struct PendingCounter final {
    std::mutex lock{};
    std::condition_variable done{};
    std::uint32_t remaining{0U};
};

// 블록 하나를 워커에게 넘깁니다. `pending` 은 호출부가 소유하며, 워커가 일을 끝내면
// 하나 줄입니다. 넘기지 못했으면 거짓 — 호출부가 직접 돌아야 합니다.
[[nodiscard]] bool submit(
    BlockFunction function,
    void* context,
    std::uint32_t first_row,
    std::uint32_t row_count,
    PendingCounter& pending) noexcept;

// `pending` 이 0 이 될 때까지 기다립니다.
void wait_for(PendingCounter& pending) noexcept;

// 지금 풀이 들고 있는 워커 수. 진단·시험용입니다.
[[nodiscard]] std::uint32_t worker_count() noexcept;

}  // namespace negaflow::core::row_block_pool_detail
