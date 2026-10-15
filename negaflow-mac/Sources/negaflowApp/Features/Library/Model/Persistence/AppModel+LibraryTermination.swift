import AppKit
import Combine
import CoreImage
import Foundation
import Chromabase
import ScannerKit

extension AppModel {
    func beginApplicationTermination(
        completion: @escaping LibraryTerminationReply
    ) -> LibraryTerminationDecision {
        beginApplicationTermination(
            scheduleCommit: { catalog, _, catalogURL, defectDirectory, finished in
                let payload = LibraryCatalogCommitPayload(
                    catalog: catalog,
                    catalogURL: catalogURL,
                    defectDirectory: defectDirectory
                )
                Task.detached(priority: .utility) {
                    let result = LibraryCatalogFile.commitAndVerify(
                        payload.catalog,
                        to: payload.catalogURL,
                        defectDirectory: payload.defectDirectory,
                        catalogSafetyValidated: true
                    )
                    await finished(result)
                }
            },
            completion: completion
        )
    }

    /// 정상 종료 요청을 최신 catalog generation의 read-back 승인까지 보류한다.
    /// 먼저 결함 recipe를 저장하고, 그다음 catalog를 커밋한다.
    /// scheduler는 테스트에서 completion 순서와 실패를 결정적으로 주입하기 위한 seam이다.
    func beginApplicationTermination(
        scheduleCommit: @escaping LibraryTerminationCommitScheduler,
        completion: @escaping LibraryTerminationReply
    ) -> LibraryTerminationDecision {
        guard libraryPersistenceEnabled, libraryCatalogBlockReason == nil else {
            removeOwnedPreviewFilesForTermination()
            return .terminateNow
        }
        // 재설치가 다음 실행에 적용할 세대를 이미 예약했다. 지금 커밋해도 그 세대가 통째로
        // 덮으므로 건너뛴다 — 여기서 커밋이 실패해 재설치의 재실행이 막히지 않게 한다.
        if isLibraryReinstallPendingRelaunch {
            librarySaveTask?.cancel()
            librarySaveTask = nil
            removeOwnedPreviewFilesForTermination()
            return .terminateNow
        }
        guard !isLibraryTerminationSaveInProgress else { return .terminateLater }
        isLibraryTerminationSaveInProgress = true
        // 저장이 확인되지 않은 결함 편집이 없으면 바로 커밋한다. 있으면 먼저 비동기로 그 recipe만
        // 저장하고 커밋한다 — 실패 시 종료를 취소해 적용된 편집을 지킵니다.
        let needsBake = frames.contains {
            !$0.isPreviewScan && !$0.defectEdits.isEmpty && !isDefectRecipeCommitted($0)
        }
        guard needsBake else {
            guard startLibraryTerminationCommit(
                scheduleCommit: scheduleCommit,
                completion: completion
            ) else {
                isLibraryTerminationSaveInProgress = false
                libraryTerminationAttemptGeneration = nil
                return .terminateCancel
            }
            return .terminateLater
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.bakeDefectEditsForTermination() else {
                self.isLibraryTerminationSaveInProgress = false
                self.libraryTerminationAttemptGeneration = nil
                self.statusMessage = self.text(AppLocalizedPhrase.librarySaveFailed)
                completion(false)
                return
            }
            guard self.startLibraryTerminationCommit(
                scheduleCommit: scheduleCommit,
                completion: completion
            ) else {
                self.isLibraryTerminationSaveInProgress = false
                self.libraryTerminationAttemptGeneration = nil
                completion(false)
                return
            }
        }
        return .terminateLater
    }

    private func startLibraryTerminationCommit(
        scheduleCommit: @escaping LibraryTerminationCommitScheduler,
        completion: @escaping LibraryTerminationReply
    ) -> Bool {
        guard let prepared = prepareLibraryTerminationCommit() else { return false }
        libraryTerminationAttemptGeneration = prepared.generation
        scheduleCommit(
            prepared.catalog,
            prepared.generation,
            libraryCatalogURL,
            libraryDefectDirectoryURL
        ) { [weak self] result in
            guard let self else { return }
            self.finishLibraryTerminationCommit(
                result,
                catalog: prepared.catalog,
                generation: prepared.generation,
                scheduleCommit: scheduleCommit,
                completion: completion
            )
        }
        return true
    }

    private func finishLibraryTerminationCommit(
        _ result: Result<Void, LibraryCatalogCommitError>,
        catalog: LibraryCatalog,
        generation: UInt64,
        scheduleCommit: @escaping LibraryTerminationCommitScheduler,
        completion: @escaping LibraryTerminationReply
    ) {
        guard isLibraryTerminationSaveInProgress,
              libraryTerminationAttemptGeneration == generation else { return }
        switch result {
        case .success:
            recordLibraryCatalogWriteResult(generation: generation, succeeded: true)
            if libraryCatalogDirtyGeneration > generation,
               terminationCatalogStillMatches(catalog) {
                // 커밋하는 동안 썸네일 같은 화면 값만 바뀌어도 사진 변경 표시가 올라간다. 카탈로그
                // 내용이 방금 승인된 것과 같으면 디스크가 이미 지금 상태다 — 다시 커밋하지 않는다.
                // 실행 직후 썸네일이 들어오는 동안 종료하면 이 표시를 쫓아 수백 번 재커밋했다.
                librarySaveTask?.cancel()
                librarySaveTask = nil
                recordLibraryCatalogWriteResult(
                    generation: libraryCatalogDirtyGeneration,
                    succeeded: true
                )
            }
            if libraryCatalogDirtyGeneration > generation, hasUnsavedLibraryChanges {
                guard startLibraryTerminationCommit(
                    scheduleCommit: scheduleCommit,
                    completion: completion
                ) else {
                    isLibraryTerminationSaveInProgress = false
                    libraryTerminationAttemptGeneration = nil
                    completion(false)
                    return
                }
                return
            }
            isLibraryTerminationSaveInProgress = false
            libraryTerminationAttemptGeneration = nil
            // 백업은 종료를 기다리게 하지 않는다. 자동 백업은 실행 중에 이미 백그라운드로 돈다.
            removeOwnedPreviewFilesForTermination()
            completion(true)
        case .failure:
            librarySaveTask?.cancel()
            librarySaveTask = nil
            recordLibraryCatalogWriteResult(generation: generation, succeeded: false)
            statusMessage = text(AppLocalizedPhrase.librarySaveFailed)
            isLibraryTerminationSaveInProgress = false
            libraryTerminationAttemptGeneration = nil
            completion(false)
        }
    }

