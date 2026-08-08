import XCTest
@testable import negaflowApp

// AsyncSemaphore 계약 검증: 폭 제한, 슬롯 이관, 취소된 대기자의 즉시 이탈과 카운트 무결성.
final class AsyncSemaphoreTests: XCTestCase {

    /// 폭 2 세마포어에서 동시 실행이 2를 넘지 않는다.
    func testWidthBoundsConcurrency() async throws {
        let semaphore = AsyncSemaphore(width: 2)
        let tracker = ConcurrencyTracker()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    guard (try? await semaphore.acquire()) != nil else { return }
                    await tracker.enter()
                    try? await Task.sleep(nanoseconds: 10_000_000)
                    await tracker.exit()
                    await semaphore.release()
                }
            }
        }
        let observedMax = await tracker.maxObserved
        let entries = await tracker.totalEntries
        XCTAssertEqual(entries, 8, "모든 태스크가 슬롯을 받아야 한다.")
        XCTAssertLessThanOrEqual(observedMax, 2, "동시 실행이 폭(2)을 넘으면 안 된다.")
    }

    /// 대기 중 취소 → 보유자가 release 하지 않아도 즉시 CancellationError 로 이탈한다.
    @MainActor
    func testCancelledWaiterLeavesImmediately() async throws {
        let semaphore = AsyncSemaphore(width: 1)
        try await semaphore.acquire()   // 슬롯 점유(놓지 않음)

        let outcome = CancellationOutcome()
        let waiting = Task {
            do {
                try await semaphore.acquire()
                await outcome.record(.acquired)
                await semaphore.release()
            } catch {
                await outcome.record(error is CancellationError ? .cancelled : .otherError)
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)   // 대기 진입 보장
        waiting.cancel()
        _ = await waiting.value
        let recorded = await outcome.value
        XCTAssertEqual(recorded, .cancelled,
                       "대기 중 취소는 슬롯 없이 CancellationError 로 끝나야 한다.")

        // 카운트 무결성: 취소가 슬롯을 소모/증식하지 않았으므로 release 후 다시 얻을 수 있다.
        await semaphore.release()
        try await semaphore.acquire()
        await semaphore.release()
    }

    /// 이미 취소된 태스크의 acquire 는 즉시 던진다(대기열 오염 없음).
    func testAcquireOnCancelledTaskThrowsImmediately() async throws {
        let semaphore = AsyncSemaphore(width: 1)
        let task = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            do {
                try await semaphore.acquire()
                return false
            } catch {
                return error is CancellationError
            }
        }
        task.cancel()
        let threwCancellation = await task.value
        XCTAssertTrue(threwCancellation, "취소된 태스크의 acquire 는 CancellationError 여야 한다.")

        try await semaphore.acquire()
        await semaphore.release()
    }
}

private actor ConcurrencyTracker {
    private(set) var current = 0
    private(set) var maxObserved = 0
    private(set) var totalEntries = 0

    func enter() {
        current += 1
        totalEntries += 1
        maxObserved = max(maxObserved, current)
    }

    func exit() { current -= 1 }
}

private actor CancellationOutcome {
    enum Value { case acquired, cancelled, otherError }
    private(set) var value: Value?
    func record(_ newValue: Value) { value = newValue }
}
