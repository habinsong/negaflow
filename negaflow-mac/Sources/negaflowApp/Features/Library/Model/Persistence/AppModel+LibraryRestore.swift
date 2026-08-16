import AppKit
import Combine
import CoreImage
import Foundation
import Chromabase
import ScannerKit

typealias LibraryTerminationCommitCompletion = @MainActor @Sendable (
    Result<Void, LibraryCatalogCommitError>
) -> Void

typealias LibraryTerminationCommitScheduler = @MainActor (
    LibraryCatalog,
    UInt64,
    URL,
    URL,
    @escaping LibraryTerminationCommitCompletion
) -> Void

typealias LibraryTerminationReply = @MainActor (Bool) -> Void

extension AppModel {

    // MARK: - 라이브러리 영속화 (카탈로그 방식)
    //
    // 프레임 메타데이터(원본 경로 + 현상 파라미터/변형/별점 등)는 Application Support 의
    // library.sqlite 에, 썸네일은 디스크 캐시(설정의 썸네일 폴더)에 저장한다. RAM FIFO 는 그대로 —
    // 디스크는 재시작 후 복원과 대량 라이브러리의 백킹만 담당한다.

    /// 다음 프레임 번호. 복원/삭제 후에도 겹치지 않도록 count 대신 max+1 을 쓴다.
    var nextScanIndex: Int {
        (frames.filter { !$0.isPreviewScan }.map(\.scanIndex).max() ?? 0) + 1
    }

    // MARK: 복원

    /// 앱 시작 시 1회: 카탈로그를 읽어 프레임을 복원하고, 이후의 변경 저장을 켠다.
    /// 원본 파일이 사라져도 레코드와 썸네일을 보존한다. 사용자는 Offline 필터에서 원본 또는
    /// 폴더를 명시적으로 다시 연결할 수 있다.
    func restoreLibraryOnLaunch() async {
        await restoreLibraryOnLaunch(reusingHeldProcessLock: false)
    }