    /// 종료 커밋을 다시 준비할 때와 같은 조건(진행 중 트랜잭션 없음, 롤 소속 일치, 결함 기록 확정)에서
    /// 지금 카탈로그가 방금 커밋한 값과 같은지 본다. 조건이 하나라도 어긋나면 다시 커밋하는 원래 길로 간다.
    private func terminationCatalogStillMatches(_ committed: LibraryCatalog) -> Bool {
        let persistentFrames = frames.filter { !$0.isPreviewScan }
        guard !isAcknowledgedLibraryTransactionActive,
              rollStore.hasExactMembership(for: persistentFrames.map(\.id)),
              persistentFrames.allSatisfy({ $0.defectEdits.isEmpty || isDefectRecipeCommitted($0) }),
              let current = currentLibraryCatalogSnapshot() else { return false }
        return LibraryCatalogFile.hasSameContent(current, committed)
    }

    private func prepareLibraryTerminationCommit() -> (
        catalog: LibraryCatalog,
        generation: UInt64
    )? {
        librarySaveTask?.cancel()
        librarySaveTask = nil
        let persistentFrameIDs = frames.lazy.filter { !$0.isPreviewScan }.map(\.id)
        guard !isAcknowledgedLibraryTransactionActive,
              rollStore.hasExactMembership(for: Array(persistentFrameIDs)) else {
            recordLibraryCatalogWriteResult(
                generation: markLibraryCatalogDirty(),
                succeeded: false
            )
            statusMessage = text(AppLocalizedPhrase.librarySaveFailed)
            return nil
        }
        for frame in frames where !frame.isPreviewScan && !frame.defectEdits.isEmpty
            && !isDefectRecipeCommitted(frame) {
            guard refreshDefectRecipeState(frame, advanceRevision: false, persist: true) != nil else {
                return nil
            }
        }
        // recipe 저장이 예약한 지연 저장은 종료 커밋과 같은 catalog를 두고 경쟁한다.
        librarySaveTask?.cancel()
        librarySaveTask = nil
        // 별도 approval generation을 써서 앞서 enqueue된 일반 write completion이 종료
        // read-back 실패를 성공 상태로 덮지 못하게 한다. recipe 저장이 스스로 catalog를
        // dirty로 올리므로 그 뒤에 확정한다 — 먼저 잡으면 종료 커밋이 자기가 만든 dirty를
        // 사용자 변경으로 보고 끝없이 재커밋한다.
        let generation = markLibraryCatalogDirty()
        guard let catalog = currentLibraryCatalogSnapshot() else {
            recordLibraryCatalogWriteResult(generation: generation, succeeded: false)
            statusMessage = text(AppLocalizedPhrase.librarySaveFailed)
            return nil
        }
        return (catalog, generation)
    }

    /// 기존 내부 호출과 회귀 테스트를 위한 동기 helper. 실제 앱 종료는 AppKit의
    /// `terminateLater` 경로를 사용한다.
    @discardableResult
    func saveLibraryOnTerminate() -> Bool {
        guard libraryPersistenceEnabled, libraryCatalogBlockReason == nil,
              let prepared = prepareLibraryTerminationCommit() else { return false }
        let result = LibraryCatalogFile.commitAndVerify(
            prepared.catalog,
            to: libraryCatalogURL,
            defectDirectory: libraryDefectDirectoryURL,
            catalogSafetyValidated: true
        )
        switch result {
        case .success:
            recordLibraryCatalogWriteResult(
                generation: prepared.generation,
                succeeded: true
            )
            _ = try? LibraryBackupStore.createSnapshot(
                catalogURL: libraryCatalogURL,
                defectDirectory: libraryDefectDirectoryURL,
                backupDirectory: libraryBackupDirectoryURL
            )
            removeOwnedPreviewFilesForTermination()
            return true
        case .failure:
            recordLibraryCatalogWriteResult(
                generation: prepared.generation,
                succeeded: false
            )
            statusMessage = text(AppLocalizedPhrase.librarySaveFailed)
            return false
        }
    }

    private func removeOwnedPreviewFilesForTermination() {
        for frame in frames where frame.isPreviewScan {
            Self.removeOwnedPreviewFile(at: frame.rawScanURL)
        }
    }

    var hasUncommittedDefectGesture: Bool {
        frames.contains { $0.defectGestureRecipeAdvanced }
    }


}
