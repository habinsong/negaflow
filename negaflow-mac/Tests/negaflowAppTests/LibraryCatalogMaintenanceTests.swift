import XCTest
@testable import negaflowApp

/// 진단 패널의 카탈로그 수동 복구/재설치. 둘 다 "결함 기록 불일치로 카탈로그 저장이 전부
/// 막히고 스캔 발행이 ioFailure 로 끝나는" 증상을 풀어야 한다.
@MainActor
final class LibraryCatalogMaintenanceTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "negaflow-catalog-maintenance-\(UUID().uuidString)",
        isDirectory: true
    )
    private var terminationRequests = 0

    /// 백업·동기화 도구가 수정 시각만 바꾼 경우. 관찰값은 어긋나지만 디스크 기록이 같은 세대이므로
    /// 버튼 없이도 저장이 막히면 안 된다.
    func testMetadataOnlySidecarChangeDoesNotBlockCatalogSave() throws {
        let (model, frame) = try makeReadyModelWithDefectFrame()
        let sidecar = DefectSidecarFile.url(for: frame.id, in: defectDirectory)
        let identity = try XCTUnwrap(frame.defectRecipeIdentity)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3_600)],
            ofItemAtPath: sidecar.path
        )
        XCTAssertFalse(DefectSidecarCommitCache.shared.matches(identity, at: sidecar))

        XCTAssertTrue(model.saveLibrary(synchronous: true))
        XCTAssertTrue(DefectSidecarCommitCache.shared.matches(identity, at: sidecar))
    }

    func testRepairRewritesMissingSidecarAndRelaunches() async throws {
        let (model, frame) = try makeReadyModelWithDefectFrame()
        let sidecar = DefectSidecarFile.url(for: frame.id, in: defectDirectory)
        let previousRevision = frame.defectRecipeRevision
        try FileManager.default.removeItem(at: sidecar)
        XCTAssertFalse(model.saveLibrary(synchronous: true))
        XCTAssertEqual(lastCatalogSaveFailureCode(), "catalog_snapshot_invalid.defect_sidecar_mismatch")

        let repaired = await model.repairLibraryCatalogAndRelaunch()

        XCTAssertTrue(repaired)
        XCTAssertEqual(terminationRequests, 1)
        XCTAssertTrue(model.isRelaunchRequested)
        XCTAssertFalse(model.isLibraryMaintenanceInProgress)
        XCTAssertEqual(frame.defectEdits.count, 1)
        XCTAssertGreaterThan(frame.defectRecipeRevision, previousRevision)
        guard case .loaded(.currentV2(_, let stored)) = DefectSidecarFile.read(
            for: frame.id,
            in: defectDirectory
        ) else {
            return XCTFail("복구가 sidecar 를 다시 써야 합니다.")
        }
        XCTAssertEqual(stored.identity, frame.defectRecipeIdentity)
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        // 재실행은 정상 종료 경로(결함 기록 저장 → 카탈로그 커밋·검증)를 거친다. 그게 통과해야
        // 실제로 앱이 다시 열린다.
        let terminated = await terminate(model)
        XCTAssertTrue(terminated)
    }

    func testRepairClearsUnrecoverableRecipeAfterPreservingCurrentState() async throws {
        let (model, frame) = try makeReadyModelWithDefectFrame()
        let sidecar = DefectSidecarFile.url(for: frame.id, in: defectDirectory)
        try Data("not a sidecar".utf8).write(to: sidecar)
        frame.defectEdits = []
        frame.defectRecipeIdentity = nil
        frame.defectEditsNeedRestore = true
        XCTAssertFalse(model.saveLibrary(synchronous: true))
        XCTAssertEqual(lastCatalogSaveFailureCode(), "catalog_snapshot_invalid.defect_restore_pending")

        let repaired = await model.repairLibraryCatalogAndRelaunch()

        XCTAssertTrue(repaired)
        XCTAssertEqual(terminationRequests, 1)
        XCTAssertFalse(frame.defectEditsNeedRestore)
        XCTAssertTrue(frame.defectEdits.isEmpty)
        let rollbacks = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("RestoreRollbacks", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        let preservedSidecar = try XCTUnwrap(rollbacks.first)
            .appendingPathComponent("defects", isDirectory: true)
            .appendingPathComponent(sidecar.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: preservedSidecar), Data("not a sidecar".utf8))
        XCTAssertTrue(model.saveLibrary(synchronous: true))
    }

    func testRepairKeepsRecipeThatCannotBeReadYet() async throws {
        let (model, frame) = try makeReadyModelWithDefectFrame()
        let sidecar = DefectSidecarFile.url(for: frame.id, in: defectDirectory)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sidecar.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: sidecar.path
            )
        }
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: sidecar.path), "권한으로 읽기를 막을 수 없는 환경")
        frame.defectEdits = []
        frame.defectRecipeIdentity = nil
        frame.defectEditsNeedRestore = true

        let repaired = await model.repairLibraryCatalogAndRelaunch()

        XCTAssertFalse(repaired)
        XCTAssertEqual(terminationRequests, 0)
        XCTAssertFalse(model.isRelaunchRequested)
        XCTAssertTrue(frame.defectEditsNeedRestore)
        XCTAssertFalse(model.isLibraryMaintenanceInProgress)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))
    }

    func testReinstallSchedulesVerifiedRestoreThatNextLaunchApplies() async throws {
        let (model, frame) = try makeReadyModelWithDefectFrame()
        let editIDs = frame.defectEdits.map(\.id)
        try FileManager.default.removeItem(at: DefectSidecarFile.url(for: frame.id, in: defectDirectory))
        XCTAssertFalse(model.saveLibrary(synchronous: true))

        let reinstalled = await model.reinstallLibraryCatalogAndRelaunch()

        XCTAssertTrue(reinstalled)
        XCTAssertEqual(terminationRequests, 1)
        XCTAssertTrue(model.isRelaunchRequested)
        XCTAssertNotNil(model.libraryPendingRestoreMarker)
        XCTAssertNotNil(LibraryPendingRestoreStore.pendingMarker(for: catalogURL))
        // 기록이 사라진 사진이 있어 종료 커밋은 실패할 상태지만, 예약한 세대가 다음 실행에서
        // 카탈로그를 덮으므로 커밋 없이 바로 종료돼야 한다.
        let decision = model.beginApplicationTermination(
            scheduleCommit: { _, _, _, _, _ in XCTFail("재설치 뒤 종료는 커밋하지 않아야 합니다.") },
            completion: { _ in XCTFail("즉시 종료여야 합니다.") }
        )
        XCTAssertEqual(decision, .terminateNow)

        let relaunched = makeModel()
        await relaunched.restoreLibraryOnLaunch()
        defer {
            relaunched.libraryPersistenceEnabled = false
            relaunched.librarySaveTask?.cancel()
            relaunched.librarySaveTask = nil
        }

        XCTAssertEqual(relaunched.libraryLifecycleState, .ready)
        XCTAssertNil(LibraryPendingRestoreStore.pendingMarker(for: catalogURL))
        let restored = try XCTUnwrap(relaunched.frames.first { $0.id == frame.id })
        XCTAssertFalse(restored.defectEditsNeedRestore)
        XCTAssertEqual(restored.defectEdits.map(\.id), editIDs)
        XCTAssertTrue(relaunched.saveLibrary(synchronous: true))
    }

    func testMaintenanceDoesNothingWhileScanning() async throws {
        let (model, _) = try makeReadyModelWithDefectFrame()
        model.isScanning = true

        XCTAssertFalse(model.canRunLibraryCatalogMaintenance)
        let repaired = await model.repairLibraryCatalogAndRelaunch()
        let reinstalled = await model.reinstallLibraryCatalogAndRelaunch()

        XCTAssertFalse(repaired)
        XCTAssertFalse(reinstalled)
        XCTAssertEqual(terminationRequests, 0)
        XCTAssertFalse(model.isRelaunchRequested)
        XCTAssertNil(LibraryPendingRestoreStore.pendingMarker(for: catalogURL))
    }

    // MARK: - Helpers

    private var catalogURL: URL { root.appendingPathComponent("library.sqlite") }
    private var defectDirectory: URL { root.appendingPathComponent("defects", isDirectory: true) }

    private func makeModel() -> AppModel {
        let root = root
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defectDirectory,
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups", isDirectory: true)
        )
        model.requestTerminationForRelaunch = { [weak self] in self?.terminationRequests += 1 }
        return model
    }

    private func makeReadyModelWithDefectFrame() throws -> (AppModel, ScanFrame) {
        let model = makeModel()
        model.libraryPersistenceEnabled = false
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Maintenance",
            filmType: .colorNegative,
            activate: true
        ))
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/catalog-maintenance.tiff"),
            filmType: .colorNegative
        )
        frame.establishLibraryWorkflowBaselineIfNeeded()
        frame.defectEdits = [makeEdit()]
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame], toRollID: roll.id))
        _ = try XCTUnwrap(model.refreshDefectRecipeState(frame, advanceRevision: true, persist: true))
        DefectSidecarFile.flushSync()

        model.libraryPersistenceEnabled = true
        model.transitionLibraryLifecycle(to: .ready)
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        addTeardownBlock { @MainActor in
            model.libraryPersistenceEnabled = false
            model.librarySaveTask?.cancel()
            model.librarySaveTask = nil
        }
        return (model, frame)
    }

    private func terminate(_ model: AppModel) async -> Bool {
        await withCheckedContinuation { continuation in
            let decision = model.beginApplicationTermination { continuation.resume(returning: $0) }
            switch decision {
            case .terminateLater: break
            case .terminateNow: continuation.resume(returning: true)
            case .terminateCancel: continuation.resume(returning: false)
            }
        }
    }

    private func lastCatalogSaveFailureCode() -> String? {
        AppDiagnostics.recentEvents.last(where: {
            $0.operation == .catalogSave && $0.phase == .error
        })?.code
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
