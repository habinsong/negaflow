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

    /// 모두 초기화는 크롭·종횡비·수평 각도도 지운다(2026-10-15 사용자 지시). 베이스와 필름 방향
    /// (90° 회전·뒤집기)은 보정이 아니라 그대로 둔다.
    func testResetAllAdjustmentsClearsCropButPreservesBaseAndOrientation() {
        let frame = Self.makeFrame()
        let crop = SIMD4<Double>(0.1, 0.2, 0.7, 0.6)
        frame.updateTransform {
            $0.cropRect = crop
            $0.cropAspect = 1.5
            $0.straightenAngle = 2.5
            $0.rotation = .deg270
            $0.flipHorizontal = true
        }
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
        XCTAssertNil(frame.imageTransform.cropRect)
        XCTAssertNil(frame.imageTransform.cropAspect)
        XCTAssertEqual(frame.imageTransform.straightenAngle, 0)
        XCTAssertEqual(frame.imageTransform.rotation, .deg270)
        XCTAssertTrue(frame.imageTransform.flipHorizontal)
    }

    private static func makeFrame() -> ScanFrame {
        ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-resetter-test-\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
    }
}
