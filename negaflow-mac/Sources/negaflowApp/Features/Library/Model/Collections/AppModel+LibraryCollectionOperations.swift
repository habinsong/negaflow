import AppKit
import Foundation

extension AppModel {
    @discardableResult
    func createManualCollection(
        named name: String,
        frameIDs: [UUID] = []
    ) -> UUID? {
        guard allowsLibraryMutation,
              let name = normalizedOrganizerName(name),
              validManualCollectionFrameIDs(frameIDs) else {
            return nil
        }
        let collection = LibraryManualCollection(
            id: uniqueOrganizerID(excluding: Set(manualCollections.map(\.id))),
            name: name,
            frameIDs: frameIDs
        )
        insertManualCollection(collection, at: manualCollections.count, recordsUndo: true)
        return collection.id
    }

    @discardableResult
    func renameManualCollection(id: UUID, to name: String) -> Bool {
        guard allowsLibraryMutation,
              let name = normalizedOrganizerName(name),
              let index = uniqueIndex(id: id, in: manualCollections) else {
            return false
        }
        var replacement = manualCollections[index]
        guard replacement.name != name else { return true }
        replacement.name = name
        replaceManualCollection(replacement, recordsUndo: true)
        return true
    }

    @discardableResult
    func deleteManualCollection(id: UUID) -> Bool {
        guard allowsLibraryMutation,
              let index = uniqueIndex(id: id, in: manualCollections) else {
            return false
        }
        removeManualCollection(at: index, recordsUndo: true)
        return true
    }

    @discardableResult
    func addFrameIDs(_ frameIDs: [UUID], toManualCollection id: UUID) -> Bool {
        guard validManualCollectionFrameIDs(frameIDs),
              let index = uniqueIndex(id: id, in: manualCollections) else {
            return false
        }
        var replacement = manualCollections[index]
        let existing = Set(replacement.frameIDs)
        replacement.frameIDs.append(contentsOf: frameIDs.filter { !existing.contains($0) })
        guard replacement != manualCollections[index] else { return true }
        replaceManualCollection(replacement, recordsUndo: true)
        return true
    }

    @discardableResult
    func removeFrameIDs(_ frameIDs: Set<UUID>, fromManualCollection id: UUID) -> Bool {
        guard allowsLibraryMutation,
              let index = uniqueIndex(id: id, in: manualCollections) else {
            return false
        }
        var replacement = manualCollections[index]
        replacement.frameIDs.removeAll { frameIDs.contains($0) }
        guard replacement != manualCollections[index] else { return true }
        replaceManualCollection(replacement, recordsUndo: true)
        return true
    }

    @discardableResult
    func createSmartCollection(
        named name: String,
        definition: LibrarySearchDefinition
    ) -> UUID? {
        guard allowsLibraryMutation,
              let name = normalizedOrganizerName(name),
              let envelope = validStoredSearchEnvelope(definition) else {
            return nil
        }
        let collection = LibrarySmartCollection(
            id: uniqueOrganizerID(excluding: Set(smartCollections.map(\.id))),
            name: name,
            definition: envelope
        )
        insertSmartCollection(collection, at: smartCollections.count, recordsUndo: true)
        return collection.id
    }

    @discardableResult
    func renameSmartCollection(id: UUID, to name: String) -> Bool {
        guard allowsLibraryMutation,
              let name = normalizedOrganizerName(name),
              let index = uniqueIndex(id: id, in: smartCollections) else {
            return false
        }
        var replacement = smartCollections[index]
        guard replacement.name != name else { return true }
        replacement.name = name
        replaceSmartCollection(replacement, recordsUndo: true)
        return true
    }

    @discardableResult
    func updateSmartCollection(
        id: UUID,
        definition: LibrarySearchDefinition
    ) -> Bool {
        guard allowsLibraryMutation,
              let envelope = validStoredSearchEnvelope(definition),
              let index = uniqueIndex(id: id, in: smartCollections) else {
            return false
        }
        var replacement = smartCollections[index]
        guard replacement.definition != envelope else { return true }
        replacement.definition = envelope
        replaceSmartCollection(replacement, recordsUndo: true)
        return true
    }

    @discardableResult
    func deleteSmartCollection(id: UUID) -> Bool {
        guard allowsLibraryMutation,
              let index = uniqueIndex(id: id, in: smartCollections) else {
            return false
        }
        removeSmartCollection(at: index, recordsUndo: true)
        return true
    }

