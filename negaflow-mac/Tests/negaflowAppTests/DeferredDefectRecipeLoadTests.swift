import XCTest
@testable import negaflowApp

/// 결함 기록 지연 읽기. 시작은 카탈로그의 식별값만 얹고, 항목은 그 사진을 쓸 때 읽는다.
/// 기록(IR 은 장당 수십 MB)이 쌓여도 첫 사진과 상주 메모리가 기록 크기를 따라가지 않아야 한다.
@MainActor
final class DeferredDefectRecipeLoadTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "negaflow-deferred-defects-\(UUID().uuidString)",
        isDirectory: true
    )

    // MARK: - 카탈로그 레코드

    func testRecordCarriesRecipeIdentityOnlyForFramesWithDefects() throws {
        let frame = makeFrame()
        frame.defectEdits = [makeEdit()]
        let identity = try makeIdentity(revision: 3)
        frame.defectRecipeIdentity = identity

        XCTAssertEqual(LibraryFrameRecord(frame: frame).defectRecipeIdentity, identity)

        frame.defectEdits = []
        XCTAssertNil(LibraryFrameRecord(frame: frame).defectRecipeIdentity)
    }

    func testRecordWithoutOrWithUnknownRecipeIdentityStillDecodes() throws {
        let frame = makeFrame()
        frame.defectEdits = [makeEdit()]
        frame.defectRecipeIdentity = try makeIdentity(revision: 3)
        let encoded = try JSONEncoder().encode(LibraryFrameRecord(frame: frame))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        var legacy = object
        legacy.removeValue(forKey: "defectRecipeIdentity")
        let legacyRecord = try JSONDecoder().decode(
            LibraryFrameRecord.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertNil(legacyRecord.defectRecipeIdentity)
        XCTAssertEqual(legacyRecord.hasDefectEdits, true)

        // 이 앱이 모르는 지문 형식은 지름길만 버리고 사진은 연다 — 기록은 그때 읽는다.
        var future = object
        var identity = try XCTUnwrap(future["defectRecipeIdentity"] as? [String: Any])
        identity["fingerprintVersion"] = 999
        future["defectRecipeIdentity"] = identity
        let futureRecord = try JSONDecoder().decode(
            LibraryFrameRecord.self,
            from: JSONSerialization.data(withJSONObject: future)
        )
        XCTAssertNil(futureRecord.defectRecipeIdentity)
        XCTAssertEqual(futureRecord.id, frame.id)
    }

    // MARK: - 시작과 읽기

    func testRelaunchShowsFramesWithoutReadingDefectItems() async throws {
        let (_, frame) = try makeSavedLibraryWithDefectFrame()
        let identity = try XCTUnwrap(frame.defectRecipeIdentity)
        let thumbnailRecipeID = try XCTUnwrap(frame.currentThumbnailRecipeID())

        let relaunched = await relaunch()
        let restored = try XCTUnwrap(relaunched.frames.first { $0.id == frame.id })

        XCTAssertTrue(restored.defectEditsLoadDeferred)
        XCTAssertTrue(restored.defectEditsNeedRestore)
        XCTAssertTrue(restored.defectEdits.isEmpty)
        XCTAssertEqual(restored.defectRecipeIdentity, identity)
        // 썸네일 캐시는 결함 식별값으로 맞춘다 — 읽기 전에도 같은 썸네일을 그대로 쓴다.
        XCTAssertEqual(restored.currentThumbnailRecipeID(), thumbnailRecipeID)
        // 읽지 않은 기록은 저장도 종료도 막지 않는다.
        XCTAssertTrue(relaunched.saveLibrary(synchronous: true), String(describing: lastCatalogSaveFailureCode()))
        let baked = await relaunched.bakeDefectEditsForTermination()
        XCTAssertTrue(baked)
        XCTAssertTrue(restored.defectEditsLoadDeferred)
    }

    func testDeferredLoadRestoresItemsOnceForConcurrentRequests() async throws {
        let (_, frame) = try makeSavedLibraryWithDefectFrame()
        let editIDs = frame.defectEdits.map(\.id)
        let identity = try XCTUnwrap(frame.defectRecipeIdentity)
        let relaunched = await relaunch()
        let restored = try XCTUnwrap(relaunched.frames.first { $0.id == frame.id })

        let first = relaunched.startDeferredDefectEditsLoad(restored)
        let second = relaunched.startDeferredDefectEditsLoad(restored)
        let firstLoaded = await first.value
        let secondLoaded = await relaunched.loadDeferredDefectEdits(restored)

        XCTAssertTrue(firstLoaded)
        XCTAssertTrue(secondLoaded)
        let secondTaskLoaded = await second.value
        XCTAssertTrue(secondTaskLoaded)
        XCTAssertFalse(restored.defectEditsLoadDeferred)
        XCTAssertFalse(restored.defectEditsNeedRestore)
        XCTAssertNil(restored.defectEditsLoadTask)
        XCTAssertEqual(restored.defectEdits.map(\.id), editIDs)
        XCTAssertEqual(restored.defectRecipeIdentity, identity)
        XCTAssertTrue(relaunched.isDefectRecipeCommitted(restored))
        XCTAssertTrue(relaunched.saveLibrary(synchronous: true), String(describing: lastCatalogSaveFailureCode()))
    }

    /// 예전 카탈로그(식별값 없음)는 이번 시작에 기록을 읽어 식별값을 채우고, 다음 시작부터 지연 읽기다.
    func testLegacyCatalogReadsRecipesOnceAndRecordsIdentity() async throws {
        let (_, frame) = try makeSavedLibraryWithDefectFrame()
        let identity = try XCTUnwrap(frame.defectRecipeIdentity)
        try rewriteCatalog { $0.defectRecipeIdentity = nil }

        let migrated = await relaunch()
        let eager = try XCTUnwrap(migrated.frames.first { $0.id == frame.id })
        XCTAssertFalse(eager.defectEditsLoadDeferred)
        XCTAssertFalse(eager.defectEditsNeedRestore)
        XCTAssertEqual(eager.defectEdits.count, 1)
        XCTAssertEqual(eager.defectRecipeIdentity, identity)
        XCTAssertTrue(migrated.saveLibrary(synchronous: true), String(describing: lastCatalogSaveFailureCode()))
        XCTAssertEqual(try storedRecord(frame.id).defectRecipeIdentity, identity)
        Self.release(migrated)

        let next = await relaunch()
        let deferred = try XCTUnwrap(next.frames.first { $0.id == frame.id })
        XCTAssertTrue(deferred.defectEditsLoadDeferred)
        XCTAssertEqual(deferred.defectRecipeIdentity, identity)
    }

    /// 기록을 쓴 직후 카탈로그를 저장하지 못하고 꺼진 경우. 카탈로그 식별값은 지름길일 뿐이고
    /// 기록이 진실이다 — 읽을 때 기록 쪽 세대로 맞추고 카탈로그도 따라간다.
    func testStaleCatalogIdentityYieldsToTheRecordOnLoad() async throws {
        let (_, frame) = try makeSavedLibraryWithDefectFrame()
        let stale = try XCTUnwrap(frame.defectRecipeIdentity)
        let newer = try DefectRecipeSnapshot(
            frameID: frame.id,
            revision: stale.revision + 1,
            sourceIdentity: stale.sourceIdentity,
            items: frame.defectEdits.map { DefectEditItemRecord(item: $0) }
        )
        guard case .written = try DefectSidecarFile.write(newer, in: defectDirectory) else {
            return XCTFail("더 새 세대 기록을 써야 합니다.")
        }

        let relaunched = await relaunch()
        let restored = try XCTUnwrap(relaunched.frames.first { $0.id == frame.id })
        XCTAssertEqual(restored.defectRecipeIdentity, stale)

        let loaded = await relaunched.loadDeferredDefectEdits(restored)

        XCTAssertTrue(loaded)
        XCTAssertEqual(restored.defectRecipeIdentity, newer.identity)
        XCTAssertEqual(restored.defectRecipeRevision, newer.identity.revision)
        XCTAssertTrue(relaunched.saveLibrary(synchronous: true), String(describing: lastCatalogSaveFailureCode()))
        XCTAssertEqual(try storedRecord(frame.id).defectRecipeIdentity, newer.identity)
    }

    /// 읽을 때 기록이 사라졌으면 시작 때 읽기에 실패한 것과 같은 상태가 된다(저장 검증·복구가 다룬다).
    func testMissingRecordOnLoadBecomesRestorePending() async throws {
        let (_, frame) = try makeSavedLibraryWithDefectFrame()
        let relaunched = await relaunch()
        let restored = try XCTUnwrap(relaunched.frames.first { $0.id == frame.id })
        try FileManager.default.removeItem(at: DefectSidecarFile.url(for: frame.id, in: defectDirectory))

        let loaded = await relaunched.loadDeferredDefectEdits(restored)

        XCTAssertFalse(loaded)
        XCTAssertFalse(restored.defectEditsLoadDeferred)
        XCTAssertTrue(restored.defectEditsNeedRestore)
        XCTAssertNil(restored.defectRecipeIdentity)
        XCTAssertFalse(relaunched.saveLibrary(synchronous: true))
        XCTAssertEqual(lastCatalogSaveFailureCode(), "catalog_snapshot_invalid.defect_restore_pending")
    }

    // MARK: - 기록을 쓰는 경로

    func testExportOfADeferredFrameReadsItsRecipeFirst() async throws {
        let (_, frame) = try makeSavedLibraryWithDefectFrame()
        let relaunched = await relaunch()
        let restored = try XCTUnwrap(relaunched.frames.first { $0.id == frame.id })

        // 원본 그대로 내보내기는 결함 기록이 필요 없다.
        let rawPrepared = await relaunched.prepareCleanedRawForExport(restored, format: .rawScanTIFF)
        XCTAssertTrue(rawPrepared)
        XCTAssertTrue(restored.defectEditsLoadDeferred)

        // 결함 제거가 들어가는 내보내기는 기록을 읽은 뒤 판단한다(원본이 없어 여기서는 실패한다).
        // 읽지 않은 채 "결함 없음"으로 보고 통과시키면 결함 제거 없이 내보내게 된다.
        let developedPrepared = await relaunched.prepareCleanedRawForExport(restored, format: .tiff16)
        XCTAssertFalse(developedPrepared)
        XCTAssertFalse(restored.defectEditsLoadDeferred)
        XCTAssertEqual(restored.defectEdits.count, 1)
    }

    func testManualBackupCopiesDeferredRecordWithoutLoadingIt() async throws {
        let (_, frame) = try makeSavedLibraryWithDefectFrame()
        let relaunched = await relaunch()
        let restored = try XCTUnwrap(relaunched.frames.first { $0.id == frame.id })

        let payload = await relaunched.makeManualBackupPayload()

        let backedUp = try XCTUnwrap(payload?.defectDataByFrameID[frame.id])
        XCTAssertEqual(backedUp, DefectSidecarFile.validatedRawData(for: frame.id, in: defectDirectory))
        XCTAssertTrue(restored.defectEditsLoadDeferred)
        XCTAssertTrue(restored.defectEdits.isEmpty)
    }

    func testRelinkLeavesAnUnreadRecipeForTheBuildToRecheck() async throws {
        let (_, frame) = try makeSavedLibraryWithDefectFrame()
        let identity = try XCTUnwrap(frame.defectRecipeIdentity)
        let relaunched = await relaunch()
        let restored = try XCTUnwrap(relaunched.frames.first { $0.id == frame.id })

        XCTAssertTrue(relaunched.invalidateDefectRecipeSourceBindingsForRelink([restored]))

        XCTAssertTrue(restored.defectEditsLoadDeferred)
        XCTAssertEqual(restored.defectRecipeIdentity, identity)
        XCTAssertTrue(relaunched.saveLibrary(synchronous: true), String(describing: lastCatalogSaveFailureCode()))
        guard case .loaded(.currentV2(_, let stored)) = DefectSidecarFile.read(
            for: frame.id, in: defectDirectory
        ) else {
            return XCTFail("읽지 않은 기록은 그대로 남아야 합니다.")
        }
        XCTAssertEqual(stored.identity, identity)
    }

    // MARK: - 메모리 캐시 한도

    func testCleanedRawEvictionUnloadsCommittedItemsUntilNextUse() async throws {
        let (_, frame) = try makeSavedLibraryWithDefectFrame()
        let editIDs = frame.defectEdits.map(\.id)
        let identity = try XCTUnwrap(frame.defectRecipeIdentity)
        let relaunched = await relaunch()
        let restored = try XCTUnwrap(relaunched.frames.first { $0.id == frame.id })
        let loaded = await relaunched.loadDeferredDefectEdits(restored)
        XCTAssertTrue(loaded)

        relaunched.evictCleanedRawBuffers(restored)

        XCTAssertTrue(restored.defectEditsLoadDeferred)
        XCTAssertTrue(restored.defectEditsNeedRestore)
        XCTAssertTrue(restored.defectEdits.isEmpty)
        XCTAssertEqual(restored.defectRecipeIdentity, identity)
        XCTAssertTrue(relaunched.saveLibrary(synchronous: true), String(describing: lastCatalogSaveFailureCode()))
        XCTAssertEqual(try storedRecord(frame.id).defectRecipeIdentity, identity)

        let reloaded = await relaunched.loadDeferredDefectEdits(restored)
        XCTAssertTrue(reloaded)
        XCTAssertEqual(restored.defectEdits.map(\.id), editIDs)
    }

    /// 선택한 사진, 되돌리기 기록이 남은 사진, 디스크와 세대가 다른 사진은 내려놓지 않는다.
    func testCleanedRawEvictionKeepsItemsThatAreInUseOrUncommitted() async throws {
        let (_, frame) = try makeSavedLibraryWithDefectFrame()
        let relaunched = await relaunch()
        let restored = try XCTUnwrap(relaunched.frames.first { $0.id == frame.id })
        let loaded = await relaunched.loadDeferredDefectEdits(restored)
        XCTAssertTrue(loaded)

        relaunched.frameStore.selectedFrameID = restored.id
        relaunched.evictCleanedRawBuffers(restored)
        XCTAssertFalse(restored.defectEditsLoadDeferred)
        relaunched.frameStore.selectedFrameID = nil

        restored.defectHistoryDepth = 1
        relaunched.evictCleanedRawBuffers(restored)
        XCTAssertFalse(restored.defectEditsLoadDeferred)
        restored.defectHistoryDepth = 0

        restored.defectRecipeRevision += 1
        relaunched.evictCleanedRawBuffers(restored)
        XCTAssertFalse(restored.defectEditsLoadDeferred)
        XCTAssertEqual(restored.defectEdits.count, 1)
    }

    /// 이웃 사진의 기록은 파일만 데운다 — 항목을 올리면 지연 읽기로 줄인 상주 메모리가 되돌아온다.
    func testWarmingNeighborRecordsDoesNotLoadTheirItems() async throws {
        let (_, frame) = try makeSavedLibraryWithDefectFrame()
        let relaunched = await relaunch()
        let restored = try XCTUnwrap(relaunched.frames.first { $0.id == frame.id })
        let selected = makeFrame()
        relaunched.frames.insert(selected, at: 0)

        relaunched.warmNeighborDefectRecords(around: selected)
        let warm = try XCTUnwrap(relaunched.defectRecordWarmTask)
        await warm.value

        XCTAssertTrue(restored.defectEditsLoadDeferred)
        XCTAssertTrue(restored.defectEdits.isEmpty)
        XCTAssertNil(restored.defectEditsLoadTask)
    }

    // MARK: - Helpers

    private var catalogURL: URL { root.appendingPathComponent("library.sqlite") }
    private var defectDirectory: URL { root.appendingPathComponent("defects", isDirectory: true) }
    private var backupDirectory: URL { root.appendingPathComponent("Backups", isDirectory: true) }

    private func makeModel() -> AppModel {
        let root = root
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defectDirectory,
            libraryBackupDirectoryURL: backupDirectory
        )
    }

    private func relaunch() async -> AppModel {
        let model = makeModel()
        await model.restoreLibraryOnLaunch()
        addTeardownBlock { @MainActor in Self.release(model) }
        return model
    }

    private static func release(_ model: AppModel) {
        model.libraryPersistenceEnabled = false
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        model.libraryProcessLock = nil
    }

    /// 원본에 묶인 결함 기록 하나를 가진 사진을 저장해 둔 라이브러리.
    private func makeSavedLibraryWithDefectFrame() throws -> (AppModel, ScanFrame) {
        let model = makeModel()
        model.libraryPersistenceEnabled = false
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Deferred",
            filmType: .colorNegative,
            activate: true
        ))
        let frame = makeFrame()
        frame.establishLibraryWorkflowBaselineIfNeeded()
        frame.defectEdits = [makeEdit()]
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame], toRollID: roll.id))
        let snapshot = try XCTUnwrap(model.refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: false
        ))
        let bound = try model.bindDefectRecipeSnapshot(snapshot, to: makeSourceIdentity())
        model.installDefectRecipeIdentity(bound.identity, on: frame)
        model.persistDefectRecipe(bound, for: frame)
        DefectSidecarFile.flushSync()

        model.libraryPersistenceEnabled = true
        model.transitionLibraryLifecycle(to: .ready)
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        XCTAssertTrue(model.saveLibrary(synchronous: true), String(describing: lastCatalogSaveFailureCode()))
        model.libraryPersistenceEnabled = false
        return (model, frame)
    }

    private func rewriteCatalog(_ change: (inout LibraryFrameRecord) -> Void) throws {
        guard case .loaded(var catalog, _) = LibraryCatalogFile.read(from: catalogURL) else {
            return XCTFail("저장한 카탈로그를 읽을 수 있어야 합니다.")
        }
        for index in catalog.frames.indices { change(&catalog.frames[index]) }
        XCTAssertTrue(LibraryCatalogFile.writeCatalogSync(catalog, to: catalogURL))
    }

    private func storedRecord(_ id: UUID) throws -> LibraryFrameRecord {
        guard case .loaded(let catalog, _) = LibraryCatalogFile.read(from: catalogURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try XCTUnwrap(catalog.frames.first { $0.id == id })
    }

    private func lastCatalogSaveFailureCode() -> String? {
        AppDiagnostics.recentEvents.last(where: {
            $0.operation == .catalogSave && $0.phase == .error
        })?.code
    }

    private func makeFrame() -> ScanFrame {
        ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/deferred-defects.tiff"),
            filmType: .colorNegative
        )
    }

    private func makeSourceIdentity() throws -> DefectSourceIdentity {
        try DefectSourceIdentity(byteCount: 4_096, sha256: String(repeating: "ab", count: 32))
    }

    private func makeIdentity(revision: UInt64) throws -> DefectRecipeIdentity {
        try DefectRecipeSnapshot(
            frameID: UUID(),
            revision: revision,
            sourceIdentity: makeSourceIdentity(),
            items: [DefectEditItemRecord(item: makeEdit())]
        ).identity
    }

    private func makeEdit() -> DefectEditItem {
        DefectEditItem(
            edit: .brush([DefectStroke(
                points: [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.4, y: 0.5)],
                thickness: 0.05
            )]),
            enabled: true,
            strength: 1,
            label: .brush(strokeCount: 1),
            summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
            preview: [],
            baseSize: nil
        )
    }
}
