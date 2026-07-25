import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    /// 실제 파일 삭제는 원본 프레임을 명시적으로 선택했을 때만 계획한다. 가상 사본만 선택한
    /// 경우에는 nil이며, 같은 파일을 공유하는 모든 catalog frame이 영향 범위에 포함된다.
    func sourceDeletionPlan(for framesToDelete: [ScanFrame]) -> SourceDeletionPlan? {
        let requestedSources = Set(framesToDelete.filter { !$0.isVirtualCopy && !$0.isPreviewScan }.map {
            $0.rawScanURL.standardizedFileURL.path
        })
        guard !requestedSources.isEmpty else { return nil }

        let groups = requestedSources.sorted().compactMap { path -> SourceDeletionPlan.Group? in
            let affected = frames.filter { $0.rawScanURL.standardizedFileURL.path == path }
            guard !affected.isEmpty else { return nil }
            let infrared = Set(affected.compactMap { $0.infraredScanURL?.standardizedFileURL.path })
                .sorted()
                .map { URL(fileURLWithPath: $0) }
            return SourceDeletionPlan.Group(
                sourceURL: URL(fileURLWithPath: path),
                frameIDs: Set(affected.map(\.id)),
                infraredURLs: infrared
            )
        }
        return groups.isEmpty ? nil : SourceDeletionPlan(groups: groups)
    }

    /// 확인된 계획의 모든 원본/IR 파일을 OS 휴지통으로 옮기고, 제거 후 catalog를 read-back
    /// commit한 뒤에만 MainActor 상태를 publish한다. 파일 이동 또는 catalog commit이 실패하면
    /// 이미 옮긴 파일을 역순으로 원위치해 부분 삭제를 남기지 않는다.
    func deleteSourceFiles(_ plan: SourceDeletionPlan) {
        Task { await performSourceDeletion(plan, fileOperations: .live) }
    }

    /// 파일 이동(휴지통)은 백그라운드에서, 검증·후보 계산·catalog commit·상태 publish 는
    /// MainActor 에서 수행한다 — performSourceMove 와 같은 구조. await 동안에는
    /// isSourceMoveInProgress 가 allowsLibraryMutation 을 내려 라이브러리 구성이 동결되므로
    /// await 이전에 계산한 후보 스냅샷이 commit 시점에도 유효하다(fail-closed 순서 보존).
    @discardableResult
    func performSourceDeletion(
        _ plan: SourceDeletionPlan,
        fileOperations: SourceTrashFileOperations = .live
    ) async -> Bool {
        guard allowsLibraryMutation else { return false }
        guard let plannedFrameIDs = validatedSourceDeletionFrameIDs(plan) else {
            statusMessage = text(AppLocalizedPhrase.sourceDeletionPlanChangedStatus)
            return false
        }
        isSourceMoveInProgress = true
        defer { isSourceMoveInProgress = false }
        guard beginAcknowledgedLibraryTransaction() else {
            statusMessage = text(AppLocalizedPhrase.sourceDeletionUnavailableStatus)
            return false
        }
        defer { endAcknowledgedLibraryTransaction() }

        let candidateFrames = frames.filter { !plannedFrameIDs.contains($0.id) }
        let candidateRolls = rolls.compactMap { roll -> LibraryRoll? in
            var updated = roll
            updated.frameIDs.removeAll { plannedFrameIDs.contains($0) }
            return updated.kind == .unassigned && updated.frameIDs.isEmpty ? nil : updated
        }
        let candidateManualCollections = manualCollections.map { collection -> LibraryManualCollection in
            var updated = collection
            updated.frameIDs.removeAll { plannedFrameIDs.contains($0) }
            return updated
        }
        let fileURLs = plan.groups.flatMap { [$0.sourceURL] + $0.infraredURLs }
        let staged = await Task.detached(priority: .utility) {
            SourceTrashTransaction.stage(urls: fileURLs, operations: fileOperations)
        }.value

        switch staged {
        case .missingFiles:
            statusMessage = text(AppLocalizedPhrase.sourceDeletionPlanChangedStatus)
            return false
        case .moveFailed(_, let rollbackFailures):
            reportSourceDeletionFailure(
                rollbackFailures: rollbackFailures,
                fallback: .sourceDeletionMoveFailedStatus
            )
            return false
        case .staged(let moved):
            let commitSucceeded: Bool = {
                if case .success = commitAcknowledgedLibrarySnapshot(
                    frames: candidateFrames,
                    rolls: candidateRolls,
                    activeRollID: activeRollID,
                    scanSessions: scanSessions,
                    scanRollAssignments: scanRollAssignments,
                    manualCollections: candidateManualCollections
                ) {
                    return true
                }
                return false
            }()
            guard commitSucceeded else {
                let rollbackFailures = await Task.detached(priority: .utility) {
                    SourceTrashTransaction.rollback(moved, operations: fileOperations)
                }.value
                reportSourceDeletionFailure(
                    rollbackFailures: rollbackFailures,
                    fallback: .sourceDeletionCatalogFailedStatus
                )
                return false
            }
            // 실제 파일 삭제는 되돌릴 수 없는 수명주기다. 과거 catalog undo/redo가 휴지통으로
            // 이동한 원본이나 고아 가상 사본을 다시 복원하지 못하도록 모두 무효화한다.
            invalidateCatalogUndoHistoryAfterSourceTrash()
            let sidecarRemovalRevisions = Dictionary(uniqueKeysWithValues: frames.compactMap {
                plannedFrameIDs.contains($0.id)
                    ? ($0.id, $0.defectRecipeRevision &+ 1)
                    : nil
            })
            performLibraryRemoval(plannedFrameIDs, preservingDefectSidecars: false)
            purgeSourceDeletionArtifacts(
                frameIDs: plannedFrameIDs,
                sidecarRemovalRevisions: sidecarRemovalRevisions
            )
            acknowledgeCurrentLibraryStateMatchesCommittedSnapshot()
            return true
        }
    }

    private func purgeSourceDeletionArtifacts(
        frameIDs: Set<UUID>,
        sidecarRemovalRevisions: [UUID: UInt64]
    ) {
        for frameID in frameIDs {
            CleanedRawCacheFile.removeAll(
                for: frameID,
                additionalDirectories: diskStorage.cleanedRawKnownDirectories
            )
            if let revision = sidecarRemovalRevisions[frameID] {
                try? DefectSidecarFile.remove(
                    for: frameID,
                    atRevision: max(revision, 1),
                    in: libraryDefectDirectoryURL
                )
            } else {
                try? DefectSidecarFile.remove(
                    for: frameID,
                    in: libraryDefectDirectoryURL
                )
            }
        }
    }

    private func validatedSourceDeletionFrameIDs(
        _ plan: SourceDeletionPlan
    ) -> Set<UUID>? {
        guard !plan.groups.isEmpty else { return nil }
        let sourcePaths = plan.groups.map { $0.sourceURL.standardizedFileURL.path }
        guard Set(sourcePaths).count == sourcePaths.count else { return nil }

        var validatedIDs = Set<UUID>()
        for group in plan.groups {
            guard !group.frameIDs.isEmpty,
                  validatedIDs.isDisjoint(with: group.frameIDs) else {
                return nil
            }
            let path = group.sourceURL.standardizedFileURL.path
            let affected = frames.filter {
                $0.rawScanURL.standardizedFileURL.path == path
            }
            let currentFrameIDs = Set(affected.map(\.id))
            let currentInfraredPaths = Set(affected.compactMap {
                $0.infraredScanURL?.standardizedFileURL.path
            })
            let plannedInfraredPaths = Set(group.infraredURLs.map {
                $0.standardizedFileURL.path
            })
            guard currentFrameIDs == group.frameIDs,
                  currentInfraredPaths == plannedInfraredPaths else {
                return nil
            }
            validatedIDs.formUnion(group.frameIDs)
        }
        return validatedIDs
    }

    private func reportSourceDeletionFailure(
        rollbackFailures: [String],
        fallback: AppLocalizedPhrase
    ) {
        guard !rollbackFailures.isEmpty else {
            statusMessage = text(fallback)
            return
        }
        statusMessage = text(AppLocalizedPhrase.sourceDeletionRollbackFailedStatus)
            + "\n"
            + rollbackFailures.joined(separator: "\n")
    }

    func invalidateCatalogUndoHistoryAfterSourceTrash() {
        catalogUndoManager?.removeAllActions()
    }

    /// 기존 내부 호출 호환. UI는 반드시 plan을 표시해 확인받은 뒤 위 overload를 호출한다.
    func deleteSourceFiles(_ framesToDelete: [ScanFrame]) {
        guard let plan = sourceDeletionPlan(for: framesToDelete) else { return }
        deleteSourceFiles(plan)
    }

    func deleteFrame(_ frame: ScanFrame) {
        removeFramesFromLibrary([frame])
    }


}
