import Foundation

enum ScanStorageKind: Equatable {
    case local
    case cloudManaged
}

struct ScanStorageLocationStatus: Equatable {
    let availableCapacityBytes: Int64?
    let kind: ScanStorageKind
}

enum ScanStorageLocationInspector {
    static func inspect(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> ScanStorageLocationStatus {
        let existing = nearestExistingAncestor(of: url, fileManager: fileManager)
        let values = try? existing.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .isUbiquitousItemKey,
        ])
        let available = values?.volumeAvailableCapacityForImportantUsage
            ?? values?.volumeAvailableCapacity.map(Int64.init)
        let cloudManaged = values?.isUbiquitousItem == true
            || isCloudManagedPath(url)
        return ScanStorageLocationStatus(
            availableCapacityBytes: available,
            kind: cloudManaged ? .cloudManaged : .local
        )
    }

    static func isCloudManagedPath(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.contains("/Library/Mobile Documents/")
            || path.contains("/Library/CloudStorage/")
    }

    private static func nearestExistingAncestor(
        of url: URL,
        fileManager: FileManager
    ) -> URL {
        var candidate = url.standardizedFileURL
        while !fileManager.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { break }
            candidate = parent
        }
        return candidate
    }
}