    func restoreLibraryOnLaunch(
        reusingHeldProcessLock: Bool,
        exportJournalDirectory: URL = ExportArtifactCommitJournal.defaultDirectoryURL()
    ) async {
        guard !didRestoreLibrary else { return }
        let trace = AppDiagnostics.start(.catalogRestore, category: .catalog)
        defer { trace.finish() }
        didRestoreLibrary = true
        // 카탈로그를 다시 읽기 전에는 이전 membership 판정으로 삭제를 허용하지 않는다.
        ambiguousExportCommitTransactionIDs.removeAll()
        transitionLibraryLifecycle(to: .restoring)
        if reusingHeldProcessLock {
            guard libraryProcessLock != nil else {
                libraryCatalogBlockReason = .lockUnavailable
                libraryPersistenceEnabled = false
                transitionLibraryLifecycle(to: .blocked)
                statusMessage = libraryCatalogBlockMessage(.lockUnavailable)
                trace.fail(code: "process_lock_missing")
                return
            }
        } else {
            do {
                libraryProcessLock = try LibraryProcessLock.acquire(for: libraryCatalogURL)
            } catch LibraryProcessLockError.alreadyLocked {
                libraryCatalogBlockReason = .lockedByAnotherProcess
                libraryPersistenceEnabled = false
                transitionLibraryLifecycle(to: .blocked)
                statusMessage = libraryCatalogBlockMessage(.lockedByAnotherProcess)
                trace.fail(code: "catalog_already_locked")
                return
            } catch {
                libraryCatalogBlockReason = .lockUnavailable
                libraryPersistenceEnabled = false
                transitionLibraryLifecycle(to: .blocked)
                statusMessage = libraryCatalogBlockMessage(.lockUnavailable)
                trace.fail(error)
                return
            }
        }
        ensureStorageFolders()
        let url = libraryCatalogURL
        let defectDirectory = libraryDefectDirectoryURL
        let backupDirectory = libraryBackupDirectoryURL
        let startupResult = await Task.detached(priority: .userInitiated) {
            do {
                let pending = try LibraryPendingRestoreStore.applyIfScheduled(
                    catalogURL: url,
                    defectDirectory: defectDirectory,
                    backupDirectory: backupDirectory
                )
                let open = LibraryCatalogFile.prepareForUse(
                    at: url,
                    defectDirectory: defectDirectory,
                    backupDirectory: backupDirectory
                )
                let exportReconciliation: ExportArtifactCommitReconciliationReport
                switch open {
                case .newLibrary:
                    exportReconciliation = ExportArtifactCommitJournal.reconcile(
                        committedTransactionIDs: [],
                        in: exportJournalDirectory
                    )
                case .loaded(let catalog, _, _):
                    let committedTransactionIDs = Set(catalog.frames.flatMap { record in
                        record.exportTracking.successfulEvents.map(\.id)
                    })
                    exportReconciliation = ExportArtifactCommitJournal.reconcile(
                        committedTransactionIDs: committedTransactionIDs,
                        in: exportJournalDirectory
                    )
                case .blocked:
                    // Catalog 진실을 읽지 못하면 committed 여부를 추측해 산출물을 지우지 않는다.
                    exportReconciliation = ExportArtifactCommitReconciliationReport()
                }
                return (open, pending.didApplyRestore, exportReconciliation)
            } catch {
                return (
                    LibraryCatalogOpenResult.blocked(.pendingRestoreFailed),
                    false,
                    ExportArtifactCommitReconciliationReport()
                )
            }
        }.value
        let openResult = startupResult.0
        let appliedPendingRestore = startupResult.1
        let exportReconciliation = startupResult.2
        libraryPendingRestoreMarker = LibraryPendingRestoreStore.pendingMarker(for: url)
        if case .blocked = openResult {
            // Catalog 진실을 읽지 못한 상태에서는 keep-only 복구만 유지한다.
        } else {
            preserveAmbiguousExportCommitTransactions(from: exportReconciliation)
        }

        if blockLibraryForInconsistentExportReconciliation(exportReconciliation) {
            trace.fail(code: "export_reconciliation_unresolved")
            return
        }

        let catalog: LibraryCatalog
        let recoveredFromBackup: Bool
        let migratedFromVersion: Int?
        switch openResult {
        case .newLibrary:
            libraryCatalogBlockReason = nil
            libraryPersistenceEnabled = true
            transitionLibraryLifecycle(to: .ready)
            restoreExportBatchCheckpoint()
            trace.finish()
            return
        case let .blocked(reason):
            librarySaveTask?.cancel()
            librarySaveTask = nil
            libraryCatalogBlockReason = reason
            libraryPersistenceEnabled = false
            transitionLibraryLifecycle(to: .blocked)
            statusMessage = libraryCatalogBlockMessage(reason)
            trace.fail(code: "catalog_open_blocked_\(String(describing: reason))")
            return
        case let .loaded(loaded, recovered, migrated):
            catalog = loaded
            recoveredFromBackup = recovered
            migratedFromVersion = migrated
            libraryCatalogBlockReason = nil
        }

        // 유효한 primary 또는 backup catalog를 읽었을 때만 orphan 정리를 허용한다. 손상/권한
        // 오류를 빈 catalog로 간주하면 복구 가능한 app-owned 데이터를 전부 지우게 된다.
        await sweepDefectStorageOrphans(
            catalog: catalog,
            defectDirectory: defectDirectory,
            cleanedRawDirectory: diskStorage.cleanedRawURL
        )

        for path in catalog.folders {
            let folderURL = URL(fileURLWithPath: path, isDirectory: true)
            // 외장 디스크나 iCloud가 일시적으로 offline이어도 catalog reference를 보존한다.
            registerLibraryFolder(folderURL)
        }
        replaceRollState(with: RollStoreSnapshot(
            rolls: catalog.rolls,
            activeRollID: catalog.activeRollID
        ))
        stackStore.replace(with: catalog.stacks)
        scanSessions = catalog.scanSessions
        scanRollAssignments = catalog.scanRollAssignments
        replaceLibraryOrganizerState(
            manualCollections: catalog.manualCollections,
            smartCollections: catalog.smartCollections,
            savedSearches: catalog.savedSearches
        )
        // 실행 중 차단을 해제해 다시 여는 경우에는 현재 persistent frame을 catalog 진실과
        // 합치지 않는다. 동일 UUID의 이전 객체/observation을 남기면 tracking 상태가 갈라진다.
        let transientPreviewFrames = frames.filter(\.isPreviewScan)
        frameObservations.removeAll()
        frameQueryObservations.removeAll()
        libraryFrameRecordCache.removeAll()
        dirtyLibraryFrameRecordIDs.removeAll()
        var restored: [ScanFrame] = []
        for record in catalog.frames {
            let frame = record.makeFrame(presets: presets)
            libraryFrameRecordCache[record.id] = record
            // 결함 기록/캐시 필드는 더 이상 복원하지 않는다(기록은 세션 종료 시 이미지에
            // 구워진다). 남아 있는 legacy 필드는 다음 저장에서 nil로 재기록되도록 dirty 처리.
            if frame.rawScanURL.path != record.rawScanPath
                || frame.infraredScanURL?.path != record.infraredScanPath
                || frame.rawScanBookmarkData != record.rawScanBookmarkData
                || frame.infraredScanBookmarkData != record.infraredScanBookmarkData
                || frame.preset?.id != record.presetID
                || record.cleanedRawPath != nil
                || record.cleanedRawEditCount != nil
                || record.hasDefectEdits != nil {
                dirtyLibraryFrameRecordIDs.insert(record.id)
            }
            restored.append(frame)
        }
        libraryPersistenceEnabled = true
        frames = restored + transientPreviewFrames
        // 다시 켜면 마지막으로 작업하던 사진으로 돌아간다. 그 사진이 카탈로그에서 사라졌거나
        // 원본을 열 수 없으면 값을 버리고 기존 규칙(가장 최근 사진)에 맡긴다.
        restoredLastActiveFrameID = catalog.lastActiveFrameID.flatMap { id in
            restored.contains { $0.id == id } ? id : nil
        }
        guard !restored.isEmpty else {
            transitionLibraryLifecycle(to: .ready)
            _ = await reconcilePersistedScanWorkflowAfterRestore()
            restoreExportBatchCheckpoint()
            return
        }
        if appliedPendingRestore {
            statusMessage = text(
                AppLocalizedPhrase.librarySelectedBackupAppliedFormat,
                restored.count
            )
        } else if recoveredFromBackup {
            statusMessage = text(AppLocalizedPhrase.libraryRecoveredFromBackupFormat, restored.count)
        } else if let migratedFromVersion {
            statusMessage = text(
                AppLocalizedPhrase.libraryCatalogMigratedFormat,
                migratedFromVersion,
                restored.count
            )
        } else {
            statusMessage = text(AppLocalizedPhrase.libraryRestoredFormat, restored.count)
        }
        loadThumbnailsFromDisk(for: restored)
        transitionLibraryLifecycle(to: .ready)
        _ = await reconcilePersistedScanWorkflowAfterRestore()
        restoreExportBatchCheckpoint()
    }

