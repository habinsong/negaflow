import Foundation

struct LibraryBackupVolumeInfo: Equatable {
    let identifier: String
    let name: String
    let availableBytes: Int64
    let totalBytes: Int64
    let isWritable: Bool
}

enum LibraryBackupDestinationStatus: Equatable {
    case notConfigured
    case disconnected(URL)
    case sameVolume(LibraryBackupVolumeInfo)
    case readOnly(LibraryBackupVolumeInfo)
    case insufficientCapacity(info: LibraryBackupVolumeInfo, requiredBytes: Int64)
    case ready(LibraryBackupVolumeInfo)

    var readyInfo: LibraryBackupVolumeInfo? {
        guard case let .ready(info) = self else { return nil }
        return info
    }
}

enum LibraryBackupVolumeInspector {
    static func inspect(_ url: URL, fileManager: FileManager = .default) -> LibraryBackupVolumeInfo? {
        guard let existingURL = existingAncestor(of: url, fileManager: fileManager) else { return nil }
        let keys: Set<URLResourceKey> = [
            .volumeIdentifierKey,
            .volumeNameKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
            .isWritableKey,
        ]
        guard let values = try? existingURL.resourceValues(forKeys: keys),
              let identifier = values.volumeIdentifier else { return nil }
        return LibraryBackupVolumeInfo(
            identifier: String(describing: identifier),
            name: values.volumeName ?? existingURL.path,
            availableBytes: values.volumeAvailableCapacityForImportantUsage
                ?? Int64(values.volumeTotalCapacity ?? 0),
            totalBytes: Int64(values.volumeTotalCapacity ?? 0),
            isWritable: values.isWritable == true
        )
    }

    private static func existingAncestor(of url: URL, fileManager: FileManager) -> URL? {
        var candidate = url.standardizedFileURL
        while candidate.path != "/" && !fileManager.fileExists(atPath: candidate.path) {
            candidate.deleteLastPathComponent()
        }
        return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
    }
}

enum LibraryBackupDestinationValidator {
    static func evaluate(
        catalogURL: URL,
        destinationURL: URL,
        requiredBytes: Int64,
        fileManager: FileManager = .default,
        inspectVolume: (URL) -> LibraryBackupVolumeInfo?
    ) -> LibraryBackupDestinationStatus {
        guard fileManager.fileExists(atPath: destinationURL.path),
              let destination = inspectVolume(destinationURL) else {
            return .disconnected(destinationURL)
        }
        guard let source = inspectVolume(catalogURL.deletingLastPathComponent()) else {
            return .disconnected(destinationURL)
        }
        guard source.identifier != destination.identifier else {
            return .sameVolume(destination)
        }
        guard destination.isWritable else { return .readOnly(destination) }
        guard destination.availableBytes >= max(requiredBytes, 0) else {
            return .insufficientCapacity(info: destination, requiredBytes: max(requiredBytes, 0))
        }
        return .ready(destination)
    }
}
