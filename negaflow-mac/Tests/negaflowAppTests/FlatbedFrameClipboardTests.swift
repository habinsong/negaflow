import CoreGraphics
import XCTest
@testable import Chromabase
@testable import ScannerKit
@testable import negaflowApp

/// 평판 프레임의 복사·붙여넣기와 방향키 미세 이동.
///
/// 시뮬레이터의 평판 장치(210×297mm, positioned scan area)로 프리뷰까지 실제로 돌린 뒤 검사한다.
/// 좌표가 프리뷰로 훑은 영역 기준이라, 비율만 보는 검사로는 mm 단위 동작을 확인할 수 없다.
@MainActor
final class FlatbedFrameClipboardTests: XCTestCase {
    private var root: URL!
    private var defaultsName: String!

    override func tearDown() async throws {
        tearDownFixture()
        try await super.tearDown()
    }

    private func tearDownFixture() {
        if let defaultsName {
            UserDefaults.standard.removePersistentDomain(forName: defaultsName)
        }
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
        defaultsName = nil
    }

    func testPasteAddsAFrameOfTheCopiedSizeInTheNextSlot() async throws {
        let model = try await makeFlatbedPreviewModel()
        let previewArea = try XCTUnwrap(model.flatbedPreviewScanArea)
        let original = try XCTUnwrap(model.flatbedScanRegions.first)
        model.selectFlatbedScanRegion(original.id)

        // 손으로 키워 둔 크기를 그대로 복제하는 것이 이 기능의 목적이다.
        let widened = CGRect(
            x: original.unitRect.minX,
            y: original.unitRect.minY,
            width: original.unitRect.width * 1.4,
            height: original.unitRect.height * 1.4
        )
        model.updateFlatbedScanRegion(original.id, unitRect: widened)
        let copied = try XCTUnwrap(model.selectedFlatbedScanRegion).unitRect
        let countBeforePaste = model.flatbedScanRegions.count

        model.copySelectedFlatbedScanRegion()
        XCTAssertEqual(model.copiedFlatbedScanRegionSize, copied.size)
        XCTAssertTrue(model.canPasteFlatbedScanRegion)

        model.pasteFlatbedScanRegion()

        XCTAssertEqual(model.flatbedScanRegions.count, countBeforePaste + 1)
        let pasted = try XCTUnwrap(model.flatbedScanRegions.last)
        XCTAssertEqual(model.selectedFlatbedScanRegionID, pasted.id)
        XCTAssertEqual(
            Double(pasted.unitRect.width) * previewArea.widthMM,
            Double(copied.width) * previewArea.widthMM,
            accuracy: 0.001
        )
        XCTAssertEqual(
            Double(pasted.unitRect.height) * previewArea.heightMM,
            Double(copied.height) * previewArea.heightMM,
            accuracy: 0.001
        )
        // 붙여넣은 프레임은 마지막 프레임 위에 겹치지 않는다.
        let previous = model.flatbedScanRegions[model.flatbedScanRegions.count - 2].unitRect
        XCTAssertFalse(pasted.unitRect.intersects(previous.insetBy(dx: 0.001, dy: 0.001)))
    }

    func testCopyingNothingLeavesPasteUnavailable() async throws {
        let model = try await makeFlatbedPreviewModel()
        model.selectedFlatbedScanRegionID = nil

        model.copySelectedFlatbedScanRegion()

        XCTAssertNil(model.copiedFlatbedScanRegionSize)
        XCTAssertFalse(model.canPasteFlatbedScanRegion)
        let before = model.flatbedScanRegions
        model.pasteFlatbedScanRegion()
        XCTAssertEqual(model.flatbedScanRegions, before)
    }