    func libraryCatalogBlockMessage(_ reason: LibraryCatalogOpenFailure) -> String {
        switch reason {
        case .lockedByAnotherProcess:
            text(AppLocalizedPhrase.libraryCatalogLockedStatus)
        case .lockUnavailable:
            text(AppLocalizedPhrase.libraryCatalogLockUnavailableStatus)
        case let .unsupportedVersion(version):
            text(AppLocalizedPhrase.libraryCatalogNewerVersionFormat, version)
        case let .unsupportedStorageVersion(version):
            text(AppLocalizedPhrase.libraryCatalogNewerVersionFormat, version)
        case .missingAuthoritativeData:
            text(AppLocalizedPhrase.libraryCatalogMissingAuthoritativeDataStatus)
        case .pendingRestoreFailed:
            text(AppLocalizedPhrase.libraryPendingRestoreFailedStatus)
        case .unreadable, .corrupt, .writeFailed:
            text(AppLocalizedPhrase.libraryCatalogBlockedStatus)
        }
    }

    func libraryBackupGenerations() async throws -> [LibraryBackupGeneration] {
        let directory = libraryBackupDirectoryURL
        return try await Task.detached(priority: .utility) {
            try LibraryBackupStore.generations(in: directory)
        }.value
    }

    @discardableResult
    func scheduleLibraryRestore(generationID: String) async throws -> LibraryPendingRestoreMarker {
        guard !isLibraryMaintenanceInProgress else {
            throw LibraryPendingRestoreError.applyFailed
        }
        isLibraryMaintenanceInProgress = true
        defer { isLibraryMaintenanceInProgress = false }
        let catalogURL = libraryCatalogURL
        let backupDirectory = libraryBackupDirectoryURL
        let marker = try await Task.detached(priority: .utility) {
            try LibraryPendingRestoreStore.schedule(
                generationID: generationID,
                catalogURL: catalogURL,
                backupDirectory: backupDirectory
            )
        }.value
        libraryPendingRestoreMarker = marker
        return marker
    }

    func cancelScheduledLibraryRestore() async throws {
        guard !isLibraryMaintenanceInProgress else {
            throw LibraryPendingRestoreError.applyFailed
        }
        isLibraryMaintenanceInProgress = true
        defer { isLibraryMaintenanceInProgress = false }
        let catalogURL = libraryCatalogURL
        try await Task.detached(priority: .utility) {
            try LibraryPendingRestoreStore.cancel(catalogURL: catalogURL)
        }.value
        libraryPendingRestoreMarker = nil
    }

    func refreshScheduledLibraryRestore() async {
        let catalogURL = libraryCatalogURL
        libraryPendingRestoreMarker = await Task.detached(priority: .utility) {
            LibraryPendingRestoreStore.pendingMarker(for: catalogURL)
        }.value
    }


}
