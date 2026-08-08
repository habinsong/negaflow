import Foundation

/// 폭 제한 비동기 세마포어(FIFO). 폴더 가져오기 썸네일 디코드처럼 "동시에 몇 개만" 돌려야
/// 하는 백그라운드 작업의 IO·메모리 폭주를 막는다.
///
/// 취소: 대기 중 태스크가 취소되면 즉시 큐에서 빠지고 `CancellationError` 를 던진다 —
/// 슬롯을 받지 못했으므로 호출자는 `release()` 를 부르면 안 된다(groue/Semaphore 의
/// waitUnlessCancelled 계약과 동일). 슬롯을 받은 뒤에는 취소 여부와 무관하게 정확히 한 번
/// `release()` 한다.
///
/// 취소 레이스 안전성: `onCancel` 은 actor 밖에서 동기 실행되고 `cancelWaiter` 태스크는
/// actor 직렬화 때문에 `acquire()` 가 continuation 을 등록(또는 조기 리턴)한 뒤에만 진입한다.
/// 따라서 "등록 전에 취소가 처리돼 continuation 이 영원히 남는" 릭은 구조적으로 불가능하다.
actor AsyncSemaphore {
    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Void, Error>
    }

    private let width: Int
    private var active = 0
    private var waiters: [Waiter] = []
    private var nextWaiterID: UInt64 = 0

    init(width: Int) {
        self.width = max(1, width)
    }

    /// 슬롯을 얻을 때까지 대기한다. 대기 중 취소되면 `CancellationError`.
    func acquire() async throws {
        try Task.checkCancellation()
        if active < width {
            active += 1
            return
        }
        let id = nextWaiterID
        nextWaiterID &+= 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    func release() {
        if waiters.isEmpty {
            active = max(0, active - 1)
        } else {
            // FIFO 슬롯 이관: active 는 그대로 두고 다음 대기자를 깨운다.
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(id: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            // 이미 release() 가 슬롯을 넘겼거나 완료된 대기자 — 아무것도 하지 않는다.
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}
