import AppKit
import Combine
import CoreImage
import Foundation
import Chromabase
import ScannerKit

extension AppModel {
    func frameListDidChange(_ currentFrames: [ScanFrame]) {
        let currentFrameIDs = Set(currentFrames.map(\.id))
        libraryFrameRecordCache = libraryFrameRecordCache.filter {
            currentFrameIDs.contains($0.key)
        }
        dirtyLibraryFrameRecordIDs.formIntersection(currentFrameIDs)
        for frame in currentFrames where libraryFrameRecordCache[frame.id] == nil {
            dirtyLibraryFrameRecordIDs.insert(frame.id)
        }
        var observations: [UUID: AnyCancellable] = [:]
        for frame in currentFrames {
            observations[frame.id] = frameObservations[frame.id] ?? observeFrameChanges(frame)
        }
        frameObservations = observations
        exportAvailabilityStore.observe(currentFrames)
        refreshLibraryFrameQueryObservations(currentFrames)
        updateLibraryFileSystemMonitoring()
        scheduleLibrarySave()
    }

    private func observeFrameChanges(_ frame: ScanFrame) -> AnyCancellable {
        let frameID = frame.id
        return frame.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.dirtyLibraryFrameRecordIDs.insert(frameID)
                self.scheduleLibrarySave()
            }
        }
    }

    /// 호출자가 준비한 한 generation의 catalog 값을 만든다. 실제 저장 경로의 sidecar까지
    /// 포함한 health 검사는 snapshot/commit 단계에서 수행한다.
    func makeLibraryCatalogValue(
        frames snapshotFrames: [ScanFrame],
        rolls snapshotRolls: [LibraryRoll],
        activeRollID snapshotActiveRollID: UUID?,
        scanSessions snapshotScanSessions: [ScanSession],
        scanRollAssignments snapshotAssignments: [LibraryScanRollAssignment],
        manualCollections snapshotManualCollections: [LibraryManualCollection]? = nil
    ) -> LibraryCatalog {
        let persistentFrames = snapshotFrames.filter { !$0.isPreviewScan }
        let frameRecords = persistentFrames.map { frame in
            if !dirtyLibraryFrameRecordIDs.contains(frame.id),
               let cached = libraryFrameRecordCache[frame.id] {
                return cached
            }
            let record = LibraryFrameRecord(frame: frame)
            libraryFrameRecordCache[frame.id] = record
            dirtyLibraryFrameRecordIDs.remove(frame.id)
            return record
        }
        return LibraryCatalog(
            folders: libraryFolders.map { $0.url.path },
            frames: frameRecords,
            rolls: snapshotRolls,
            activeRollID: snapshotActiveRollID,
            scanSessions: snapshotScanSessions,
            scanRollAssignments: snapshotAssignments,
            manualCollections: snapshotManualCollections ?? manualCollections,
            smartCollections: smartCollections,
            savedSearches: savedSearches,
            stacks: stacks
        )
    }

    /// 호출자가 준비한 한 generation을 health 검사까지 마친 catalog 값으로 만든다.
    /// 스캔 transaction은 이 값을 acknowledged commit한 뒤에만 대응 MainActor 상태를 publish한다.
    func makeLibraryCatalogSnapshot(
        frames snapshotFrames: [ScanFrame],
        rolls snapshotRolls: [LibraryRoll],
        activeRollID snapshotActiveRollID: UUID?,
        scanSessions snapshotScanSessions: [ScanSession],
        scanRollAssignments snapshotAssignments: [LibraryScanRollAssignment],
        manualCollections snapshotManualCollections: [LibraryManualCollection]? = nil
    ) -> LibraryCatalog? {
        guard defectSidecarsMatchCurrentFrames(snapshotFrames) else { return nil }
        let catalog = makeLibraryCatalogValue(
            frames: snapshotFrames,
            rolls: snapshotRolls,
            activeRollID: snapshotActiveRollID,
            scanSessions: snapshotScanSessions,
            scanRollAssignments: snapshotAssignments,
            manualCollections: snapshotManualCollections
        )
        let health = LibraryCatalogHealthInspector.inspect(
            catalog,
            defectDirectory: libraryDefectDirectoryURL,
            cleanedRawDirectory: diskStorage.cleanedRawURL,
            includeWarnings: false,
            validatedPreviousCatalog: LibraryCatalogSQLiteWriteCache.shared
                .safetyValidatedCatalog(for: libraryCatalogURL)
        )
        return health.canOpenSafely ? catalog : nil
    }

    func currentLibraryCatalogSnapshot() -> LibraryCatalog? {
        guard !hasUncommittedDefectGesture else { return nil }
        let persistentFrames = frames.filter { !$0.isPreviewScan }
        guard rollStore.hasExactMembership(for: persistentFrames.map(\.id)) else {
            return nil
        }
        return makeLibraryCatalogSnapshot(
            frames: persistentFrames,
            rolls: rolls,
            activeRollID: activeRollID,
            scanSessions: scanSessions,
            scanRollAssignments: scanRollAssignments
        )
    }

    @discardableResult
    func beginAcknowledgedLibraryTransaction() -> Bool {
        guard libraryPersistenceEnabled,
              libraryCatalogBlockReason == nil,
              libraryLifecycleState == .ready,
              !isLibraryMaintenanceInProgress,
              !hasUncommittedDefectGesture,
              !isAcknowledgedLibraryTransactionActive else {
            return false
        }
        librarySaveTask?.cancel()
        librarySaveTask = nil
        isAcknowledgedLibraryTransactionActive = true
        librarySaveRequestedDuringTransaction = false
        return true
    }

    func commitAcknowledgedLibrarySnapshot(
        frames snapshotFrames: [ScanFrame],
        rolls snapshotRolls: [LibraryRoll],
        activeRollID snapshotActiveRollID: UUID?,
        scanSessions snapshotScanSessions: [ScanSession],
        scanRollAssignments snapshotAssignments: [LibraryScanRollAssignment],
        manualCollections snapshotManualCollections: [LibraryManualCollection]? = nil
    ) -> Result<Void, LibraryCatalogCommitError> {
        guard isAcknowledgedLibraryTransactionActive else {
            return .failure(.invalidCatalog)
        }
        guard let catalog = makeLibraryCatalogSnapshot(
            frames: snapshotFrames,
            rolls: snapshotRolls,
            activeRollID: snapshotActiveRollID,
            scanSessions: snapshotScanSessions,
            scanRollAssignments: snapshotAssignments,
            manualCollections: snapshotManualCollections
        ) else {
            return .failure(.invalidCatalog)
        }
        let generation = libraryCatalogDirtyGeneration
        let result = LibraryCatalogFile.commitAndVerify(
            catalog,
            to: libraryCatalogURL,
            defectDirectory: libraryDefectDirectoryURL,
            catalogSafetyValidated: true
        )
        if case .success = result {
            recordLibraryCatalogWriteResult(generation: generation, succeeded: true)
        }
        return result
    }

    /// acknowledged commit의 catalog와 현재 MainActor 상태가 동일해진 직후 호출한다.
    /// transaction 안에서 발생한 publisher 기반 dirty generation을 같은 read-back commit으로
    /// 승인해 불필요한 두 번째 저장과 일시적인 unsaved 표시를 남기지 않는다.
    func acknowledgeCurrentLibraryStateMatchesCommittedSnapshot() {
        guard isAcknowledgedLibraryTransactionActive else { return }
        recordLibraryCatalogWriteResult(
            generation: libraryCatalogDirtyGeneration,
            succeeded: true
        )
        librarySaveRequestedDuringTransaction = false
    }

    func endAcknowledgedLibraryTransaction() {
        guard isAcknowledgedLibraryTransactionActive else { return }
        isAcknowledgedLibraryTransactionActive = false
        let shouldSaveLatest = librarySaveRequestedDuringTransaction
        librarySaveRequestedDuringTransaction = false
        if shouldSaveLatest { scheduleLibrarySave(markDirty: false) }
    }

    /// 트레일링 디바운스 저장. 창 안의 반복 변경(슬라이더 등)은 창 끝의 1회 저장으로 흡수된다
    /// (저장 시점의 최신 상태를 읽으므로 재예약이 필요 없다).

}
