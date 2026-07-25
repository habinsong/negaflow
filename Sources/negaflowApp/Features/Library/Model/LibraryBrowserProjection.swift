import Foundation
import Chromabase

struct LibrarySortDescriptor: Codable, Equatable, Sendable {
    var key: LibrarySortKey
    var ascending: Bool
}

struct LibraryBrowserFolderSection: Equatable, Sendable {
    let id: String
    let folderID: UUID?
    let title: String
    let orderedFrameIDs: [UUID]
}

struct LibraryBrowserProjection: Equatable, Sendable {
    let contextGeneration: UInt64
    let sourceCount: Int
    let matchedCount: Int
    let orderedFrameIDs: [UUID]
    let folderSections: [LibraryBrowserFolderSection]
    let queryWasValid: Bool

    func restrictingFolderSections(toStoredFilmType filmType: FilmType) -> Self {
        Self(
            contextGeneration: contextGeneration,
            sourceCount: sourceCount,
            matchedCount: matchedCount,
            orderedFrameIDs: orderedFrameIDs,
            folderSections: folderSections.filter { section in
                FrameStorageNaming.storedFilmType(
                    forFilmFolderURL: URL(fileURLWithPath: section.id, isDirectory: true)
                ) == filmType
            },
            queryWasValid: queryWasValid
        )
    }

    static func make(
        sourceFrameIDs: [UUID],
        query: LibraryQuery,
        context: LibraryQueryContext,
        sort: LibrarySortDescriptor
    ) -> LibraryBrowserProjection {
        let sourceIDs = stableUnique(sourceFrameIDs)
        guard let predicate = LibraryQueryPredicate(query) else {
            return LibraryBrowserProjection(
                contextGeneration: context.generation,
                sourceCount: sourceIDs.count,
                matchedCount: 0,
                orderedFrameIDs: [],
                folderSections: [],
                queryWasValid: false
            )
        }

        let matchingIDs = sourceIDs.filter { frameID in
            guard let facts = context.factsByFrameID[frameID] else { return false }
            return predicate.matches(facts, context: context)
        }
        let orderedIDs = sortFrameIDs(matchingIDs, context: context, descriptor: sort)
        return LibraryBrowserProjection(
            contextGeneration: context.generation,
            sourceCount: sourceIDs.count,
            matchedCount: orderedIDs.count,
            orderedFrameIDs: orderedIDs,
            folderSections: makeFolderSections(orderedIDs, context: context),
            queryWasValid: true
        )
    }

    func refining(
        with refinement: LibraryQueryTextRefinement,
        context: LibraryQueryContext
    ) -> LibraryBrowserProjection {
        let condition = refinement.condition
        let predicate = LibraryPreparedTextPredicate(condition)
        let matchingIDs = orderedFrameIDs.filter { frameID in
            guard let facts = context.factsByFrameID[frameID] else { return false }
            return predicate.matches(
                facts.textValues[condition.field] ?? [],
                substringIndex: facts.anySearchableSubstringIndex,
                knowledgeIsComplete: !facts.unknownTextFields.contains(condition.field)
            )
        }
        return LibraryBrowserProjection(
            contextGeneration: context.generation,
            sourceCount: sourceCount,
            matchedCount: matchingIDs.count,
            orderedFrameIDs: matchingIDs,
            folderSections: Self.makeFolderSections(matchingIDs, context: context),
            queryWasValid: true
        )
    }

