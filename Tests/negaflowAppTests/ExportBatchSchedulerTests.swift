import XCTest
@testable import negaflowApp

@MainActor
private final class SchedulerRecorder {
    private(set) var finished: [Int] = []

    func record(_ value: Int) {
        finished.append(value)
    }
}

@MainActor
private final class SchedulerGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations = []
        pending.forEach { $0.resume() }
    }
}

@MainActor
final class ExportBatchSchedulerTests: XCTestCase {
    func testEveryElementRunsExactlyOnce() async {
        let recorder = SchedulerRecorder()

        await ExportBatchScheduler.run(Array(0..<7), maximumConcurrent: 3) { element in
            recorder.record(element)
        }

        XCTAssertEqual(recorder.finished.sorted(), Array(0..<7))
        XCTAssertEqual(Set(recorder.finished).count, 7)
    }

    func testSingleWorkerKeepsPlanOrder() async {
        let recorder = SchedulerRecorder()

        await ExportBatchScheduler.run(Array(0..<5), maximumConcurrent: 1) { element in
            recorder.record(element)
        }

        XCTAssertEqual(recorder.finished, Array(0..<5))
    }

    /// 한 장이 오래 걸려도 남은 항목이 그 뒤에 줄 서면 안 된다. 예전 stride 분배에서는 워커 0 이
    /// 짝수 인덱스를 예약해 가져서, 0 번이 막히면 2·4 번이 함께 멈췄다.
    func testSlowElementDoesNotBlockTheRemainingQueue() async throws {
        let gate = SchedulerGate()
        let recorder = SchedulerRecorder()
        let elements = Array(0..<6)

        let run = Task { @MainActor in
            await ExportBatchScheduler.run(elements, maximumConcurrent: 2) { element in
                if element == 0 {
                    await gate.wait()
                }
                recorder.record(element)
            }
        }

        let deadline = Date().addingTimeInterval(5)
        while recorder.finished.count < elements.count - 1, Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertEqual(
            recorder.finished.sorted(),
            Array(1..<6),
            "the fast worker must drain every remaining item while element 0 is blocked"
        )

        gate.open()
        await run.value
        XCTAssertEqual(recorder.finished.sorted(), elements)
    }

    func testEmptyPlanListCompletesImmediately() async {
        let recorder = SchedulerRecorder()

        await ExportBatchScheduler.run([Int](), maximumConcurrent: 4) { element in
            recorder.record(element)
        }

        XCTAssertTrue(recorder.finished.isEmpty)
    }

    func testWorkerCountIsClampedToElementCount() async {
        let recorder = SchedulerRecorder()

        await ExportBatchScheduler.run([42], maximumConcurrent: 8) { element in
            recorder.record(element)
        }

        XCTAssertEqual(recorder.finished, [42])
    }
}
