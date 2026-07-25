import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class DevelopInspectorBindingsTests: XCTestCase {
    func testGrainMendDefaultsUseMaximumSensitivityAndMicroSpecksInBothModes() {
        let frame = Self.makeFrame()

        for automaticMode in [true, false] {
            frame.defectAutoMode = automaticMode

            XCTAssertEqual(frame.defectSensitivity, 6.0)
            XCTAssertTrue(frame.defectMicroSpecks)
        }
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
