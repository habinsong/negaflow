import Foundation

/// 진단 패널의 카탈로그 수동 복구/재설치. 둘 다 끝나면 앱을 다시 실행한다 — 다시 여는 쪽이
/// 카탈로그를 처음부터 읽고, 열 때의 정합성 수리와 결함 기록 복원을 새로 돌린다.
extension AppModel {
    /// 스캔·내보내기 도중에 재실행하면 진행 중인 작업이 끊기므로 막는다.
    var canRunLibraryCatalogMaintenance: Bool {
        libraryLifecycleState == .ready
            && libraryPersistenceEnabled
            && libraryCatalogBlockReason == nil
            && !isLibraryMaintenanceInProgress
            && !isLibraryTerminationSaveInProgress
            && !isAcknowledgedLibraryTransactionActive
            && !isScanning
            && !isScanFinalizationInProgress
            && !exportBatchStore.isRunning
            && !isPrintPackageExporting
    }

    /// 수동 복구. 카탈로그 파일은 그대로 두고, 결함 기록을 메모리 기준으로 다시 확정해
    /// 카탈로그 저장을 막던 불일치(`catalog_snapshot_invalid.defect_*`)를 푼 뒤 저장하고 재실행한다.
    @discardableResult
    func repairLibraryCatalogAndRelaunch() async -> Bool {
        guard beginLibraryCatalogMaintenance() else { return false }
        guard await settleDefectRecipesForCatalogMaintenance(),
              await rewriteMismatchedDefectRecipes(),
              defectSidecarValidationFailure(frames) == nil,
              saveLibrary(synchronous: true) else {
            return failLibraryCatalogMaintenance(AppLocalizedPhrase.libraryCatalogRepairFailedStatus)
        }
        relaunchAfterLibraryCatalogMaintenance()
        return true
    }

    /// 재설치. 지금 라이브러리로 검증된 백업 세대를 만들고, 다음 실행 때 그 세대로 카탈로그와
    /// 결함 폴더를 통째로 새로 깐다. 적용 직전의 기존 파일은 예약 복원과 같은 경로로 따로 보관된다.
    /// 예약한 세대가 다음 실행에서 카탈로그를 덮으므로 이번 종료 커밋은 건너뛴다.
    @discardableResult
    func reinstallLibraryCatalogAndRelaunch() async -> Bool {
        guard beginLibraryCatalogMaintenance() else { return false }
        guard await settleDefectRecipesForCatalogMaintenance(),
              let payload = await makeManualBackupPayload(),
              let backup = await createManualBackupSnapshot(
                  payload,
                  backupDirectory: libraryBackupDirectoryURL,
                  verificationDate: Date()
              ),
              backup.drill.succeeded else {
            return failLibraryCatalogMaintenance(AppLocalizedPhrase.libraryCatalogReinstallFailedStatus)
        }
        let generationID = backup.generationURL.lastPathComponent
        let catalogURL = libraryCatalogURL
        let backupDirectory = libraryBackupDirectoryURL
        let marker = await Task.detached(priority: .userInitiated) {
            try? LibraryPendingRestoreStore.schedule(
                generationID: generationID,
                catalogURL: catalogURL,
                backupDirectory: backupDirectory
            )
        }.value
        guard let marker else {
            return failLibraryCatalogMaintenance(AppLocalizedPhrase.libraryCatalogReinstallFailedStatus)
        }
        libraryPendingRestoreMarker = marker
        isLibraryReinstallPendingRelaunch = true
        relaunchAfterLibraryCatalogMaintenance()
        return true
    }

