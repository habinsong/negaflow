import Chromabase
import CoreGraphics
import XCTest
@testable import negaflowApp

/// GrainMend IR 레이어의 수명: 종료 시 굽지 않고, 다음 실행에서 IR 파일로 되살린다.
///
/// 브러시·복제도장은 사람이 그린 기록이라 굽지 않으면 사라지지만, IR 은 원본 옆의 IR 스캔에서
/// 언제든 똑같이 다시 만들 수 있다. 구워 버리면 다음 실행에서 레이어가 없어져 켜기/끄기와
/// 강도 조절이 불가능해지고, 원본도 되돌릴 수 없게 된다.
@MainActor
final class InfraredLayerLifecycleTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-ir-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try await super.tearDown()
    }

    func testInfraredLayerIsNotBakedButBrushIs() {
        let frame = makeFrame()
        frame.defectEdits = [infraredEdit(), brushEdit()]

        let bakeable = frame.bakeableDefectEdits
        XCTAssertEqual(bakeable.count, 1, "구울 대상은 브러시뿐이어야 한다.")
        XCTAssertFalse(bakeable.contains { $0.isInfrared })
    }

    func testFrameWithOnlyInfraredHasNothingToBake() {
        let frame = makeFrame()
        frame.defectEdits = [infraredEdit()]
        XCTAssertTrue(frame.bakeableDefectEdits.isEmpty,
                      "IR 만 있는 프레임은 원본을 건드릴 이유가 없다.")
    }

    /// IR 쌍이 있는데 레이어가 없으면(= 앱을 다시 켠 직후) 되살린다. 한 세션에 한 번만이다 —
    /// 결과가 "결함 없음"이면 레이어가 안 생겨서, 표시가 없으면 선택할 때마다 다시 돈다.
    func testAutomaticRestoreRunsOncePerSessionAndSkipsFramesThatAlreadyHaveTheLayer() {
        let model = AppModel()

        let restored = makeFrame(infrared: tempDir.appendingPathComponent("scan.tiff.ir.tiff"))
        model.frames = [restored]
        model.runInfraredCleanIfNeeded(restored)
        XCTAssertTrue(restored.infraredAutoCleanAttempted, "IR 쌍이 있으면 한 번은 시도해야 한다.")
        model.cancelInfraredClean(restored)

        // 이미 레이어가 있는 프레임은 건드리지 않는다(중복 적용 방지).
        let alreadyClean = makeFrame(infrared: tempDir.appendingPathComponent("other.tiff.ir.tiff"))
        alreadyClean.defectEdits = [infraredEdit()]
        model.frames.append(alreadyClean)
        model.runInfraredCleanIfNeeded(alreadyClean)
        XCTAssertFalse(alreadyClean.infraredAutoCleanAttempted)

        // IR 쌍이 없는 프레임도 마찬가지다.
        let noInfrared = makeFrame()
        model.frames.append(noInfrared)
        model.runInfraredCleanIfNeeded(noInfrared)
        XCTAssertFalse(noInfrared.infraredAutoCleanAttempted)
    }

    /// 훑고 지나가는 프레임에서는 시작하지 않는다 — 프레임마다 수십 MB 원본을 디코드해
    /// 검출을 돌리면 화살표 몇 번에 메모리와 CPU 가 바닥난다.
    func testSelectionRestoreDoesNotStartForFramesScrolledPast() async throws {
        let model = AppModel()
        let passed = makeFrame(infrared: tempDir.appendingPathComponent("passed.tiff.ir.tiff"))
        let landed = makeFrame(infrared: tempDir.appendingPathComponent("landed.tiff.ir.tiff"))
        model.frames = [passed, landed]

        model.frameStore.selectedFrameID = passed.id
        model.scheduleInfraredCleanForSelection(passed)
        model.frameStore.selectedFrameID = landed.id      // 곧바로 다음 사진으로 넘어간다
        model.scheduleInfraredCleanForSelection(landed)

        try await Task.sleep(nanoseconds: AppModel.infraredSelectionDebounceNanoseconds * 3)

        XCTAssertFalse(passed.infraredAutoCleanAttempted, "지나친 프레임은 시작하면 안 된다.")
        XCTAssertTrue(landed.infraredAutoCleanAttempted, "머무른 프레임은 되살려야 한다.")
        model.cancelInfraredClean(landed)
    }

    /// 사진을 여러 장 왔다 갔다 하다 돌아와도 두 번 처리하지 않는다.
    ///
    /// 두 겹으로 막는다: 세션 시도 표시(`infraredAutoCleanAttempted`)가 재실행을 막고, 그게
    /// 어떤 이유로든 뚫려도 `runInfraredClean` 의 "이미 IR 레이어가 있으면 중단"이 이중 적용을
    /// 막는다. 이중 적용은 결함 자리를 두 번 나눗셈해 없던 밝은 얼룩을 만든다.
    func testRevisitingAFrameNeitherReRunsNorStacksASecondLayer() {
        let model = AppModel()
        let frame = makeFrame(infrared: tempDir.appendingPathComponent("revisit.tiff.ir.tiff"))
        let other = makeFrame()
        model.frames = [frame, other]

        model.runInfraredCleanIfNeeded(frame)
        XCTAssertTrue(frame.infraredAutoCleanAttempted)
        model.cancelInfraredClean(frame)
        // 검출이 실제로 레이어를 남긴 상태를 흉내 낸다.
        frame.defectEdits = [infraredEdit()]

        for _ in 0..<5 {
            model.frameStore.selectedFrameID = other.id
            model.frameStore.selectedFrameID = frame.id
            model.runInfraredCleanIfNeeded(frame)
            model.runInfraredClean(frame)          // 표시를 무시하고 직접 불러도
        }
        XCTAssertEqual(frame.defectEdits.filter(\.isInfrared).count, 1,
                       "IR 레이어는 몇 번을 돌아와도 한 장이어야 한다.")
    }

    /// "적용된 결함 제거 초기화"는 사용자가 만든 레이어만 지운다. IR 은 스캔과 함께 측정된
    /// 결과이고 한 세션에 한 번만 만들어지므로, 같이 지우면 그 세션에서는 다시 만들 방법이
    /// 없어 IR 먼지 제거가 통째로 불능이 된다.
    func testClearAllDefectsKeepsTheInfraredLayer() {
        let model = AppModel()
        let frame = makeFrame(infrared: tempDir.appendingPathComponent("clear.tiff.ir.tiff"))
        model.frames = [frame]
        frame.defectEdits = [infraredEdit(), brushEdit()]

        model.clearAllDefects(frame)

        XCTAssertEqual(frame.defectEdits.count, 1, "브러시만 지워야 한다.")
        XCTAssertTrue(frame.defectEdits[0].isInfrared)
        XCTAssertTrue(frame.canUndoDefects, "초기화는 ⌘Z 로 되돌릴 수 있어야 한다.")

        model.undoDefects(frame)
        XCTAssertEqual(frame.defectEdits.count, 2, "되돌리면 지워진 레이어가 살아난다.")
    }

    /// IR 레이어뿐이면 초기화할 사용자 편집이 없다 — 아무것도 건드리지 않는다.
    func testClearAllDefectsDoesNothingWhenOnlyInfraredRemains() {
        let model = AppModel()
        let frame = makeFrame(infrared: tempDir.appendingPathComponent("only-ir.tiff.ir.tiff"))
        model.frames = [frame]
        frame.defectEdits = [infraredEdit()]

        model.clearAllDefects(frame)

        XCTAssertEqual(frame.defectEdits.count, 1)
        XCTAssertTrue(frame.defectEdits[0].isInfrared)
        XCTAssertFalse(frame.canUndoDefects, "지운 것이 없으면 undo 도 쌓이지 않는다.")
    }

    /// 결함 제거 레이어는 붙었는데 cleaned raw 픽셀이 아직 없는 순간은 실패가 아니라 보류다.
    /// 이걸 실패로 처리하면 스캔 직후 "이미지 로드 실패"가 뜬다(실측: IR 스캔 마지막 컷).
    func testMissingCleanedRawIsReportedAsPendingNotFailure() {
        let params = DevelopParameters()
        var snapshot = DevelopFrameSnapshot(
            rawScanURL: tempDir.appendingPathComponent("scan.tiff"),
            preloadedRaw: nil,
            cleanedRawURL: nil,
            filmType: .colorNegative,
            params: params,
            preset: nil,
            imageTransform: .identity,
            cachedBase: nil,
            baseKey: FilmBaseCacheKey(filmType: .colorNegative,
                                      mode: params.baseEstimationMode,
                                      manualBaseRGB: nil, filmStockDminID: nil),
            needsRawPreview: false,
            needsNeutralPreview: false,
            needsDebugPreviews: false
        )
        snapshot.requiresCleanedRaw = true
        guard case .cleanedRawPending = DevelopFrameRenderer.loadError(for: snapshot) else {
            return XCTFail("cleaned raw 를 기다리는 중은 보류여야 한다.")
        }

        snapshot.requiresCleanedRaw = false
        guard case .loadFailed = DevelopFrameRenderer.loadError(for: snapshot) else {
            return XCTFail("결함 레이어가 없는데 입력이 없으면 진짜 실패다.")
        }
    }

    // MARK: 픽스처

    private func makeFrame(infrared: URL? = nil) -> ScanFrame {
        // 원본이 디스크에 있어야 "소스 있음"으로 본다 — 자동 복원의 전제 조건이다.
        let rawURL = tempDir.appendingPathComponent("scan-\(UUID().uuidString).tiff")
        FileManager.default.createFile(atPath: rawURL.path, contents: Data([0x49, 0x49]))
        if let infrared {
            FileManager.default.createFile(atPath: infrared.path, contents: Data([0x49, 0x49]))
        }
        return ScanFrame(
            scanIndex: 1,
            rawScanURL: rawURL,
            filmType: .colorNegative,
            infraredScanURL: infrared,
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
