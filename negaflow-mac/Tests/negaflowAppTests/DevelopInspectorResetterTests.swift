import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class DevelopInspectorResetterTests: XCTestCase {
    func testToneResetRestoresToneOnlyAndDoesNotRequestBatchWBSync() {
        let frame = Self.makeFrame()
        frame.updateParams {
            $0.exposure = 1.2
            $0.contrast = 0.8
            $0.warmth = 0.4
            $0.baseEstimationMode = .manual
            $0.manualBaseRGB = SIMD3(0.2, 0.3, 0.4)
        }

        let shouldSync = DevelopInspectorResetter.reset(.tone, frame: frame, neutralPreset: nil)

        XCTAssertFalse(shouldSync)
        XCTAssertEqual(frame.params.exposure, DevelopParameters().exposure)
        XCTAssertEqual(frame.params.contrast, DevelopParameters().contrast)
        XCTAssertEqual(frame.params.warmth, 0.4)
        XCTAssertEqual(frame.params.baseEstimationMode, .manual)
        XCTAssertEqual(frame.params.manualBaseRGB, SIMD3(0.2, 0.3, 0.4))
    }

    func testColorResetRequestsBatchWBSyncAndKeepsToneValues() {
        let frame = Self.makeFrame()
        frame.updateParams {
            $0.exposure = 0.7
            $0.warmth = -0.5
            $0.tint = 0.3
            $0.vibrance = 0.6
        }

        let shouldSync = DevelopInspectorResetter.reset(.color, frame: frame, neutralPreset: nil)

        XCTAssertTrue(shouldSync)
        XCTAssertEqual(frame.params.exposure, 0.7)
        XCTAssertEqual(frame.params.warmth, DevelopParameters().warmth)
        XCTAssertEqual(frame.params.tint, DevelopParameters().tint)
        XCTAssertEqual(frame.params.vibrance, DevelopParameters().vibrance)
    }

    func testResetAllAdjustmentsPreservesBaseAndGeometry() {
        let frame = Self.makeFrame()
        let crop = SIMD4<Double>(0.1, 0.2, 0.7, 0.6)
        frame.updateTransform { $0.cropRect = crop }
        frame.updateParams {
            $0.exposure = 1.0
            $0.warmth = 0.8
            $0.noiseReduction = 0.9
            $0.baseEstimationMode = .manual
            $0.manualBaseRGB = SIMD3(0.3, 0.4, 0.5)
            $0.filmStockDminID = "kodak-gold-200"
        }

        DevelopInspectorResetter.resetAllAdjustments(frame: frame, neutralPreset: nil)

        XCTAssertEqual(frame.params.exposure, DevelopParameters().exposure)
        XCTAssertEqual(frame.params.warmth, DevelopParameters().warmth)
        XCTAssertEqual(frame.params.noiseReduction, DevelopParameters().noiseReduction)
        XCTAssertEqual(frame.params.baseEstimationMode, .manual)
        XCTAssertEqual(frame.params.manualBaseRGB, SIMD3(0.3, 0.4, 0.5))
        XCTAssertEqual(frame.params.filmStockDminID, "kodak-gold-200")
        XCTAssertEqual(frame.imageTransform.cropRect, crop)
    }

    private static func makeFrame() -> ScanFrame {
        ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-resetter-test-\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
    }
}
