import AppKit
import XCTest
@testable import negaflowApp

@MainActor
final class ApplicationLifecycleTests: XCTestCase {
    func testLastWindowCloseRequestsFullApplicationTermination() {
        let delegate = NegaflowApplicationDelegate(model: AppModel())

        XCTAssertTrue(
            delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
        )
    }

    func testQuitIsCancelledWhenTerminationSnapshotCannotBePrepared() {
        let (model, delegate) = makeDelegateWhoseTerminationSaveFails()
        var asked = 0
        delegate.confirmQuitWithoutSaving = { _ in
            asked += 1
            return false
        }

        XCTAssertEqual(
            delegate.applicationShouldTerminate(NSApplication.shared),
            .terminateCancel
        )
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(model.frames.count, 1)
    }

    /// 저장이 실패해도 사용자가 고르면 앱을 끌 수 있어야 한다 — 막기만 하면 강제 종료뿐이다.
    func testQuitProceedsWithoutSavingWhenUserConfirms() {
        let (model, delegate) = makeDelegateWhoseTerminationSaveFails()
        model.isRelaunchRequested = true
        delegate.confirmQuitWithoutSaving = { _ in true }

        XCTAssertEqual(
            delegate.applicationShouldTerminate(NSApplication.shared),
            .terminateNow
        )
        XCTAssertFalse(model.isRelaunchRequested)
    }

    private func makeDelegateWhoseTerminationSaveFails() -> (AppModel, NegaflowApplicationDelegate) {
        let model = AppModel()
        model.frames = [ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-quit-regression.tiff"),
            filmType: .colorNegative
        )]
        model.libraryPersistenceEnabled = true
        addTeardownBlock { @MainActor in model.libraryPersistenceEnabled = false }
        return (model, NegaflowApplicationDelegate(model: model))
    }
}
