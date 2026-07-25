import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class DevelopInspectorKeyboardControllerTests: XCTestCase {
    func testToneNudgeUsesFineStepWithoutBatchWBSync() {
        let frame = Self.makeFrame()
        frame.updateParams { $0.exposure = 0 }

        let shouldSync = DevelopInspectorKeyboardController.nudge(
            .exposure,
            frame: frame,
            direction: .increase,
            coarse: false
        )

        XCTAssertFalse(shouldSync)
        XCTAssertEqual(frame.params.exposure, 0.01)
    }

    func testWarmthNudgeRequestsBatchWBSync() {
        let frame = Self.makeFrame()
        frame.updateParams { $0.warmth = 0 }

        let shouldSync = DevelopInspectorKeyboardController.nudge(
            .warmth,
            frame: frame,
            direction: .decrease,
            coarse: true
        )

        XCTAssertTrue(shouldSync)
        XCTAssertEqual(frame.params.warmth, -0.1)
    }

    func testNoiseReductionNudgeClampsToMinimum() {
        let frame = Self.makeFrame()
        frame.updateParams { $0.noiseReduction = 0.05 }

        _ = DevelopInspectorKeyboardController.nudge(
            .noiseReduction,
            frame: frame,
            direction: .decrease,
            coarse: true
        )

        XCTAssertEqual(frame.params.noiseReduction, 0.05)
    }

    private static func makeFrame() -> ScanFrame {
        ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-keyboard-controller-test-\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
    }
}
