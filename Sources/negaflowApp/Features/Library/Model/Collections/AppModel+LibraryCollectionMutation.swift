import AppKit
import Foundation

extension AppModel {
    func normalizedOrganizerName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    func validManualCollectionFrameIDs(_ frameIDs: [UUID]) -> Bool {
        guard allowsLibraryMutation, Set(frameIDs).count == frameIDs.count else { return false }
        let groups = Dictionary(grouping: frames.filter { !$0.isPreviewScan }, by: \.id)
        return frameIDs.allSatisfy { groups[$0]?.count == 1 }
    }

    func validStoredSearchEnvelope(
        _ definition: LibrarySearchDefinition
    ) -> LibraryStoredSearchEnvelope? {
        guard definition.version == LibrarySearchDefinition.currentVersion,
              definition.query.isValid else {
            return nil
        }
        return try? LibraryStoredSearchEnvelope(definition: definition)
    }

    func uniqueOrganizerID(excluding ids: Set<UUID>) -> UUID {
        var id = UUID()
        while ids.contains(id) { id = UUID() }
        return id
    }

    func uniqueIndex<T: Identifiable>(id: UUID, in values: [T]) -> Int? where T.ID == UUID {
        let matches = values.indices.filter { values[$0].id == id }
        return matches.count == 1 ? matches[0] : nil
    }

    func insertManualCollection(
        _ collection: LibraryManualCollection,
        at index: Int,
        recordsUndo: Bool
    ) {
        guard allowsLibraryMutation,
              !manualCollections.contains(where: { $0.id == collection.id }) else { return }
        var updated = manualCollections
        updated.insert(collection, at: min(max(index, 0), updated.count))
        replaceManualCollections(with: updated)
        guard recordsUndo, let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            guard let currentIndex = model.uniqueIndex(id: collection.id, in: model.manualCollections) else {
                return
            }
            model.removeManualCollection(at: currentIndex, recordsUndo: true)
        }
        undoManager.setActionName(text(AppLocalizedPhrase.libraryCollections))
    }

    func removeManualCollection(at index: Int, recordsUndo: Bool) {
        guard allowsLibraryMutation, manualCollections.indices.contains(index) else { return }
        var updated = manualCollections
        let removed = updated.remove(at: index)
        replaceManualCollections(with: updated)
        guard recordsUndo, let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.insertManualCollection(removed, at: index, recordsUndo: true)
        }
        undoManager.setActionName(text(AppLocalizedPhrase.libraryCollections))
    }

    func replaceManualCollection(
        _ replacement: LibraryManualCollection,
        recordsUndo: Bool
    ) {
        guard allowsLibraryMutation,
              let index = uniqueIndex(id: replacement.id, in: manualCollections) else { return }
        let previous = manualCollections[index]
        var updated = manualCollections
        updated[index] = replacement
        replaceManualCollections(with: updated)
        guard recordsUndo, let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.replaceManualCollection(previous, recordsUndo: true)
        }
        undoManager.setActionName(text(AppLocalizedPhrase.libraryCollections))
    }

    func insertSmartCollection(
        _ collection: LibrarySmartCollection,
        at index: Int,
        recordsUndo: Bool
    ) {
        guard allowsLibraryMutation,
              !smartCollections.contains(where: { $0.id == collection.id }) else { return }
        var updated = smartCollections
        updated.insert(collection, at: min(max(index, 0), updated.count))
        replaceSmartCollections(with: updated)
        guard recordsUndo, let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            guard let currentIndex = model.uniqueIndex(id: collection.id, in: model.smartCollections) else {
                return
            }
            model.removeSmartCollection(at: currentIndex, recordsUndo: true)
        }
        undoManager.setActionName(text(AppLocalizedPhrase.librarySmartCollections))
    }

    func removeSmartCollection(at index: Int, recordsUndo: Bool) {
        guard allowsLibraryMutation, smartCollections.indices.contains(index) else { return }
        var updated = smartCollections
        let removed = updated.remove(at: index)
        replaceSmartCollections(with: updated)
        guard recordsUndo, let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.insertSmartCollection(removed, at: index, recordsUndo: true)
        }
        undoManager.setActionName(text(AppLocalizedPhrase.librarySmartCollections))
    }

    func replaceSmartCollection(
        _ replacement: LibrarySmartCollection,
        recordsUndo: Bool
    ) {
        guard allowsLibraryMutation,
              let index = uniqueIndex(id: replacement.id, in: smartCollections) else { return }
        let previous = smartCollections[index]
        var updated = smartCollections
        updated[index] = replacement
        replaceSmartCollections(with: updated)
        guard recordsUndo, let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.replaceSmartCollection(previous, recordsUndo: true)
        }
        undoManager.setActionName(text(AppLocalizedPhrase.librarySmartCollections))
    }

    func insertSavedSearch(
        _ savedSearch: LibrarySavedSearch,
        at index: Int,
        recordsUndo: Bool
    ) {
        guard allowsLibraryMutation,
              !savedSearches.contains(where: { $0.id == savedSearch.id }) else { return }
        var updated = savedSearches
        updated.insert(savedSearch, at: min(max(index, 0), updated.count))
        replaceSavedSearches(with: updated)
        guard recordsUndo, let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            guard let currentIndex = model.uniqueIndex(id: savedSearch.id, in: model.savedSearches) else {
                return
            }
            model.removeSavedSearch(at: currentIndex, recordsUndo: true)
        }
        undoManager.setActionName(text(AppLocalizedPhrase.librarySavedSearches))
    }

    func removeSavedSearch(at index: Int, recordsUndo: Bool) {
        guard allowsLibraryMutation, savedSearches.indices.contains(index) else { return }
        var updated = savedSearches
        let removed = updated.remove(at: index)
        replaceSavedSearches(with: updated)
        guard recordsUndo, let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.insertSavedSearch(removed, at: index, recordsUndo: true)
        }
        undoManager.setActionName(text(AppLocalizedPhrase.librarySavedSearches))
    }

    func replaceSavedSearch(_ replacement: LibrarySavedSearch, recordsUndo: Bool) {
        guard allowsLibraryMutation,
              let index = uniqueIndex(id: replacement.id, in: savedSearches) else { return }
        let previous = savedSearches[index]
        var updated = savedSearches
        updated[index] = replacement
        replaceSavedSearches(with: updated)
        guard recordsUndo, let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.replaceSavedSearch(previous, recordsUndo: true)
        }
        undoManager.setActionName(text(AppLocalizedPhrase.librarySavedSearches))
    }
}