    /// 저장 검증이 막는 결함 기록 상태 중 "복원 대기"를 푼다. 디스크를 다시 읽어 되살리고,
    /// 기록이 사라졌거나 깨져 되살릴 수 없으면 현재 카탈로그와 결함 폴더를 옆에 보관한 뒤
    /// 그 사진의 결함 편집만 비운다(원본 픽셀은 원래 건드리지 않는다). 읽기 권한 오류나
    /// 더 새 버전 기록처럼 비우면 안 되는 경우는 실패로 돌려준다.
    func settleDefectRecipesForCatalogMaintenance() async -> Bool {
        let pending = frames.filter { !$0.isPreviewScan && $0.defectEditsNeedRestore }
        guard !pending.isEmpty else { return true }
        let directory = libraryDefectDirectoryURL
        let catalogURL = libraryCatalogURL
        var didPreserve = false
        for frame in pending {
            let frameID = frame.id
            let outcome = await Task.detached(priority: .userInitiated) {
                DefectSidecarFile.flushSync()
                return DefectRecipeMaintenanceOutcome.read(frameID: frameID, in: directory)
            }.value
            guard ownsFrame(frame), frame.defectEditsNeedRestore else { continue }
            switch outcome {
            case .restored(let restoration):
                restoration.apply(to: frame)
                guard !frame.defectEditsNeedRestore else { return false }
            case .lost:
                if !didPreserve {
                    let preserved = await Task.detached(priority: .userInitiated) {
                        (try? LibraryPendingRestoreStore.preserveUnsafeState(
                            catalogURL: catalogURL,
                            defectDirectory: directory,
                            fileManager: .default
                        )) != nil
                    }.value
                    guard preserved else { return false }
                    didPreserve = true
                }
                frame.defectEditsNeedRestore = false
                frame.defectEdits = []
                refreshDefectRecipeState(frame, advanceRevision: true, persist: true)
            case .keep:
                return false
            }
        }
        await Task.detached(priority: .userInitiated) { DefectSidecarFile.flushSync() }.value
        return true
    }

    /// 디스크 기록이 메모리 recipe 와 같은 세대가 아닌 사진만 다시 쓴다. 같은 revision 으로는
    /// revision floor 가 다시 쓰기를 막으므로, 이미 알려진 가장 높은 revision 보다 올려서 쓴다.
    func rewriteMismatchedDefectRecipes() async -> Bool {
        let directory = libraryDefectDirectoryURL
        for frame in frames where !frame.isPreviewScan && !frame.defectEdits.isEmpty {
            guard defectSidecarValidationFailure([frame]) != nil
                    || frame.defectGestureRecipeAdvanced else { continue }
            let frameID = frame.id
            let knownRevision = await Task.detached(priority: .userInitiated) {
                DefectSidecarFile.highestKnownRevision(for: frameID, in: directory)
            }.value
            guard ownsFrame(frame) else { continue }
            frame.defectRecipeRevision = max(frame.defectRecipeRevision, knownRevision)
            guard let snapshot = refreshDefectRecipeState(
                frame, advanceRevision: true, persist: false
            ) else { return false }
            let written = await Task.detached(priority: .userInitiated) {
                do {
                    switch try DefectSidecarFile.write(snapshot, in: directory) {
                    case .written, .alreadyCurrent: return true
                    case .skippedNewer: return false
                    }
                } catch {
                    AppModel.recordDefectSidecarWriteFailure("\(error)")
                    return false
                }
            }.value
            guard written, ownsFrame(frame), frame.defectRecipeIdentity == snapshot.identity else {
                return false
            }
        }
        return true
    }

    private func beginLibraryCatalogMaintenance() -> Bool {
        guard canRunLibraryCatalogMaintenance else { return false }
        isLibraryMaintenanceInProgress = true
        librarySaveTask?.cancel()
        librarySaveTask = nil
        return true
    }

    private func failLibraryCatalogMaintenance(_ phrase: AppLocalizedPhrase) -> Bool {
        isLibraryMaintenanceInProgress = false
        reportError(text(phrase))
        return false
    }

    /// 종료 저장 경로(결함 기록 → 카탈로그 커밋·검증)를 그대로 타고 끝난 뒤 다시 연다.
    /// 종료 중 백업이 돌 수 있도록 유지보수 표시는 먼저 내린다.
    private func relaunchAfterLibraryCatalogMaintenance() {
        isLibraryMaintenanceInProgress = false
        statusMessage = text(AppLocalizedPhrase.libraryCatalogRelaunchingStatus)
        isRelaunchRequested = true
        requestTerminationForRelaunch()
    }
}

/// 복원 대기 중인 결함 기록을 디스크에서 다시 읽은 결과.
enum DefectRecipeMaintenanceOutcome: @unchecked Sendable {
    case restored(DefectRecipeRestoration)
    /// 기록이 없거나 깨져 되살릴 수 없다.
    case lost
    /// 읽지 못했거나 더 새 버전이라 건드리면 안 된다.
    case keep

    static func read(frameID: UUID, in directory: URL) -> Self {
        switch DefectSidecarFile.read(for: frameID, in: directory) {
        case .missing, .invalid:
            return .lost
        case .unreadable, .unsupportedVersion:
            return .keep
        case .loaded:
            let restoration = DefectRecipeRestoration.read(frameID: frameID, in: directory)
            return restoration.snapshot == nil ? .lost : .restored(restoration)
        }
    }
}