    func testArrowNudgeMovesHalfAMillimetreAndKeepsTheSize() async throws {
        let model = try await makeFlatbedPreviewModel()
        let previewArea = try XCTUnwrap(model.flatbedPreviewScanArea)
        // 이동 거리만 재는 검사다. 회전은 방향 검사(아래)가 따로 맡는다.
        try XCTUnwrap(model.flatbedPreviewFrame).updateTransform { $0 = .identity }
        let region = try XCTUnwrap(model.flatbedScanRegions.first)
        model.selectFlatbedScanRegion(region.id)
        let before = region.unitRect

        model.nudgeSelectedFlatbedScanRegion(dx: 1, dy: 0)

        let moved = try XCTUnwrap(model.selectedFlatbedScanRegion).unitRect
        XCTAssertEqual(
            Double(moved.minX - before.minX) * previewArea.widthMM,
            FlatbedScanRegionLayout.nudgeStepMM,
            accuracy: 0.001
        )
        XCTAssertEqual(moved.minY, before.minY, accuracy: 0.000_001)
        XCTAssertEqual(moved.width, before.width, accuracy: 0.000_001)
        XCTAssertEqual(moved.height, before.height, accuracy: 0.000_001)
    }

    func testShiftNudgeMovesOneFrameGap() async throws {
        let model = try await makeFlatbedPreviewModel()
        let previewArea = try XCTUnwrap(model.flatbedPreviewScanArea)
        try XCTUnwrap(model.flatbedPreviewFrame).updateTransform { $0 = .identity }
        let region = try XCTUnwrap(model.flatbedScanRegions.first)
        model.selectFlatbedScanRegion(region.id)
        let before = region.unitRect

        model.nudgeSelectedFlatbedScanRegion(dx: 0, dy: 1, coarse: true)

        let moved = try XCTUnwrap(model.selectedFlatbedScanRegion).unitRect
        XCTAssertEqual(
            Double(moved.minY - before.minY) * previewArea.heightMM,
            FlatbedScanRegionLayout.frameGapMM,
            accuracy: 0.001
        )
        XCTAssertEqual(moved.minX, before.minX, accuracy: 0.000_001)
    }

    /// 프레임 좌표는 이미지 변환 이전(base)이라, 프리뷰가 돌아 있으면 base 축과 화면 축이
    /// 어긋난다. 방향키는 화면에서 누른 방향 그대로 움직여야 한다.
    func testArrowKeysFollowTheScreenWhenThePreviewIsRotated() async throws {
        for rotation in [ImageRotation.deg180, .deg90, .deg270] {
            let model = try await makeFlatbedPreviewModel()
            let preview = try XCTUnwrap(model.flatbedPreviewFrame)
            preview.updateTransform { $0.rotation = rotation }
            let region = try XCTUnwrap(model.flatbedScanRegions.first)
            model.selectFlatbedScanRegion(region.id)
            let before = displayCenter(of: region.unitRect, in: preview)

            model.nudgeSelectedFlatbedScanRegion(dx: 1, dy: 0)
            let afterRight = displayCenter(
                of: try XCTUnwrap(model.selectedFlatbedScanRegion).unitRect,
                in: preview
            )
            XCTAssertGreaterThan(afterRight.x, before.x, "\(rotation): → 는 화면 오른쪽")
            XCTAssertEqual(afterRight.y, before.y, accuracy: 0.000_01, "\(rotation): → 는 세로 고정")

            model.nudgeSelectedFlatbedScanRegion(dx: 0, dy: 1)
            let afterDown = displayCenter(
                of: try XCTUnwrap(model.selectedFlatbedScanRegion).unitRect,
                in: preview
            )
            XCTAssertGreaterThan(afterDown.y, afterRight.y, "\(rotation): ↓ 는 화면 아래쪽")
            XCTAssertEqual(
                afterDown.x,
                afterRight.x,
                accuracy: 0.000_01,
                "\(rotation): ↓ 는 가로 고정"
            )
            tearDownFixture()
        }
    }

    private func displayCenter(of rect: CGRect, in frame: ScanFrame) -> CGPoint {
        let baseSize = frame.sourcePixelWidth.flatMap { width in
            frame.sourcePixelHeight.map { CGSize(width: width, height: $0) }
        }
        return frame.imageTransform.baseUnitToDisplay(
            CGPoint(x: rect.midX, y: rect.midY),
            baseSize: baseSize
        )
    }

