import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    func restoreLibraryRemoval(_ record: LibraryRemovalRecord) {
        let previousSelectedFrameIDs = selectedFrameIDs
        let previousSelectedFrameID = selectedFrameID
        let previousSelectionAnchorID = frameSelectionAnchorID
        let rollSnapshot = rollStore.snapshot
        let stackSnapshot = stacks
        let candidateFrameIDs = Set(frames.map(\.id)).union(record.frameIDs)
        guard allowsLibraryMutation,
              let undoManager = catalogUndoManager,
              record.frameIDs.isDisjoint(with: Set(frames.map(\.id))),
              record.folderIDs.isDisjoint(with: Set(libraryFolders.map(\.id))),
              let restoredManualCollections = manualCollectionsRestoringMemberships(
                  record.manualCollectionMemberships,
                  availableFrameIDs: candidateFrameIDs
              ),
              let targetRollByFrameID = restorationRollOverrides(for: record),
              rollStore.restoreMemberships(
                  from: record.rollRemovalDelta,
                  targetRollByFrameID: targetRollByFrameID
              ),
              stackStore.restore(record.stackRemovalDelta) else { return }
        guard restoredFamiliesRemainCoherent(record) else {
            rollStore.replace(with: rollSnapshot)
            stackStore.replace(with: stackSnapshot)
            return
        }

        var restoredFrames = frames
        for entry in record.entries.sorted(by: { $0.index < $1.index }) {
            restoredFrames.insert(entry.frame, at: min(entry.index, restoredFrames.count))
        }
        frames = restoredFrames
        replaceManualCollections(with: restoredManualCollections)

        var restoredFolders = libraryFolders
        for entry in record.folderEntries.sorted(by: { $0.index < $1.index }) {
            restoredFolders.insert(entry.folder, at: min(entry.index, restoredFolders.count))
        }
        libraryFolders = restoredFolders

        undoManager.registerUndo(withTarget: self) { model in
            model.reapplyLibraryRemoval(
                frameIDs: record.frameIDs,
                folderIDs: record.folderIDs
            )
        }
        undoManager.setActionName(text(AppLocalizedPhrase.removeFromLibrary))

        let availableIDs = Set(frames.map(\.id))
        let scopeIDs = interactionFrameIDs
        let scope = Set(scopeIDs)
        let recordedSelection = record.selectedFrameIDs
            .intersection(availableIDs)
            .intersection(scope)
        let currentSelection = previousSelectedFrameIDs
            .intersection(availableIDs)
            .intersection(scope)
        let restoresRecordedSelection = !recordedSelection.isEmpty
        selectedFrameIDs = restoresRecordedSelection ? recordedSelection : currentSelection

        let preferredActiveID = restoresRecordedSelection
            ? record.selectedFrameID
            : previousSelectedFrameID
        let restoredActiveID = preferredActiveID.flatMap {
            selectedFrameIDs.contains($0) ? $0 : nil
        } ?? scopeIDs.first(where: { selectedFrameIDs.contains($0) })
        let preferredAnchorID = restoresRecordedSelection
            ? record.selectionAnchorID
            : previousSelectionAnchorID
        frameSelectionAnchorID = preferredAnchorID.flatMap {
            selectedFrameIDs.contains($0) ? $0 : nil
        } ?? restoredActiveID
        activateFrame(restoredActiveID)
        scheduleLibrarySave()
        statusMessage = text(AppLocalizedPhrase.libraryRemovalRestoredFormat, record.statusItemCount)
    }

    private func restorationRollOverrides(
        for record: LibraryRemovalRecord
    ) -> [UUID: UUID]? {
        let deltaFrameIDs = Set(record.rollRemovalDelta.entries.map(\.frameID))
        guard !deltaFrameIDs.isEmpty else { return [:] }
        let restoringIDs = record.frameIDs
        let restoringFramesByRoot = Dictionary(grouping: record.entries.map(\.frame)) {
            $0.rootFrameID
        }
        var overrides: [UUID: UUID] = [:]

        for (rootID, restoringFamily) in restoringFramesByRoot {
            let restoringMembershipFrames = restoringFamily.filter {
                deltaFrameIDs.contains($0.id)
            }
            guard !restoringMembershipFrames.isEmpty else { continue }
            if restoringIDs.contains(rootID) { continue }

            let survivingFamily = frames.filter {
                !$0.isPreviewScan && $0.rootFrameID == rootID
            }
            guard survivingFamily.contains(where: { $0.id == rootID }) else { return nil }
            let rollIDs = survivingFamily.compactMap { rollStore.rollID(containing: $0.id) }
            guard rollIDs.count == survivingFamily.count,
                  Set(rollIDs).count == 1,
                  let currentRollID = rollIDs.first else {
                return nil
            }
            for restored in restoringMembershipFrames {
                overrides[restored.id] = currentRollID
            }
        }
        return overrides
    }

    private func restoredFamiliesRemainCoherent(_ record: LibraryRemovalRecord) -> Bool {
        let deltaFrameIDs = Set(record.rollRemovalDelta.entries.map(\.frameID))
        guard !deltaFrameIDs.isEmpty else { return true }
        let candidateFrames = frames + record.entries.map(\.frame)
        let affectedRootIDs = Set(record.entries.compactMap { entry -> UUID? in
            deltaFrameIDs.contains(entry.frame.id) ? entry.frame.rootFrameID : nil
        })
        for rootID in affectedRootIDs {
            let family = candidateFrames.filter {
                !$0.isPreviewScan && $0.rootFrameID == rootID
            }
            guard family.contains(where: { $0.id == rootID }) else { return false }
            let rollIDs = family.compactMap { rollStore.rollID(containing: $0.id) }
            guard rollIDs.count == family.count, Set(rollIDs).count == 1 else {
                return false
            }
        }
        return true
    }

    private func reapplyLibraryRemoval(
        frameIDs: Set<UUID>,
        folderIDs: Set<UUID>
    ) {
        guard allowsLibraryMutation,
              !containsProtectedScanProvenanceRoot(frameIDs: frameIDs),
              let undoManager = catalogUndoManager,
              let record = captureLibraryRemovalRecord(
                  frameIDs: frameIDs,
                  folderIDs: folderIDs
              ) else { return }
        if !record.frameIDs.isEmpty {
            performLibraryRemoval(record.frameIDs, preservingDefectSidecars: true)
        }
        if !record.folderIDs.isEmpty {
            libraryFolders.removeAll { record.folderIDs.contains($0.id) }
            scheduleLibrarySave()
        }
        undoManager.registerUndo(withTarget: self) { model in
            model.restoreLibraryRemoval(record)
        }
        undoManager.setActionName(text(AppLocalizedPhrase.removeFromLibrary))
        statusMessage = text(AppLocalizedPhrase.libraryRemovalUndoAvailableFormat, record.statusItemCount)
    }


}
