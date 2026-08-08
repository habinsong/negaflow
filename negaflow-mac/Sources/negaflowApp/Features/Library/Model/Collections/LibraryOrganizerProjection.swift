import Foundation

struct LibraryManualCollectionMembershipPosition {
    let collectionID: UUID
    let index: Int
    let frameID: UUID
}
enum LibraryOrganizerSelection: Equatable, Hashable, Sendable {
    case all
    case manual(UUID)
    case smart(UUID)
    case savedSearch(UUID)

    var isSmart: Bool {
        if case .smart = self { return true }
        return false
    }
}

struct LibraryOrganizerProjectionRequest: Equatable, Sendable {
    let sourceFrameIDs: [UUID]?
    let query: LibraryQuery
    let sort: LibrarySortDescriptor

    static func resolve(
        selection: LibraryOrganizerSelection,
        manualCollections: [LibraryManualCollection],
        smartCollections: [LibrarySmartCollection],
        savedSearches: [LibrarySavedSearch],
        currentQuery: LibraryQuery,
        currentSort: LibrarySortDescriptor
    ) -> LibraryOrganizerProjectionRequest? {
        switch selection {
        case .all:
            return Self(sourceFrameIDs: nil, query: currentQuery, sort: currentSort)
        case let .manual(id):
            let matches = manualCollections.filter { $0.id == id }
            guard matches.count == 1 else { return nil }
            return Self(
                sourceFrameIDs: matches[0].frameIDs,
                query: currentQuery,
                sort: currentSort
            )
        case let .smart(id):
            let matches = smartCollections.filter { $0.id == id }
            guard matches.count == 1,
                  let definition = matches[0].definition.decodedDefinition() else {
                return nil
            }
            return Self(sourceFrameIDs: nil, query: definition.query, sort: definition.sort)
        case let .savedSearch(id):
            let matches = savedSearches.filter { $0.id == id }
            guard matches.count == 1,
                  let definition = matches[0].definition.decodedDefinition() else {
                return nil
            }
            return Self(sourceFrameIDs: nil, query: definition.query, sort: definition.sort)
        }
    }
}