    /// 유리면 밖으로는 나가지 않는다. 밀다 멈춰도 크기는 줄지 않아야 한다.
    func testNudgeStopsAtTheEdgeWithoutShrinkingTheFrame() async throws {
        let model = try await makeFlatbedPreviewModel()
        try XCTUnwrap(model.flatbedPreviewFrame).updateTransform { $0 = .identity }
        let region = try XCTUnwrap(model.flatbedScanRegions.first)
        model.selectFlatbedScanRegion(region.id)
        let size = region.unitRect.size

        for _ in 0..<2_000 {
            model.nudgeSelectedFlatbedScanRegion(dx: -1, dy: -1)
        }

        let moved = try XCTUnwrap(model.selectedFlatbedScanRegion).unitRect
        XCTAssertEqual(moved.minX, 0, accuracy: 0.000_001)
        XCTAssertEqual(moved.minY, 0, accuracy: 0.000_001)
        XCTAssertEqual(moved.width, size.width, accuracy: 0.000_001)
        XCTAssertEqual(moved.height, size.height, accuracy: 0.000_001)
    }

    /// 기본값은 자동이다. 수동으로 바꾸면 프리뷰가 끝나도 앱이 프레임을 놓지 않는다.
    func testManualModeLeavesFrameFindingToTheUser() async throws {
        let model = try await makeFlatbedPreviewModel()
        XCTAssertEqual(model.flatbedFrameDetectionMode, .automatic)

        await model.setFlatbedFrameDetectionMode(.manual)
        // 방식만 바꿨을 뿐이므로 이미 놓인 프레임은 그대로 둔다.
        XCTAssertFalse(model.flatbedScanRegions.isEmpty)

        model.resetFlatbedPreviewState()
        await model.runScan(preview: true)

        XCTAssertTrue(model.flatbedScanRegions.isEmpty)
        XCTAssertNotNil(model.flatbedPreviewFrame)
    }

    func testRefreshFindsAgainWhenAutomaticAndStartsOverWhenManual() async throws {
        let model = try await makeFlatbedPreviewModel()
        let detected = model.flatbedScanRegions.count
        XCTAssertGreaterThan(detected, 1)
        XCTAssertTrue(model.canRefreshFlatbedScanRegions)

        model.deleteSelectedFlatbedScanRegion()
        XCTAssertEqual(model.flatbedScanRegions.count, detected - 1)
        await model.refreshFlatbedScanRegions()
        XCTAssertEqual(model.flatbedScanRegions.count, detected)

        await model.setFlatbedFrameDetectionMode(.manual)
        await model.refreshFlatbedScanRegions()
        // 수동은 빈 화면 대신 다시 시작할 프레임 하나를 남긴다.
        XCTAssertEqual(model.flatbedScanRegions.count, 1)
        XCTAssertEqual(model.flatbedScanRegions.first?.source, .manual)
        XCTAssertEqual(model.selectedFlatbedScanRegionID, model.flatbedScanRegions.first?.id)
    }

    /// 시뮬레이터의 평판 장치로 프리뷰를 돌려 프레임이 잡힌 상태를 만든다.
    private func makeFlatbedPreviewModel() async throws -> AppModel {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-flatbed-clipboard-\(UUID().uuidString)",
            isDirectory: true
        )
        defaultsName = "negaflow.flatbed-clipboard.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let diskStorage = DiskStorageStore(defaults: defaults)
        diskStorage.locationMode = .custom
        diskStorage.rootPath = root.appendingPathComponent("storage", isDirectory: true).path
        diskStorage.scansPath = root.appendingPathComponent("storage/Scans", isDirectory: true).path
        diskStorage.scanPreviewsPath = root
            .appendingPathComponent("storage/Scan Previews", isDirectory: true).path
        let support = root.appendingPathComponent("support", isDirectory: true)
        let model = AppModel(
            diskStorageStore: diskStorage,
            scannerDemoBackend: MockScannerBackend(),
            libraryCatalogURL: support.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: support.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: support.appendingPathComponent("Backups", isDirectory: true)
        )
        model.libraryPersistenceEnabled = false
        model.demoMode = true
        model.selectedDeviceID = MockScannerBackend.flatbedScannerID
        await model.loadCapabilities()
        XCTAssertTrue(model.usesFlatbedRegionWorkflow)
        await model.runScan(preview: true)
        XCTAssertFalse(model.flatbedScanRegions.isEmpty)
        return model
    }
}
