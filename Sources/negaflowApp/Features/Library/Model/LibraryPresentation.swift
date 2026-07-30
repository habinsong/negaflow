import Foundation
import Chromabase

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case all
    case folders
    case filmType
    case offline

    var id: Self { self }

    var groupsByFolder: Bool {
        self == .folders || self == .filmType
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .all:
            return AppLocalization.text(AppLocalizedPhrase.libraryAllPhotos, language: language)
        case .folders:
            return AppLocalization.text(AppLocalizedPhrase.libraryFolders, language: language)
        case .filmType:
            return AppLocalization.text(AppLocalizedPhrase.libraryFilmType, language: language)
        case .offline:
            return AppLocalization.text(AppLocalizedPhrase.libraryOffline, language: language)
        }
    }

    func capsuleDisplayName(language: AppLanguage) -> String {
        switch self {
        case .all:
            return AppLocalization.text(AppLocalizedPhrase.libraryAllShort, language: language)
        case .folders, .filmType, .offline:
            return displayName(language: language)
        }
    }
}

enum LibrarySortKey: String, CaseIterable, Identifiable, Codable, Sendable {
    case inputOrder
    case time
    case name
    case flag
    case rating
    case fileSize

    var id: Self { self }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .inputOrder:
            return AppLocalization.text(AppLocalizedPhrase.sortInputOrder, language: language)
        case .time:
            return AppLocalization.text(AppLocalizedPhrase.sortTime, language: language)
        case .name:
            return AppLocalization.text(AppLocalizedPhrase.sortName, language: language)
        case .flag:
            return AppLocalization.text(AppLocalizedPhrase.sortFlag, language: language)
        case .rating:
            return AppLocalization.text(AppLocalizedPhrase.sortRating, language: language)
        case .fileSize:
            return AppLocalization.text(AppLocalizedPhrase.sortSize, language: language)
        }
    }
}

struct LibraryFolder: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let addedAt: Date

    init(id: UUID = UUID(), url: URL, addedAt: Date = Date()) {
        self.id = id
        self.url = url.standardizedFileURL
        self.addedAt = addedAt
    }

    var name: String {
        let last = url.lastPathComponent
        return last.isEmpty ? url.path : last
    }
}

struct LibraryFolderSection: Identifiable {
    let id: String
    let folder: LibraryFolder?
    let title: String
    let frames: [ScanFrame]
}

