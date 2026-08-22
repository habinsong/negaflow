#pragma once

// 영속 워커 풀입니다. `run_row_blocks` 가 이것을 씁니다.
//
// 왜 만드나 — 이전에는 **호출마다 `std::thread` 를 새로 만들었습니다.** 큰 이미지 한 장에서는
// 묻히지만 작은 작업에서는 생성 비용이 이득을 먹습니다. 실측
// (`docs/audit/13-performance-playbook.md` 19절): 256×171 표본 격자를 나눴더니
// **25 ms 느려졌습니다.**
//
// **교착을 만들지 않는 것이 이 파일의 유일한 어려움입니다.**
// 워커가 돌던 중에 다시 `run_row_blocks` 를 부를 수 있습니다(단계 안에서 단계). 그때
// 자기가 낸 일을 자기가 기다리면 멈춥니다. 그래서 **예약 없이는 절대 큐에 넣지 않고**,
// 예약은 프로세스 전체 예산(`hardware - 1`)을 넘지 못하며, 풀의 스레드 수도 같습니다 —
// 예약이 K 개 잡혔다는 것은 **놀고 있는 워커가 K 개 있다는 뜻**입니다.
// 예약이 0 이면 호출한 스레드가 전부 직접 돕니다(이전과 같은 폴백).

#include <atomic>
#include <cstdint>

namespace negaflow::core::row_block_pool_detail {

using BlockFunction = void (*)(void* context, std::uint32_t first_row, std::uint32_t row_count);

// 호출부가 스택에 두는 완료 계수기입니다. 워커가 블록을 끝낼 때마다 하나 줄입니다.
//
// **원자값 하나뿐입니다 — 뮤텍스도 조건변수도 여기 두지 않습니다.**
// 예전에는 여기에 뮤텍스·조건변수가 있었고, 워커가 "줄이고 알리는" 동안 대기자가
// 깨어 돌아가며 이 구조체를 **스택에서 없앨 수 있었습니다.** 그러면 워커가 사라진
// 뮤텍스를 만집니다(use-after-free). 알림을 잠금 안으로 옮겨 창을 좁혔지만,
// "남이 막 풀어 준 뮤텍스를 곧바로 없애는" 창은 원리적으로 남았습니다.
//
// 그래서 기다림에 쓰는 뮤텍스·조건변수를 **풀이 소유**합니다(풀은 프로세스 수명입니다).
// 워커가 이 구조체를 만지는 **마지막 순간은 `fetch_sub` 하나**이고, 대기자는 그
// 값이 0 이 된 것을 본 뒤에만 돌아옵니다 — 그 뒤로 워커가 만질 것이 없습니다.
struct PendingCounter final {
    std::atomic<std::uint32_t> remaining{0U};
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

} // namespace negaflow::core::row_block_pool_detail
