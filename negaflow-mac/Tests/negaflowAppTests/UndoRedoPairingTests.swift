import Chromabase
import CoreGraphics
import ScannerKit
import XCTest
@testable import negaflowApp

/// ⌘Z 와 ⇧⌘Z 는 앱 전체에서 하나의 히스토리를 왕복한다.
///
/// 예전에는 캔버스가 ⌘Z 를 가로채 무조건 현재 사진의 GrainMend 를 되돌렸다. 사진을 백스페이스로
/// 지운 뒤 ⌘Z 를 누르면 지운 사진이 돌아오는 대신 **다음 사진의 GrainMend 기록**이 사라졌다.
@MainActor
final class UndoRedoPairingTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-undo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try await super.tearDown()
    }

    // MARK: 라이브러리 제거와 결함 편집이 한 스택을 공유한다

    /// 사진을 지운 직후의 ⌘Z 는 그 사진을 되살린다. 다른 사진의 GrainMend 기록은 손대지 않는다.
    func testUndoAfterRemovalRestoresThePhotoAndLeavesOtherLayersAlone() throws {
        let model = makeModel()
        let removed = makeFrame(named: "removed")
        let neighbour = makeFrame(named: "neighbour")
        neighbour.defectEdits = [infraredEdit(), brushEdit()]
        model.frames = [removed, neighbour]
        model.selectedFrameID = removed.id

        model.removeFramesFromLibrary([removed])
        XCTAssertEqual(model.frames.count, 1)

        model.performUndo()

        XCTAssertEqual(model.frames.count, 2, "지운 사진이 돌아와야 한다.")
        XCTAssertTrue(model.frames.contains { $0 === removed })
        XCTAssertEqual(neighbour.defectEdits.count, 2, "다른 사진의 레이어는 그대로여야 한다.")
        XCTAssertTrue(neighbour.defectEdits.contains(where: \.isInfrared))
    }

    /// ⇧⌘Z 는 방금 되돌린 것을 다시 실행한다.
    func testRedoReappliesTheRemoval() throws {
        let model = makeModel()
        let frame = makeFrame(named: "redo")
        model.frames = [frame]
        model.selectedFrameID = frame.id

        model.removeFramesFromLibrary([frame])
        model.performUndo()
        XCTAssertEqual(model.frames.count, 1)

        model.performRedo()

        XCTAssertTrue(model.frames.isEmpty, "다시 실행하면 제거가 되살아난다.")
    }

    /// 되돌리기는 가장 최근에 한 일부터 되짚는다 — 결함 편집과 라이브러리 편집이 섞여도 순서가 유지된다.
    func testUndoWalksBackTheMostRecentActionFirst() throws {
        let model = makeModel()
        let edited = makeFrame(named: "edited")
        let removed = makeFrame(named: "removed")
        model.frames = [edited, removed]
        model.selectedFrameID = edited.id

        // 1) 결함 편집 → 2) 사진 제거 순서로 히스토리를 쌓는다.
        model.recordDefectHistory(edited, before: [])
        edited.defectEdits = [brushEdit()]
        flushUndoGroup()
        model.removeFramesFromLibrary([removed])
        flushUndoGroup()

        model.performUndo()
        XCTAssertEqual(model.frames.count, 2, "가장 최근 조작(제거)이 먼저 되돌아간다.")
        XCTAssertEqual(edited.defectEdits.count, 1, "그 전 편집은 아직 그대로다.")

        model.performUndo()
        XCTAssertTrue(edited.defectEdits.isEmpty, "다음 ⌘Z 가 그 앞의 편집을 되돌린다.")
    }

    // MARK: GrainMend IR 은 되돌리기로 사라지지 않는다

    /// 스냅샷 이후에 붙은 IR 레이어는 되돌리기가 지우지 않는다.
    func testUndoKeepsAnInfraredLayerAddedAfterTheSnapshot() throws {
        let model = makeModel()
        let frame = makeFrame(named: "ir-keep")
        model.frames = [frame]
        let brush = brushEdit()
        let infrared = infraredEdit()
        // 브러시만 있던 시점의 스냅샷 → 그 뒤에 IR 이 붙고, 또 브러시가 하나 더 붙었다.
        let snapshot = [brush]
        frame.defectEdits = [brush, infrared, brushEdit()]

        model.applyDefectHistorySnapshot(snapshot, to: frame, mode: .preservingInfrared)

        XCTAssertEqual(frame.defectEdits.filter(\.isInfrared).count, 1, "IR 은 남아야 한다.")
        XCTAssertEqual(frame.defectEdits.count, 2, "브러시만 스냅샷 상태로 돌아간다.")
        XCTAssertTrue(frame.defectEdits.contains { $0.id == infrared.id })
    }

    /// 레이어 휴지통으로 지운 IR 은 되돌리면 정확히 돌아온다 — 유일하게 IR 이 사라지는 경로다.
    func testDeletingTheInfraredLayerFromTheListIsUndoable() throws {
        let model = makeModel()
        let frame = makeFrame(named: "ir-trash")
        model.frames = [frame]
        let infrared = infraredEdit()
        frame.defectEdits = [infrared, brushEdit()]

        model.removeDefectEdit(frame, id: infrared.id)
        XCTAssertFalse(frame.defectEdits.contains(where: \.isInfrared), "휴지통은 IR 도 지운다.")

        model.performUndo()

        XCTAssertEqual(frame.defectEdits.filter(\.isInfrared).count, 1, "되돌리면 IR 이 돌아온다.")
        frame.cleanRawTask?.cancel()
    }

    /// 순수 규칙: 되돌릴 목록을 만들 때 현재 IR 은 지켜지고, 정확 복원 모드는 스냅샷 그대로다.
    func testSnapshotResolutionRules() {
        let brush = brushEdit()
        let infrared = infraredEdit()

        let preserved = DefectHistorySnapshot.resolve(
            [brush],
            current: [brush, infrared],
            mode: .preservingInfrared
        )
        XCTAssertEqual(preserved.map(\.id), [brush.id, infrared.id])

        let exact = DefectHistorySnapshot.resolve(
            [brush],
            current: [brush, infrared],
            mode: .exact
        )
        XCTAssertEqual(exact.map(\.id), [brush.id])
    }

    // MARK: 현상 조정 — 슬라이더·자동보정·회전까지 같은 스택

    /// 인스펙터 조정은 재현상 요청 길목에서 기록된다. ⌘Z 로 값이 돌아오고 ⇧⌘Z 로 다시 적용된다.
    func testDevelopAdjustmentIsUndoableAndRedoable() throws {
        let model = makeModel()
        let frame = makeFrame(named: "adjust")
        model.frames = [frame]
        model.noteFrameEditBaseline(frame)

        frame.updateParams { $0.exposure = 1.25 }
        model.requestDevelop(frame)
        XCTAssertEqual(frame.params.exposure, 1.25)

        model.performUndo()
        XCTAssertEqual(frame.params.exposure, 0, "⌘Z 는 조정 전 값으로 돌아간다.")

        model.performRedo()
        XCTAssertEqual(frame.params.exposure, 1.25, "⇧⌘Z 는 그 조정을 다시 적용한다.")
        frame.transformTask?.cancel()
    }

    /// 회전·뒤집기·크롭도 같은 히스토리에 들어간다.
    func testTransformChangeIsUndoable() throws {
        let model = makeModel()
        let frame = makeFrame(named: "rotate")
        model.frames = [frame]
        model.noteFrameEditBaseline(frame)
        let original = frame.imageTransform

        frame.updateTransform { $0.flipHorizontal.toggle() }
        model.applyTransformFast(frame)
        XCTAssertNotEqual(frame.imageTransform, original)

        model.performUndo()
        XCTAssertEqual(frame.imageTransform, original, "⌘Z 는 뒤집기를 되돌린다.")
        frame.transformTask?.cancel()
    }

    /// 슬라이더를 끄는 동안의 연속 변화는 한 칸이다 — ⌘Z 한 번에 드래그 시작 직전으로.
    func testASliderDragCollapsesIntoOneHistoryStep() throws {
        let model = makeModel()
        let frame = makeFrame(named: "drag")
        model.frames = [frame]
        model.noteFrameEditBaseline(frame)

        for tick in 1...8 {
            frame.updateParams { $0.contrast = Double(tick) / 10 }
            model.requestDevelop(frame)
        }
        XCTAssertEqual(frame.params.contrast, 0.8, accuracy: 1e-9)

        model.performUndo()
        XCTAssertEqual(frame.params.contrast, 0, accuracy: 1e-9,
                       "드래그 한 번은 ⌘Z 한 번으로 시작 직전 값이 된다.")
        frame.transformTask?.cancel()
    }

    // MARK: 픽스처

    private func makeModel() -> AppModel {
        let model = AppModel(
            libraryCatalogURL: tempDir.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: tempDir.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: tempDir.appendingPathComponent("backups", isDirectory: true)
        )
        return model
    }

    /// UndoManager 는 한 이벤트에 등록된 것들을 한 묶음으로 되돌린다. 테스트는 사용자의 조작
    /// 사이사이를 대신해 그 묶음을 닫아 준다.
    private func flushUndoGroup() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    private func makeFrame(named name: String) -> ScanFrame {
        let rawURL = tempDir.appendingPathComponent("\(name).tiff")
        FileManager.default.createFile(atPath: rawURL.path, contents: Data([0x49, 0x49]))
        return ScanFrame(
            scanIndex: 1,
            rawScanURL: rawURL,
            filmType: .colorNegative,
            sourceKind: .scannerTIFF
        )
    }

    private func infraredEdit() -> DefectEditItem {
        let cluster = InfraredDefectRemoval.Cluster(
            roiYup: CGRect(x: 0, y: 0, width: 4, height: 4),
            maskRGBA8: Data(repeating: 0, count: 4 * 4 * 4),
            attenuationR16: Data(repeating: 0, count: 4 * 4 * 2),
            width: 4,
            height: 4
        )
        return DefectEditItem(
            edit: .infrared(clusters: [cluster]),
            label: .infrared(count: 1),
            summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
            preview: [],
            baseSize: CGSize(width: 16, height: 16)
        )
    }

    private func brushEdit() -> DefectEditItem {
        DefectEditItem(
            edit: .brush([DefectStroke(points: [CGPoint(x: 0.2, y: 0.3)], thickness: 0.04)]),
            label: .brush(strokeCount: 1),
            summaryKind: .brush,
            preview: [],
            baseSize: nil
        )
    }
}
