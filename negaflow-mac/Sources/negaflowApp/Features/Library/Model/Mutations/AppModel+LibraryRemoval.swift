import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {

    /// 라이브러리에서만 제거한다. 원본 파일은 건드리지 않는다.
    /// 사용자 제거는 macOS Undo/Redo에 등록하며, 내부 프리뷰 정리와 실제 원본 휴지통 이동은
    /// `undoable: false`로 호출해 서로 다른 수명주기를 섞지 않는다.
    func removeFramesFromLibrary(
        _ framesToRemove: [ScanFrame],
        undoable: Bool = true,
        restoringFoldersOnUndo foldersToRestore: [LibraryFolder] = []
    ) {
        guard allowsLibraryMutation else { return }
        let directRequestedIDs = Set(framesToRemove.map(\.id))
        let removedOriginalRootIDs = Set(frames.compactMap { frame -> UUID? in
            directRequestedIDs.contains(frame.id) && !frame.isVirtualCopy
                ? frame.rootFrameID
                : nil
        })
        let requestedIDs = directRequestedIDs.union(frames.compactMap { frame -> UUID? in
            removedOriginalRootIDs.contains(frame.rootFrameID) ? frame.id : nil
        })
        let requestedFolderIDs = Set(foldersToRestore.map(\.id))
        guard let record = captureLibraryRemovalRecord(
            frameIDs: requestedIDs,
            folderIDs: requestedFolderIDs
        ) else { return }
        let recordsUndo = undoable && catalogUndoManager != nil
        if !record.frameIDs.isEmpty {
            performLibraryRemoval(record.frameIDs, preservingDefectSidecars: recordsUndo)
        }
        guard recordsUndo, let undoManager = catalogUndoManager else { return }
        registerLibraryRemovalUndo(record, with: undoManager)
        statusMessage = text(AppLocalizedPhrase.libraryRemovalUndoAvailableFormat, record.statusItemCount)
    }

    func captureLibraryRemovalRecord(
        frameIDs: Set<UUID>,
        folderIDs: Set<UUID>
    ) -> LibraryRemovalRecord? {
        let entries = frames.enumerated().compactMap { index, frame -> LibraryRemovalRecord.Entry? in
            frameIDs.contains(frame.id) ? LibraryRemovalRecord.Entry(index: index, frame: frame) : nil
        }
        let folderEntries = libraryFolders.enumerated().compactMap {
            index, folder -> LibraryRemovalRecord.FolderEntry? in
            folderIDs.contains(folder.id)
                ? LibraryRemovalRecord.FolderEntry(index: index, folder: folder)
                : nil
        }
        let manualCollectionMemberships = manualCollections.flatMap { collection in
            collection.frameIDs.enumerated().compactMap { index, frameID in
                frameIDs.contains(frameID)
                    ? LibraryManualCollectionMembershipPosition(
                        collectionID: collection.id,
                        index: index,
                        frameID: frameID
                    )
                    : nil
            }
        }
        guard Set(entries.map { $0.frame.id }) == frameIDs,
              Set(folderEntries.map { $0.folder.id }) == folderIDs,
              !entries.isEmpty || !folderEntries.isEmpty else {
            return nil
        }
        return LibraryRemovalRecord(
            entries: entries,
            folderEntries: folderEntries,
            selectedFrameIDs: selectedFrameIDs,
            selectedFrameID: selectedFrameID,
            selectionAnchorID: frameSelectionAnchorID,
            rollRemovalDelta: rollStore.removalDelta(for: frameIDs),
            stackRemovalDelta: stackStore.removalDelta(for: frameIDs),
            manualCollectionMemberships: manualCollectionMemberships
        )
    }

    func performLibraryRemoval(
        _ ids: Set<UUID>,
        preservingDefectSidecars: Bool
    ) {
        let oldSelectedFrameID = selectedFrameID
        let oldScopeIDs = interactionFrameIDs
        let adjacentReplacementID = oldSelectedFrameID.flatMap { activeID in
            interactionReplacementFrameID(
                afterRemoving: ids,
                activeID: activeID,
                orderedScopeIDs: oldScopeIDs
            )
        }
        if let oldSelectedFrameID, ids.contains(oldSelectedFrameID) {
            // FrameStore는 소유 프레임이 사라지면 전역 마지막 프레임을 자동 선택한다. 먼저 활성
            // 프레임을 비워 화면 scope 밖 프레임이 순간적으로 복원·현상되는 것을 막는다.
            activateFrame(nil)
        }
        for frame in frames where ids.contains(frame.id) {
            frame.developRevision += 1
            frame.transformRevision += 1
            frame.defectDetectRevision += 1
            frame.cleanRawRevision += 1
            frame.transformTask?.cancel()
            frame.defectDetectTask?.cancel()
            frame.cleanRawTask?.cancel()
            cancelInfraredClean(frame)
            discardCleanedRaw(frame, preservingDefectSidecar: preservingDefectSidecars)
            frame.stripDefectPatchCaches()
            evictDevelopBuffers(frame)
            frameCacheManager.removeDevelopedResident(frame)
            removeThumbnailFile(for: frame)
        }
        rollStore.removeFrameIDs(ids)
        stackStore.removeFrameIDs(ids)
        removeFrameIDsFromManualCollections(ids)
        frames.removeAll { ids.contains($0.id) }
        selectedFrameIDs.subtract(ids)
        let availableIDs = Set(frames.map(\.id))
        selectedFrameIDs.formIntersection(availableIDs)
        let remainingScopeIDs = oldScopeIDs.filter { availableIDs.contains($0) }
        selectedFrameIDs.formIntersection(Set(remainingScopeIDs))

        if let active = selectedFrameID, selectedFrameIDs.contains(active) {
            if frameSelectionAnchorID.map(remainingScopeIDs.contains) != true {
                frameSelectionAnchorID = active
            }
            return
        }

        if let survivingSelectedID = remainingScopeIDs.first(where: { selectedFrameIDs.contains($0) }) {
            frameSelectionAnchorID = survivingSelectedID
            activateFrame(survivingSelectedID)
        } else if let adjacentReplacementID,
                  availableIDs.contains(adjacentReplacementID) {
            selectedFrameIDs = [adjacentReplacementID]
            frameSelectionAnchorID = adjacentReplacementID
            activateFrame(adjacentReplacementID)
        } else {
            selectedFrameIDs = []
            frameSelectionAnchorID = nil
            activateFrame(nil)
        }
    }

    private func interactionReplacementFrameID(
        afterRemoving removedIDs: Set<UUID>,
        activeID: UUID,
        orderedScopeIDs: [UUID]
    ) -> UUID? {
        guard let activeIndex = orderedScopeIDs.firstIndex(of: activeID) else { return nil }
        if activeIndex + 1 < orderedScopeIDs.count,
           let nextID = orderedScopeIDs[(activeIndex + 1)...].first(where: { !removedIDs.contains($0) }) {
            return nextID
        }
        return orderedScopeIDs[..<activeIndex].reversed().first(where: { !removedIDs.contains($0) })
    }

    private func registerLibraryRemovalUndo(
        _ record: LibraryRemovalRecord,
        with undoManager: UndoManager
    ) {
        undoManager.registerUndo(withTarget: self) { model in
            model.restoreLibraryRemoval(record)
        }
        undoManager.setActionName(text(AppLocalizedPhrase.removeFromLibrary))
    }


}
