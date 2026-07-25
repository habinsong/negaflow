import XCTest
@testable import negaflowApp

@MainActor
final class DevelopControllerTests: XCTestCase {
    func testDevelopSlotsThrottleDifferentFrames() async throws {
        let controller = DevelopController(maxConcurrentDevelopments: 2)

        let firstSlotAcquired = await controller.acquireDevelopSlot()
        let secondSlotAcquired = await controller.acquireDevelopSlot()
        XCTAssertTrue(firstSlotAcquired)
        XCTAssertTrue(secondSlotAcquired)

        var thirdSlotAcquired = false
        let waitingTask = Task { @MainActor in
            guard await controller.acquireDevelopSlot() else { return }
            thirdSlotAcquired = true
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(thirdSlotAcquired, "40+ frame rolls must not start every frame render at once")

        controller.releaseDevelopSlot()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(thirdSlotAcquired, "Queued frame render should start when a slot is released")

        controller.releaseDevelopSlot()
        controller.releaseDevelopSlot()
        waitingTask.cancel()
    }

    func testCanceledDevelopSlotWaiterDoesNotRenderLater() async throws {
        let controller = DevelopController(maxConcurrentDevelopments: 1)
        let firstSlotAcquired = await controller.acquireDevelopSlot()
        XCTAssertTrue(firstSlotAcquired)

        let canceledWaiter = Task { @MainActor in
            await controller.acquireDevelopSlot()
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        canceledWaiter.cancel()
        let canceledResult = await canceledWaiter.value
        XCTAssertFalse(canceledResult)

        var nextSlotAcquired = false
        let nextWaiter = Task { @MainActor in
            guard await controller.acquireDevelopSlot() else { return }
            nextSlotAcquired = true
        }

        controller.releaseDevelopSlot()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(nextSlotAcquired)

        controller.releaseDevelopSlot()
        nextWaiter.cancel()
    }

    func testCanceledDevelopSlotWaiterDoesNotAcquireWhenReleaseWinsActorCleanupRace() async throws {
        let controller = DevelopController(maxConcurrentDevelopments: 1)
        let firstSlotAcquired = await controller.acquireDevelopSlot()
        XCTAssertTrue(firstSlotAcquired)

        let canceledWaiter = Task { @MainActor in
            await controller.acquireDevelopSlot()
        }
        try await Task.sleep(nanoseconds: 30_000_000)

        canceledWaiter.cancel()
        controller.releaseDevelopSlot()

        let canceledResult = await canceledWaiter.value
        XCTAssertFalse(canceledResult)

        let nextSlotAcquired = await controller.acquireDevelopSlot()
        XCTAssertTrue(nextSlotAcquired)
        controller.releaseDevelopSlot()
    }

    func testActiveFrameTrackingCoalescesDuplicateFrame() {
        let controller = DevelopController()
        let frame = Self.makeFrame(index: 1)

        XCTAssertTrue(controller.beginFrame(frame))
        XCTAssertFalse(controller.beginFrame(frame))

        controller.endFrame(frame)
        XCTAssertTrue(controller.beginFrame(frame))
    }

    func testProcessingStateClearsAfterLastFrameEnds() {
        let controller = DevelopController()

        controller.developBegan()
        controller.updateProcessingDetail(interactive: true, proxyPixels: 2816, isScanning: false, language: .korean)

        XCTAssertTrue(controller.processingActive)
        XCTAssertEqual(controller.processingDetail, "프리뷰 생성 중 (2816px)")

        controller.developEnded()

        XCTAssertFalse(controller.processingActive)
        XCTAssertEqual(controller.processingDetail, "")
    }

    func testConcurrentProcessingDetailUsesFrameCount() {
        let controller = DevelopController()

        controller.developBegan()
        controller.developBegan()
        controller.updateProcessingDetail(interactive: false, proxyPixels: 3600, isScanning: false, language: .korean)

        XCTAssertTrue(controller.processingActive)
        XCTAssertEqual(controller.processingDetail, "현상 중 2장")

        controller.developEnded()
        controller.developEnded()
    }

    func testCancelPendingDevelopRequestCancelsRunningSelectionWork() async throws {
        let controller = DevelopController()
        let frame = Self.makeFrame(index: 1)
        var started = false
        var completed = false
        var observedCancellation = false

        controller.requestDevelop(frame) { _ in
            started = true
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                completed = true
            } catch {
                observedCancellation = true
            }
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(started)

        controller.cancelPendingDevelopRequest()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertTrue(observedCancellation)
        XCTAssertFalse(completed)
    }

    func testNewDevelopRequestDoesNotCancelInFlightRender() async throws {
        let controller = DevelopController()
        let frame = Self.makeFrame(index: 1)
        var firstStarted = false
        var firstWasCancelled = false
        var secondCompleted = false

        controller.requestDevelop(frame) { _ in
            firstStarted = true
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                firstWasCancelled = true
            }
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(firstStarted)

        try await Task.sleep(nanoseconds: 50_000_000)
        controller.requestDevelop(frame) { _ in
            secondCompleted = true
        }
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertTrue(secondCompleted)
        XCTAssertFalse(
            firstWasCancelled,
            "새 슬라이더 값은 진행 중 렌더를 취소하지 않고 최신 revision으로 합쳐져야 합니다."
        )
        controller.cancelPendingDevelopRequest()
    }

    private static func makeFrame(index: Int) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-develop-controller-test-\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
    }
}