@MainActor
enum LibraryPresentation {
    static func sortedFrames(
        _ frames: [ScanFrame],
        key: LibrarySortKey,
        ascending: Bool
    ) -> [ScanFrame] {
        let frames = uniqueFramesPreservingOrder(frames)
        let order = Dictionary(uniqueKeysWithValues: frames.enumerated().map { ($0.element.id, $0.offset) })
        if key == .fileSize {
            return frames.sorted { lhs, rhs in
                switch (lhs.sourceFileSizeBytes, rhs.sourceFileSizeBytes) {
                case let (lhsSize?, rhsSize?) where lhsSize != rhsSize:
                    return ascending ? lhsSize < rhsSize : lhsSize > rhsSize
                case (nil, .some):
                    return false
                case (.some, nil):
                    return true
                default:
                    return (order[lhs.id] ?? 0) < (order[rhs.id] ?? 0)
                }
            }
        }
        let sorted = frames.sorted { lhs, rhs in
            let comparison = compare(lhs, rhs, key: key, order: order)
            if comparison == .orderedSame {
                return (order[lhs.id] ?? 0) < (order[rhs.id] ?? 0)
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        if key == .inputOrder {
            return ascending ? frames : frames.reversed()
        }
        return sorted
    }

    static func folderSections(
        frames: [ScanFrame],
        folders: [LibraryFolder],
        sortKey: LibrarySortKey,
        ascending: Bool
    ) -> [LibraryFolderSection] {
        let frames = uniqueFramesPreservingOrder(frames)
        let sortedFolders = folders.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let framesByFolderPath = Dictionary(grouping: frames) {
            normalizedFolderPath(folderURL(for: $0))
        }
        var seenPaths = Set<String>()
        var sections: [LibraryFolderSection] = []

        for folder in sortedFolders {
            let path = normalizedFolderPath(folder.url)
            seenPaths.insert(path)
            let folderFrames = framesByFolderPath[path] ?? []
            sections.append(
                LibraryFolderSection(
                    id: path,
                    folder: folder,
                    title: folder.name,
                    frames: sortedFrames(folderFrames, key: sortKey, ascending: ascending)
                )
            )
        }

        for path in framesByFolderPath.keys.sorted() where !seenPaths.contains(path) {
            let groupFrames = framesByFolderPath[path] ?? []
            let title = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
            sections.append(
                LibraryFolderSection(
                    id: path,
                    folder: nil,
                    title: title.isEmpty ? path : title,
                    frames: sortedFrames(groupFrames, key: sortKey, ascending: ascending)
                )
            )
        }

        return sections
    }

    static func projectedFolderSections(
        _ sections: [LibraryFolderSection],
        orderedFrameIDs: [UUID]?
    ) -> [LibraryFolderSection] {
        guard let orderedFrameIDs else { return sections }
        var resultOrder: [UUID: Int] = [:]
        for frameID in orderedFrameIDs where resultOrder[frameID] == nil {
            resultOrder[frameID] = resultOrder.count
        }
        let resultIDs = Set(resultOrder.keys)
        return sections.map { section in
            LibraryFolderSection(
                id: section.id,
                folder: section.folder,
                title: section.title,
                frames: section.frames
                    .filter { resultIDs.contains($0.id) }
                    .sorted {
                        (resultOrder[$0.id] ?? .max) < (resultOrder[$1.id] ?? .max)
                    }
            )
        }
    }

    static func visibleFolderSections(
        _ sections: [LibraryFolderSection],
        restrictedTo folderPaths: Set<String>?
    ) -> [LibraryFolderSection] {
        guard let folderPaths else { return sections }
        return sections.filter { folderPaths.contains($0.id) }
    }

    static func frameIDs(
        _ candidateFrameIDs: [UUID],
        storedUnder filmType: FilmType,
        framesByID: [UUID: ScanFrame]
    ) -> [UUID] {
        candidateFrameIDs.filter { frameID in
            guard let frame = framesByID[frameID] else { return false }
            return FrameStorageNaming.storedFilmType(forSourceURL: frame.rawScanURL) == filmType
        }
    }

    static func folderURL(for frame: ScanFrame) -> URL {
        frame.rawScanURL.deletingLastPathComponent().standardizedFileURL
    }

    nonisolated static func normalizedFolderPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func compare(
        _ lhs: ScanFrame,
        _ rhs: ScanFrame,
        key: LibrarySortKey,
        order: [UUID: Int]
    ) -> ComparisonResult {
        switch key {
        case .inputOrder:
            return compareValues(order[lhs.id] ?? 0, order[rhs.id] ?? 0)
        case .time:
            return compareValues(lhs.scannedAt, rhs.scannedAt)
        case .name:
            return lhs.displayName.localizedStandardCompare(rhs.displayName)
        case .flag:
            return compareValues(flagRank(lhs.pickState), flagRank(rhs.pickState))
        case .rating:
            return compareValues(lhs.rating, rhs.rating)
        case .fileSize:
            return .orderedSame
        }
    }

    private static func compareValues<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private static func flagRank(_ state: FramePickState) -> Int {
        switch state {
        case .picked:
            return 0
        case .unflagged:
            return 1
        case .rejected:
            return 2
        }
    }

    private static func uniqueFramesPreservingOrder(_ frames: [ScanFrame]) -> [ScanFrame] {
        let counts = Dictionary(grouping: frames, by: \.id).mapValues(\.count)
        return frames.filter { counts[$0.id] == 1 }
    }
}

extension ScanFrame {
    var sourceFileNameWithExtension: String {
        let name = rawScanURL.lastPathComponent
        return name.isEmpty ? displayName : name
    }

    var sourceFileBaseName: String? {
        let name = rawScanURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    var editableDisplayName: String {
        if assignedPhotoNumber != nil { return displayName }
        return literalCustomDisplayName ?? sourceFileBaseName ?? displayName
    }

    var sourceFileSizeBytes: Int64? {
        sourceMetadata?.fileSizeBytes
    }

    func renameDisplayName(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        customDisplayName = trimmed.isEmpty ? nil : trimmed
    }
}