    private static func sortFrameIDs(
        _ frameIDs: [UUID],
        context: LibraryQueryContext,
        descriptor: LibrarySortDescriptor
    ) -> [UUID] {
        guard descriptor.key != .inputOrder else {
            return descriptor.ascending ? frameIDs : frameIDs.reversed()
        }
        let sourceOrder = Dictionary(uniqueKeysWithValues: frameIDs.enumerated().map {
            ($0.element, $0.offset)
        })
        return frameIDs.sorted { lhsID, rhsID in
            guard let lhs = context.factsByFrameID[lhsID],
                  let rhs = context.factsByFrameID[rhsID] else {
                return (sourceOrder[lhsID] ?? 0) < (sourceOrder[rhsID] ?? 0)
            }

            if descriptor.key == .fileSize {
                switch (lhs.fileSizeBytes, rhs.fileSizeBytes) {
                case let (lhsSize?, rhsSize?) where lhsSize != rhsSize:
                    return descriptor.ascending ? lhsSize < rhsSize : lhsSize > rhsSize
                case (nil, .some):
                    return false
                case (.some, nil):
                    return true
                default:
                    return (sourceOrder[lhsID] ?? 0) < (sourceOrder[rhsID] ?? 0)
                }
            }

            let comparison = compare(lhs, rhs, key: descriptor.key)
            if comparison == .orderedSame {
                return (sourceOrder[lhsID] ?? 0) < (sourceOrder[rhsID] ?? 0)
            }
            return descriptor.ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
    }

    private static func compare(
        _ lhs: LibraryFrameQueryFacts,
        _ rhs: LibraryFrameQueryFacts,
        key: LibrarySortKey
    ) -> ComparisonResult {
        switch key {
        case .inputOrder, .fileSize:
            return .orderedSame
        case .time:
            return compareValues(lhs.scannedAt, rhs.scannedAt)
        case .name:
            return lhs.sortName.compare(
                rhs.sortName,
                options: [.numeric],
                range: nil,
                locale: Locale(identifier: "en_US_POSIX")
            )
        case .flag:
            return compareValues(flagRank(lhs.pickState), flagRank(rhs.pickState))
        case .rating:
            return compareValues(lhs.rating, rhs.rating)
        }
    }

    private static func makeFolderSections(
        _ orderedFrameIDs: [UUID],
        context: LibraryQueryContext
    ) -> [LibraryBrowserFolderSection] {
        let groups = Dictionary(grouping: orderedFrameIDs) { frameID in
            context.factsByFrameID[frameID]?.folderPath ?? ""
        }
        let knownIDs = Set(context.folderFacts.map(\.id))
        let knownSections = context.folderFacts.map { folder in
            return LibraryBrowserFolderSection(
                id: folder.id,
                folderID: folder.folderID,
                title: folder.title,
                orderedFrameIDs: groups[folder.id] ?? []
            )
        }
        let implicitSections = groups.keys
            .filter { !$0.isEmpty && !knownIDs.contains($0) }
            .sorted()
            .compactMap { path -> LibraryBrowserFolderSection? in
                guard let frameIDs = groups[path], !frameIDs.isEmpty else { return nil }
                let title = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
                return LibraryBrowserFolderSection(
                    id: path,
                    folderID: nil,
                    title: title.isEmpty ? path : title,
                    orderedFrameIDs: frameIDs
                )
            }
        return knownSections + implicitSections
    }

    private static func stableUnique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func compareValues<T: Comparable>(
        _ lhs: T,
        _ rhs: T
    ) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private static func flagRank(_ state: FramePickState) -> Int {
        switch state {
        case .picked: 0
        case .unflagged: 1
        case .rejected: 2
        }
    }
}

enum LibraryBrowserInteractionScope {
    static func frameIDs(
        viewMode: LibraryViewMode,
        selectedFolderID: String?,
        selectedFrameID: UUID?,
        projection: LibraryBrowserProjection
    ) -> [UUID] {
        guard viewMode.groupsByFolder else { return projection.orderedFrameIDs }
        let folderID = selectedFolderID
            ?? folderID(containing: selectedFrameID, projection: projection)
        guard let folderID,
              let section = projection.folderSections.first(where: { $0.id == folderID }) else {
            return []
        }
        return section.orderedFrameIDs
    }

    static func folderID(
        containing frameID: UUID?,
        projection: LibraryBrowserProjection
    ) -> String? {
        guard let frameID else { return nil }
        return projection.folderSections.first(where: {
            $0.orderedFrameIDs.contains(frameID)
        })?.id
    }
}
