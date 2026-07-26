import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class DevelopInspectorBindingsTests: XCTestCase {
    func testGrainMendDefaultsUseMaximumSensitivityAndMicroSpecksInBothModes() {
        let frame = Self.makeFrame()

        XCTAssertEqual(frame.defectAutoSensitivity, GrainMendSensitivity.automaticRange.upperBound)
        XCTAssertEqual(frame.defectGuidedSensitivity, GrainMendSensitivity.guidedRange.upperBound)
        XCTAssertTrue(frame.defectMicroSpecks)
    }

    /// 검출기 민감도 상한은 두 모드 모두 1 이다.
    ///
    /// 가이드만 1.5 까지 올려 형태 게이트(면적/aspect/길이/두께)를 더 풀었더니, 그레인이 굵은
    /// 흑백 네거티브에서 텍스처가 통째로 한 덩어리 결함이 되어 ROI 를 뭉갰다(2026-07-26 실측).
    /// 그래서 1 로 되돌렸다 — 두 모드는 값을 따로 저장할 뿐 상한 계약은 같다.
    func testGuidedSensitivityCeilingMatchesAutomatic() {
        XCTAssertEqual(GrainMendSensitivity.automaticRange, 0.7...6.0)
        XCTAssertEqual(GrainMendSensitivity.guidedRange, 0.7...6.0)
        XCTAssertEqual(GrainMendSensitivity.guidedMaximumDetectorSensitivity, 1.0, accuracy: 1e-9)
        XCTAssertEqual(GrainMendSensitivity.detectorSensitivity(6.0, automatic: true), 1.0, accuracy: 1e-9)
        XCTAssertEqual(GrainMendSensitivity.detectorSensitivity(6.0, automatic: false), 1.0, accuracy: 1e-9)
        // 범위를 벗어난 저장값(1.5 시절의 9.0 포함)도 모드 상한을 넘지 않는다.
        XCTAssertEqual(GrainMendSensitivity.detectorSensitivity(99, automatic: true), 1.0, accuracy: 1e-9)
        XCTAssertEqual(GrainMendSensitivity.detectorSensitivity(9.0, automatic: false), 1.0, accuracy: 1e-9)
        XCTAssertEqual(GrainMendSensitivity.detectorSensitivity(0, automatic: false), 0, accuracy: 1e-9)
    }

    func testNoiseReductionToggleUsesDefaultStrengthAndCallsChange() {
        let frame = Self.makeFrame()
        var changeCount = 0
        let binding = DevelopInspectorBindings.noiseReductionEnabled(frame: frame) { changeCount += 1 }

        binding.wrappedValue = true

        XCTAssertEqual(frame.params.noiseReduction, 0.7)
        XCTAssertEqual(changeCount, 1)

        binding.wrappedValue = false

        XCTAssertEqual(frame.params.noiseReduction, 0)
        XCTAssertEqual(changeCount, 2)
    }

    func testManualBaseBindingClampsAndSwitchesToManualMode() {
        let frame = Self.makeFrame()
        var changeCount = 0
        var syncCount = 0
        let binding = DevelopInspectorBindings.manualBase(
            frame: frame,
            channel: 1,
            onChange: { changeCount += 1 },
            onSync: { syncCount += 1 }
        )

        binding.wrappedValue = 2

        XCTAssertEqual(frame.params.manualBaseRGB?.y, 1)
        XCTAssertEqual(frame.params.baseEstimationMode, .manual)
        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(syncCount, 1)
    }

    func testFilmStockNilReturnsBaseModeToAuto() {
        let frame = Self.makeFrame()
        frame.updateParams {
            $0.baseEstimationMode = .preset
            $0.filmStockDminID = "kodak-gold-200"
        }
        let binding = DevelopInspectorBindings.filmStockDminID(
            frame: frame,
            autoMatchScannerProfile: false,
            scannerProfiles: [],
            setModelScannerProfileID: { _ in },
            onChange: {},
            onSync: {}
        )

        binding.wrappedValue = nil

        XCTAssertNil(frame.params.filmStockDminID)
        XCTAssertEqual(frame.params.baseEstimationMode, .auto)
    }

    func testImportedFrameProcessCanChangeWithoutChangingScanFilmType() {
        let model = AppModel()
        model.scanFilmType = .colorPositive
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(
                fileURLWithPath: "/tmp/negaflow-imported-process-\(UUID().uuidString).tiff"
            ),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )

        model.applyDevelopmentProcess(.bwNegative, to: frame)

        XCTAssertEqual(frame.filmType, .bwNegative)
        XCTAssertEqual(frame.params.filmType, .bwNegative)
        XCTAssertEqual(model.filmType, .bwNegative)
        XCTAssertEqual(model.scanFilmType, .colorPositive)
    }

    private static func makeFrame() -> ScanFrame {
        ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-bindings-test-\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
    }
}
