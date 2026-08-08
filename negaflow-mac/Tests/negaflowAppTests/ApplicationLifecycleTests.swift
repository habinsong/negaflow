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

    func testExplicitQuitIsNotCancelledWhenTerminationSnapshotCannotBePrepared() {
        let model = AppModel()
        model.frames = [ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-quit-regression.tiff"),
            filmType: .colorNegative
        )]
        model.libraryPersistenceEnabled = true
        let delegate = NegaflowApplicationDelegate(model: model)

        XCTAssertEqual(
            delegate.applicationShouldTerminate(NSApplication.shared),
            .terminateNow
        )
    }
}