    @discardableResult
    func createSavedSearch(
        named name: String,
        definition: LibrarySearchDefinition
    ) -> UUID? {
        guard allowsLibraryMutation,
              let name = normalizedOrganizerName(name),
              let envelope = validStoredSearchEnvelope(definition) else {
            return nil
        }
        let savedSearch = LibrarySavedSearch(
            id: uniqueOrganizerID(excluding: Set(savedSearches.map(\.id))),
            name: name,
            definition: envelope
        )
        insertSavedSearch(savedSearch, at: savedSearches.count, recordsUndo: true)
        return savedSearch.id
    }

    @discardableResult
    func renameSavedSearch(id: UUID, to name: String) -> Bool {
        guard allowsLibraryMutation,
              let name = normalizedOrganizerName(name),
              let index = uniqueIndex(id: id, in: savedSearches) else {
            return false
        }
        var replacement = savedSearches[index]
        guard replacement.name != name else { return true }
        replacement.name = name
        replaceSavedSearch(replacement, recordsUndo: true)
        return true
    }

    @discardableResult
    func updateSavedSearch(
        id: UUID,
        definition: LibrarySearchDefinition
    ) -> Bool {
        guard allowsLibraryMutation,
              let envelope = validStoredSearchEnvelope(definition),
              let index = uniqueIndex(id: id, in: savedSearches) else {
            return false
        }
        var replacement = savedSearches[index]
        guard replacement.definition != envelope else { return true }
        replacement.definition = envelope
        replaceSavedSearch(replacement, recordsUndo: true)
        return true
    }

    @discardableResult
    func deleteSavedSearch(id: UUID) -> Bool {
        guard allowsLibraryMutation,
              let index = uniqueIndex(id: id, in: savedSearches) else {
            return false
        }
        removeSavedSearch(at: index, recordsUndo: true)
        return true
    }

    func manualCollectionNamesByFrameID() -> [UUID: [String]] {
        let frameGroups = Dictionary(grouping: frames.filter { !$0.isPreviewScan }, by: \.id)
        let collectionIDCounts = Dictionary(grouping: manualCollections, by: \.id)
            .mapValues(\.count)
        guard collectionIDCounts.values.allSatisfy({ $0 == 1 }) else { return [:] }
        var names = frameGroups.reduce(into: [UUID: [String]]()) { result, entry in
            guard entry.value.count == 1 else { return }
            result[entry.key] = []
        }
        for collection in manualCollections {
            let membershipCounts = Dictionary(grouping: collection.frameIDs, by: { $0 })
                .mapValues(\.count)
            guard normalizedOrganizerName(collection.name) != nil,
                  membershipCounts.values.allSatisfy({ $0 == 1 }),
                  membershipCounts.keys.allSatisfy({ frameGroups[$0]?.count == 1 }) else {
                return [:]
            }
            for frameID in collection.frameIDs {
                names[frameID, default: []].append(collection.name)
            }
        }
        return names
    }

    func removeFrameIDsFromManualCollections(_ frameIDs: Set<UUID>) {
        guard !frameIDs.isEmpty else { return }
        var updated = manualCollections
        var changed = false
        for index in updated.indices {
            let previousCount = updated[index].frameIDs.count
            updated[index].frameIDs.removeAll { frameIDs.contains($0) }
            changed = changed || updated[index].frameIDs.count != previousCount
        }
        if changed { replaceManualCollections(with: updated) }
    }

    func manualCollectionsRestoringMemberships(
        _ entries: [LibraryManualCollectionMembershipPosition],
        availableFrameIDs: Set<UUID>
    ) -> [LibraryManualCollection]? {
        guard !entries.isEmpty else { return manualCollections }
        var updated = manualCollections
        for (collectionID, collectionEntries) in Dictionary(grouping: entries, by: \.collectionID) {
            let matches = updated.indices.filter { updated[$0].id == collectionID }
            guard matches.count <= 1 else { return nil }
            guard let collectionIndex = matches.first else { continue }
            for entry in collectionEntries.sorted(by: { $0.index < $1.index }) {
                guard availableFrameIDs.contains(entry.frameID) else { return nil }
                guard !updated[collectionIndex].frameIDs.contains(entry.frameID) else { continue }
                updated[collectionIndex].frameIDs.insert(
                    entry.frameID,
                    at: min(entry.index, updated[collectionIndex].frameIDs.count)
                )
            }
        }
        return updated
    }
}
