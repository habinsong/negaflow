import XCTest
@testable import negaflowApp

@MainActor
final class DefectRecipeRuntimeTests: XCTestCase {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testSameLayerCountWithDifferentStrengthInvalidatesCleanedRawIdentity() throws {
        let model = AppModel()
        let frame = makeFrame()
        model.frames = [frame]
        frame.defectEdits = [makeEdit(strength: 1)]
        let first = try XCTUnwrap(model.refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: false
        ))
        frame.cleanedRawMemoryIdentity = first.identity
        frame.cleanedRawEditCount = 1

        frame.defectEdits[0].strength = 0.4
        let second = try XCTUnwrap(model.refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: false
        ))

        XCTAssertEqual(first.items.count, second.items.count)
        XCTAssertEqual(second.identity.revision, first.identity.revision + 1)
        XCTAssertNotEqual(second.identity.recipeSHA256, first.identity.recipeSHA256)
        XCTAssertNotEqual(frame.cleanedRawMemoryIdentity, frame.defectRecipeIdentity)
    }

    func testBoundRecipeUpdatesReviewTripletAndLaterEditBecomesUnreviewed() throws {
        let model = AppModel()
        let frame = makeFrame()
        model.frames = [frame]
        frame.defectEdits = [makeEdit(strength: 1)]
        let unbound = try XCTUnwrap(model.refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: false
        ))
        let source = try DefectSourceIdentity(
            byteCount: 123,
            sha256: String(repeating: "b", count: 64)
        )
        let bound = try model.bindDefectRecipeSnapshot(unbound, to: source)
        model.installDefectRecipeIdentity(bound.identity, on: frame)
        model.markDefectRecipeReviewed(frame)

        var tracking = try XCTUnwrap(frame.libraryWorkflowTrackingState).defectReviewTracking
        XCTAssertEqual(tracking.currentRecipeRevision, bound.identity.revision)
        XCTAssertEqual(tracking.reviewedRecipeRevision, bound.identity.revision)
        XCTAssertEqual(tracking.currentSourceIdentitySHA256, source.sha256)

        frame.defectEdits[0].strength = 0.25
        let edited = try XCTUnwrap(model.refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: false
        ))
        tracking = try XCTUnwrap(frame.libraryWorkflowTrackingState).defectReviewTracking

        XCTAssertEqual(tracking.currentRecipeRevision, edited.identity.revision)
        XCTAssertEqual(tracking.currentRecipeSHA256, edited.identity.recipeSHA256)
        XCTAssertEqual(tracking.reviewedRecipeRevision, bound.identity.revision)
        XCTAssertNotEqual(tracking.reviewedRecipeSHA256, edited.identity.recipeSHA256)
    }

    func testRecipeStateRefreshWritesNoSidecar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-defect-runtime-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: defects,
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        model.libraryPersistenceEnabled = true
        let frame = makeFrame()
        frame.defectEdits = [makeEdit(strength: 0.8)]

        let refreshed = try XCTUnwrap(model.refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: true
        ))
        DefectSidecarFile.flushSync()

        // 기록은 세션 메모리에만 있다 — persist 요청과 무관하게 sidecar가 생기지 않는다.
        XCTAssertEqual(refreshed.identity, frame.defectRecipeIdentity)
        guard case .missing = DefectSidecarFile.read(for: frame.id, in: defects) else {
            return XCTFail("defect recipes must not persist to disk")
        }
        XCTAssertNil(frame.cleanedRawDiskURL)
        XCTAssertNil(frame.cleanedRawDiskIdentity)
    }

    func testLibraryRestoreIgnoresLegacyDefectRecordsAndSweepsStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-async-cache-restore-\(UUID().uuidString)",
            isDirectory: true
        )
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let catalogURL = root.appendingPathComponent("library.json")
        let rawURL = root.appendingPathComponent("source.tiff")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("authoritative source pixels".utf8).write(to: rawURL)
        let source = ScanFrame(
            scanIndex: 1,
            rawScanURL: rawURL,
            filmType: .colorNegative
        )
        source.establishLibraryWorkflowBaselineIfNeeded()
        let edit = makeEdit(strength: 0.7)
        let snapshot = try makeBoundSnapshot(
            frameID: source.id,
            revision: 3,
            edit: edit,
            sourceIdentity: AppModel.defectSourceIdentity(for: rawURL)
        )
        let cacheURL = CleanedRawCacheFile.makeBuildURL(frameID: source.id)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: cacheURL)
        }
        try FileManager.default.createDirectory(at: defects, withIntermediateDirectories: true)
        try Data("stale cleaned raw".utf8).write(to: cacheURL)
        _ = try DefectSidecarFile.write(snapshot, in: defects)
        source.defectEdits = [edit]
        source.defectRecipeIdentity = snapshot.identity
        source.defectRecipeRevision = snapshot.identity.revision
        let catalog = LibraryCatalog(frames: [LibraryFrameRecord(frame: source)])
        XCTAssertTrue(LibraryCatalogFile.write(
            try XCTUnwrap(LibraryCatalogFile.encode(catalog)),
            to: catalogURL
        ))

        let model = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defects,
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        await model.restoreLibraryOnLaunch()
        defer {
            model.libraryPersistenceEnabled = false
            model.librarySaveTask?.cancel()
            model.librarySaveTask = nil
        }
        let restored = try XCTUnwrap(model.frames.first)

        // 기록은 세션을 넘지 않는다: 복원 프레임에 결함 상태가 없고, 잔재 sidecar는 청소된다.
        XCTAssertFalse(restored.defectEditsNeedRestore)
        XCTAssertTrue(restored.defectEdits.isEmpty)
        XCTAssertNil(restored.defectRecipeIdentity)
        XCTAssertNil(restored.cleanedRawDiskURL)
        XCTAssertNil(restored.cleanedRawDiskIdentity)
        guard case .missing = DefectSidecarFile.read(for: source.id, in: defects) else {
            return XCTFail("leftover sidecars must be swept at launch")
        }
    }

    func testLiveDefectGestureDefersCatalogAndAcknowledgedCommit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-defect-gesture-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Gesture",
            filmType: .colorNegative,
            activate: true
        ))
        let frame = makeFrame()
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame], toRollID: roll.id))
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        model.libraryPersistenceEnabled = true
        model.transitionLibraryLifecycle(to: .ready)
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        let baseline = try Data(contentsOf: model.libraryCatalogURL)

        frame.defectGestureRecipeAdvanced = true

        XCTAssertFalse(model.saveLibrary(synchronous: true))
        XCTAssertFalse(model.beginAcknowledgedLibraryTransaction())
        XCTAssertEqual(try Data(contentsOf: model.libraryCatalogURL), baseline)

        frame.defectGestureRecipeAdvanced = false
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        XCTAssertTrue(model.saveLibrary(synchronous: true))
    }

    func testCatalogSaveSucceedsWithInMemoryEditsAndNoSidecar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-defect-generation-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: defects,
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        model.libraryPersistenceEnabled = false
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Generation",
            filmType: .colorNegative,
            activate: true
        ))
        let frame = makeFrame()
        frame.defectEdits = [makeEdit(strength: 1)]
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame], toRollID: roll.id))
        _ = try XCTUnwrap(model.refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: false
        ))

        model.libraryPersistenceEnabled = true
        model.transitionLibraryLifecycle(to: .ready)
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil

        // 결함 기록이 메모리에만 있어도 catalog 저장은 성공하고, 결함 상태는 기록되지 않는다.
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.libraryCatalogURL.path))
        let record = try XCTUnwrap(model.libraryFrameRecordCache[frame.id])
        XCTAssertNil(record.hasDefectEdits)
        XCTAssertNil(record.cleanedRawPath)
        XCTAssertNil(record.cleanedRawEditCount)
    }

    func testRapidLiveStrengthTicksCoalesceAndFinalPersistUsesLatestRecipe() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-live-fingerprint-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: defects,
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        defer {
            model.libraryPersistenceEnabled = false
            model.librarySaveTask?.cancel()
            model.librarySaveTask = nil
        }
        model.libraryPersistenceEnabled = true
        let frame = makeFrame()
        frame.defectEdits = [makeLargeRegionEdit(strength: 1)]
        model.frames = [frame]
        let initial = try XCTUnwrap(model.refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: false
        ))
        let source = try DefectSourceIdentity(
            byteCount: 256,
            sha256: String(repeating: "d", count: 64)
        )
        let boundInitial = try model.bindDefectRecipeSnapshot(initial, to: source)
        model.installDefectRecipeIdentity(boundInitial.identity, on: frame)
        let editID = try XCTUnwrap(frame.defectEdits.first?.id)

        var firstWorkerID: UUID?
        for tick in 0..<30 {
            let strength = 0.2 + (Double(tick) * 0.02)
            model.setDefectEditStrength(frame, id: editID, strength: strength, live: true)
            if let firstWorkerID {
                XCTAssertEqual(frame.defectRecipeRefreshWorkerID, firstWorkerID)
            } else {
                firstWorkerID = frame.defectRecipeRefreshWorkerID
            }
        }

        // MainActor에서 연속 호출한 시점에는 큰 mask fingerprint가 아직
        // 실행되지 않았으며, 제스처 revision/undo는 한 번만 증가한다.
        XCTAssertNil(frame.defectRecipeIdentity)
        XCTAssertNotNil(frame.defectRecipeRefreshTask)
        XCTAssertEqual(frame.defectRecipeRevision, initial.identity.revision + 1)
        // 드래그 중에는 되돌리기 한 칸이 아직 확정되지 않는다 — 시작 시점 상태만 들고 있다가
        // 값이 확정될 때 한 번만 히스토리로 넘어간다.
        XCTAssertNotNil(frame.pendingDefectHistorySnapshot)
        XCTAssertEqual(frame.defectHistoryDepth, 0)
        XCTAssertTrue(frame.defectGestureRecipeAdvanced)

        for _ in 0..<400 where frame.defectRecipeRefreshTask != nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        let liveIdentity = try XCTUnwrap(frame.defectRecipeIdentity)
        let expectedLive = try DefectRecipeSnapshot(
            frameID: frame.id,
            revision: initial.identity.revision + 1,
            sourceIdentity: source,
            items: frame.defectEdits.map { DefectEditItemRecord(item: $0) }
        )
        XCTAssertEqual(liveIdentity, expectedLive.identity)
        XCTAssertNil(frame.defectRecipeRefreshTask)

        let finalStrength = try XCTUnwrap(frame.defectEdits.first?.strength)
        model.setDefectEditStrength(frame, id: editID, strength: finalStrength)

        XCTAssertFalse(frame.defectGestureRecipeAdvanced)
        XCTAssertFalse(frame.defectGestureUndoPushed)
        XCTAssertNil(frame.defectGestureSourceIdentity)
        XCTAssertNil(frame.defectRecipeRefreshTask)
        XCTAssertEqual(frame.defectRecipeIdentity, expectedLive.identity)
        // 기록은 디스크에 남지 않는다.
        guard case .missing = DefectSidecarFile.read(for: frame.id, in: defects) else {
            return XCTFail("live recipes must not persist to disk")
        }
    }

    func testCoalescingWorkerPublishesLiveIdentityWhileTicksContinue() async throws {
        let model = AppModel()
        let frame = makeFrame()
        frame.defectEdits = [makeEdit(strength: 1)]
        model.frames = [frame]
        let initial = try XCTUnwrap(model.refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: false
        ))
        let editID = try XCTUnwrap(frame.defectEdits.first?.id)
        var observedLiveIdentityDuringInput = false

        // 15ms tick이 300ms 이상 계속되는 중에 identity가 한 번이라도
        // 공개되어야 한다. 매 tick마다 취소·재예약하는 trailing debounce는
        // 입력이 끝나기 전에 이 조건을 만족할 수 없다.
        for tick in 0..<22 {
            let strength = tick.isMultiple(of: 2) ? 0.32 : 0.72
            model.setDefectEditStrength(frame, id: editID, strength: strength, live: true)
            try await Task.sleep(nanoseconds: 15_000_000)
            if tick < 21, frame.defectRecipeIdentity != nil {
                observedLiveIdentityDuringInput = true
            }
        }

        XCTAssertTrue(observedLiveIdentityDuringInput)
        XCTAssertEqual(frame.defectRecipeRevision, initial.identity.revision + 1)
        // 드래그 중에는 되돌리기 한 칸이 아직 확정되지 않는다 — 시작 시점 상태만 들고 있다가
        // 값이 확정될 때 한 번만 히스토리로 넘어간다.
        XCTAssertNotNil(frame.pendingDefectHistorySnapshot)
        XCTAssertEqual(frame.defectHistoryDepth, 0)

        let finalStrength = try XCTUnwrap(frame.defectEdits.first?.strength)
        model.setDefectEditStrength(frame, id: editID, strength: finalStrength)
        XCTAssertFalse(frame.defectGestureRecipeAdvanced)
        XCTAssertNil(frame.defectRecipeRefreshTask)
        frame.cleanRawTask?.cancel()
        frame.cleanRawTask = nil
    }

    func testSemanticMutationCancelsLiveWorkerAndClosesGesture() async throws {
        let model = AppModel()
        let frame = makeFrame()
        frame.defectEdits = [makeEdit(strength: 1)]
        model.frames = [frame]
        let initial = try XCTUnwrap(model.refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: false
        ))
        let editID = try XCTUnwrap(frame.defectEdits.first?.id)

        model.setDefectEditStrength(frame, id: editID, strength: 0.45, live: true)
        XCTAssertTrue(frame.defectGestureRecipeAdvanced)
        XCTAssertNotNil(frame.defectRecipeRefreshTask)

        model.setDefectEditEnabled(frame, id: editID, enabled: false)
        let identityAfterEnabled = try XCTUnwrap(frame.defectRecipeIdentity)

        XCTAssertFalse(frame.defectGestureRecipeAdvanced)
        XCTAssertFalse(frame.defectGestureUndoPushed)
        XCTAssertNil(frame.defectGestureSourceIdentity)
        XCTAssertNil(frame.defectRecipeRefreshTask)
        XCTAssertEqual(identityAfterEnabled.revision, initial.identity.revision + 2)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(frame.defectRecipeIdentity, identityAfterEnabled)
        frame.cleanRawTask?.cancel()
        frame.cleanRawTask = nil
    }

    func testRelinkInvalidationCancelsPendingLiveWorkerBeforeMemoryCommit() async throws {
        let model = AppModel()
        let frame = makeFrame()
        frame.defectEdits = [makeEdit(strength: 1)]
        model.frames = [frame]
        let initial = try XCTUnwrap(model.refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: false
        ))
        let source = try DefectSourceIdentity(
            byteCount: 512,
            sha256: String(repeating: "e", count: 64)
        )
        model.installDefectRecipeIdentity(
            try model.bindDefectRecipeSnapshot(initial, to: source).identity,
            on: frame
        )
        let editID = try XCTUnwrap(frame.defectEdits.first?.id)

        model.setDefectEditStrength(frame, id: editID, strength: 0.42, live: true)
        XCTAssertNotNil(frame.defectRecipeRefreshTask)
        XCTAssertTrue(model.invalidateDefectRecipeSourceBindingsForRelink([frame]))
        let relinkIdentity = try XCTUnwrap(frame.defectRecipeIdentity)

        XCTAssertNil(relinkIdentity.sourceIdentity)
        XCTAssertFalse(frame.defectGestureRecipeAdvanced)
        XCTAssertNil(frame.defectGestureSourceIdentity)
        XCTAssertNil(frame.defectRecipeRefreshTask)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(frame.defectRecipeIdentity, relinkIdentity)
        XCTAssertNil(frame.defectRecipeIdentity?.sourceIdentity)
    }

    func testTerminationFinalizesPendingLiveFingerprintBeforeCatalogSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-live-fingerprint-termination-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: defects,
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Live termination",
            filmType: .colorNegative,
            activate: true
        ))
        let frame = makeFrame()
        frame.defectEdits = [makeLargeRegionEdit(strength: 1)]
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame], toRollID: roll.id))
        let initial = try XCTUnwrap(model.refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: false
        ))
        let editID = try XCTUnwrap(frame.defectEdits.first?.id)
        model.libraryPersistenceEnabled = true
        model.transitionLibraryLifecycle(to: .ready)

        model.setDefectEditStrength(frame, id: editID, strength: 0.37, live: true)
        XCTAssertNotNil(frame.defectRecipeRefreshTask)
        XCTAssertTrue(frame.defectGestureRecipeAdvanced)

        model.saveLibraryOnTerminate()

        _ = initial
        XCTAssertFalse(frame.defectGestureRecipeAdvanced)
        XCTAssertFalse(frame.defectGestureUndoPushed)
        XCTAssertNil(frame.defectGestureSourceIdentity)
        XCTAssertNil(frame.defectRecipeRefreshTask)
        // 기록은 디스크에 남지 않고 catalog 저장은 성공한다.
        guard case .missing = DefectSidecarFile.read(for: frame.id, in: defects) else {
            return XCTFail("termination must not persist defect recipes")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.libraryCatalogURL.path))
    }

    private func makeFrame() -> ScanFrame {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/defect-runtime.tiff"),
            filmType: .colorNegative
        )
        frame.establishLibraryWorkflowBaselineIfNeeded()
        return frame
    }

    private func makeEdit(strength: Double) -> DefectEditItem {
        DefectEditItem(
            edit: .brush([DefectStroke(
                points: [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.4, y: 0.5)],
                thickness: 0.05
            )]),
            enabled: true,
            strength: strength,
            label: .brush(strokeCount: 1),
            summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
            preview: [],
            baseSize: nil
        )
    }

    private func makeLargeRegionEdit(strength: Double) -> DefectEditItem {
        let width = 512
        let height = 512
        return DefectEditItem(
            edit: .region(
                mask: .raw(Data(repeating: 0xff, count: width * height * 4)),
                roi: CGRect(x: 0, y: 0, width: width, height: height),
                width: width,
                height: height
            ),
            enabled: true,
            strength: strength,
            label: .guided(count: 1),
            summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
            preview: [],
            baseSize: CGSize(width: width, height: height)
        )
    }

    private func makeBoundSnapshot(
        frameID: UUID,
        revision: UInt64,
        edit: DefectEditItem,
        sourceIdentity: DefectSourceIdentity? = nil
    ) throws -> DefectRecipeSnapshot {
        try DefectRecipeSnapshot(
            frameID: frameID,
            revision: revision,
            sourceIdentity: sourceIdentity ?? DefectSourceIdentity(
                byteCount: 128,
                sha256: String(repeating: "c", count: 64)
            ),
            items: [DefectEditItemRecord(item: edit)]
        )
    }
}
