import Chromabase
import XCTest
@testable import negaflowApp

/// "모든 보정 초기화"는 슬라이더 수십 개를 한 번에 날린다. ⌘Z 가 듣지 않으면 사용자는
/// 초기화 전 값을 하나씩 기억해 되돌려야 한다 — 되돌리기/다시 실행이 모두 성립해야 한다.
@MainActor
final class DevelopResetUndoTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-reset-undo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try await super.tearDown()
    }

    func testResetAllAdjustmentsIsUndoableAndRedoable() {
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let frame = makeFrame()
        model.frames = [frame]
        frame.updateParams {
            $0.exposure = 1.25
            $0.contrast = -0.4
            $0.saturation = 0.6
        }
        let defaults = DevelopParameters()

        model.resetAllDevelopAdjustments(frame, neutralPreset: nil)
        XCTAssertEqual(frame.params.exposure, defaults.exposure)
        XCTAssertEqual(frame.params.contrast, defaults.contrast)
        XCTAssertEqual(frame.params.saturation, defaults.saturation)
        XCTAssertTrue(undoManager.canUndo, "초기화는 되돌릴 수 있어야 한다.")

        undoManager.undo()
        XCTAssertEqual(frame.params.exposure, 1.25)
        XCTAssertEqual(frame.params.contrast, -0.4)
        XCTAssertEqual(frame.params.saturation, 0.6)

        XCTAssertTrue(undoManager.canRedo, "되돌린 초기화는 다시 실행할 수 있어야 한다.")
        undoManager.redo()
        XCTAssertEqual(frame.params.exposure, defaults.exposure)
        XCTAssertEqual(frame.params.contrast, defaults.contrast)
    }

    /// 초기화는 룩 프리셋도 되돌린다 — 인스펙터 경로는 Neutral 로 되돌리기 때문이다.
    func testResetRestoresLookPresetOnUndo() {
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let frame = makeFrame()
        model.frames = [frame]
        let preset = model.presets.first(where: { $0.id != "neutral" })
        frame.preset = preset

        model.resetAllDevelopAdjustments(frame, neutralPreset: nil)
        XCTAssertNil(frame.preset)

        undoManager.undo()
        XCTAssertEqual(frame.preset?.id, preset?.id)
    }

    private func makeFrame() -> ScanFrame {
        let rawURL = tempDir.appendingPathComponent("scan-\(UUID().uuidString).tiff")
        FileManager.default.createFile(atPath: rawURL.path, contents: Data([0x49, 0x49]))
        return ScanFrame(
            scanIndex: 1,
            rawScanURL: rawURL,
            filmType: .colorNegative,
            sourceKind: .scannerTIFF
        )
    }
}
