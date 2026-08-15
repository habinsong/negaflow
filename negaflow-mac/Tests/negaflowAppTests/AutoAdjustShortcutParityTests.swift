import CoreGraphics
import XCTest
@testable import Chromabase
@testable import ScannerKit
@testable import negaflowApp

/// 자동 톤 / 자동 화이트 밸런스는 인스펙터 버튼과 단축키(⌘U / ⇧⌘U)가 같은 결과를 내야 한다.
///
/// 버튼은 되는데 단축키는 "프리뷰 생성하는 척만 하고 값이 안 바뀌는" 증상을 고정한다.
@MainActor
final class AutoAdjustShortcutParityTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-auto-parity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        try await super.tearDown()
    }

    func testShortcutAndButtonProduceTheSameAutoTone() async throws {
        let viaButton = try await makeModelWithFrame()
        let buttonFrame = try XCTUnwrap(viaButton.model.actionableFrame)
        viaButton.model.autoTone(buttonFrame)
        try await settle(viaButton.model)
        let buttonParams = buttonFrame.params

        let viaShortcut = try await makeModelWithFrame()
        let shortcutFrame = try XCTUnwrap(viaShortcut.model.actionableFrame)
        XCTAssertTrue(
            viaShortcut.model.canPerformWorkflowShortcutAction(.autoTone),
            "선택된 프레임이 있는데 자동 톤 단축키가 비활성이다"
        )
        viaShortcut.model.performWorkflowShortcutAction(.autoTone)
        try await settle(viaShortcut.model)
        let shortcutParams = shortcutFrame.params

        XCTAssertNotEqual(buttonParams.exposure, 0, "자동 톤이 노출을 바꾸지 않았다(기준 경로 실패)")
        XCTAssertEqual(shortcutParams.exposure, buttonParams.exposure, accuracy: 1e-9)
        XCTAssertEqual(shortcutParams.contrast, buttonParams.contrast, accuracy: 1e-9)
        XCTAssertEqual(shortcutParams.whites, buttonParams.whites, accuracy: 1e-9)
        XCTAssertEqual(shortcutParams.blacks, buttonParams.blacks, accuracy: 1e-9)
    }

    func testShortcutAndButtonProduceTheSameAutoWhiteBalance() async throws {
        let viaButton = try await makeModelWithFrame()
        let buttonFrame = try XCTUnwrap(viaButton.model.actionableFrame)
        viaButton.model.autoWhiteBalance(buttonFrame)
        try await settle(viaButton.model)
        let buttonParams = buttonFrame.params

        let viaShortcut = try await makeModelWithFrame()
        let shortcutFrame = try XCTUnwrap(viaShortcut.model.actionableFrame)
        XCTAssertTrue(viaShortcut.model.canPerformWorkflowShortcutAction(.autoWhiteBalance))
        viaShortcut.model.performWorkflowShortcutAction(.autoWhiteBalance)
        try await settle(viaShortcut.model)

        XCTAssertEqual(shortcutFrame.params.warmth, buttonParams.warmth, accuracy: 1e-9)
        XCTAssertEqual(shortcutFrame.params.tint, buttonParams.tint, accuracy: 1e-9)
    }

    // MARK: 하네스

    private func makeModelWithFrame() async throws -> (model: AppModel, frame: ScanFrame) {
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("\(UUID().uuidString).json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects-\(UUID().uuidString)"),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups-\(UUID().uuidString)")
        )
        let source = root.appendingPathComponent("frame-\(UUID().uuidString).tif")
        try MockScannerBackend.writeSyntheticNegative(width: 256, height: 192, to: source)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: source,
            filmType: .colorNegative,
            sourceKind: .scannerTIFF
        )
        model.frames = [frame]
        model.includeFrameInInteractionScopeIfNeeded(frame.id)
        model.selectedFrameID = frame.id
        return (model, frame)
    }

    /// 자동 보정은 detached 렌더를 기다리는 Task 안에서 값을 대입한다 — 완료까지 폴링한다.
    private func settle(_ model: AppModel) async throws {
        for _ in 0..<400 {
            try await Task.sleep(nanoseconds: 25_000_000)
            if let frame = model.actionableFrame,
               frame.params.exposure != 0 || frame.params.warmth != 0 || frame.params.tint != 0 {
                return
            }
        }
    }
}
