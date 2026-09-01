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
    /// 먼저 결함 편집을 이미지에 굽고(기록 폐기), 그다음 catalog를 커밋한다.
    /// scheduler는 테스트에서 completion 순서와 실패를 결정적으로 주입하기 위한 seam이다.
    func beginApplicationTermination(
        scheduleCommit: @escaping LibraryTerminationCommitScheduler,
        completion: @escaping LibraryTerminationReply
    ) -> LibraryTerminationDecision {
        guard libraryPersistenceEnabled, libraryCatalogBlockReason == nil else {
            removeOwnedPreviewFilesForTermination()
            return .terminateNow
        }
        guard !isLibraryTerminationSaveInProgress else { return .terminateLater }
        isLibraryTerminationSaveInProgress = true
        // 결함 편집이 없으면 기존 동기 커밋 경로를 그대로 쓴다. 편집이 있으면 먼저 비동기로
        // 이미지에 굽고(기록 폐기) 커밋한다 — 실패 시 종료를 취소해 적용된 편집을 지키게 한다.
        let needsBake = frames.contains { !$0.isPreviewScan && !$0.defectEdits.isEmpty }
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
                self.statusMessage = self.libraryCatalogBlockMessage(.writeFailed)
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
                generation: prepared.generation,
                scheduleCommit: scheduleCommit,
                completion: completion
            )
        }
        return true
    }

    private func finishLibraryTerminationCommit(
        _ result: Result<Void, LibraryCatalogCommitError>,
        generation: UInt64,
        scheduleCommit: @escaping LibraryTerminationCommitScheduler,
        completion: @escaping LibraryTerminationReply
    ) {
        guard isLibraryTerminationSaveInProgress,
              libraryTerminationAttemptGeneration == generation else { return }
        switch result {
        case .success:
            recordLibraryCatalogWriteResult(generation: generation, succeeded: true)
            if libraryCatalogDirtyGeneration > generation {
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
            if backupScheduleStore.schedule == .onTermination {
                Task { [weak self] in
                    guard let self else { return }
                    // 카탈로그 커밋은 이미 승인됐다. 백업은 덤이라, 실패했다고 종료를 막으면
                    // 사용자는 앱을 끌 수 없게 된다 — 실패는 알리고 종료는 진행한다.
                    _ = await self.createLibraryBackupNow()
                    self.removeOwnedPreviewFilesForTermination()
                    completion(true)
                }
                return
            }
            removeOwnedPreviewFilesForTermination()
            completion(true)
        case .failure:
            librarySaveTask?.cancel()
            librarySaveTask = nil
            recordLibraryCatalogWriteResult(generation: generation, succeeded: false)
            statusMessage = libraryCatalogBlockMessage(.writeFailed)
            isLibraryTerminationSaveInProgress = false
            libraryTerminationAttemptGeneration = nil
            completion(false)
        }
    }

    private func prepareLibraryTerminationCommit() -> (
        catalog: LibraryCatalog,
        generation: UInt64
    )? {
        librarySaveTask?.cancel()
        librarySaveTask = nil
        // 별도 approval generation을 써서 앞서 enqueue된 일반 write completion이 종료
        // read-back 실패를 성공 상태로 덮지 못하게 한다.
        let generation = markLibraryCatalogDirty()
        let persistentFrameIDs = frames.lazy.filter { !$0.isPreviewScan }.map(\.id)
        guard !isAcknowledgedLibraryTransactionActive,
              rollStore.hasExactMembership(for: Array(persistentFrameIDs)) else {
            recordLibraryCatalogWriteResult(generation: generation, succeeded: false)
            statusMessage = libraryCatalogBlockMessage(.writeFailed)
            return nil
        }
        for frame in frames where frame.defectGestureRecipeAdvanced {
            cancelPendingDefectRecipeRefresh(frame)
            frame.defectGestureRecipeAdvanced = false
            frame.defectGestureUndoPushed = false
            frame.defectGestureSourceIdentity = nil
        }
        guard let catalog = currentLibraryCatalogSnapshot() else {
            recordLibraryCatalogWriteResult(generation: generation, succeeded: false)
            statusMessage = libraryCatalogBlockMessage(.writeFailed)
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
            statusMessage = libraryCatalogBlockMessage(.writeFailed)
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
