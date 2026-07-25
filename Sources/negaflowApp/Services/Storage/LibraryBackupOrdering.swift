import Foundation

enum LibraryBackupOrdering {
    typealias ManifestLoader = (URL) -> LibraryBackupManifest?

    static func nextSequence(
        in backupDirectory: URL,
        fileManager: FileManager,
        loadManifest: ManifestLoader
    ) throws -> UInt64 {
        let urls = (try? fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let maximum = urls.compactMap { url -> UInt64? in
            guard url.lastPathComponent.hasPrefix("backup-"),
                  let manifest = loadManifest(url) else { return nil }
            return manifest.sequence
        }.max() ?? 0
        guard maximum < UInt64.max else { throw LibraryBackupError.sequenceExhausted }
        return maximum + 1
    }

    static func isNewerSnapshot(
        _ lhs: LibraryBackupSnapshot,
        _ rhs: LibraryBackupSnapshot
    ) -> Bool {
        isNewer(
            leftSequence: lhs.manifest.sequence,
            leftDate: lhs.manifest.createdAt,
            leftID: lhs.directoryURL.lastPathComponent,
            rightSequence: rhs.manifest.sequence,
            rightDate: rhs.manifest.createdAt,
            rightID: rhs.directoryURL.lastPathComponent
        )
    }

    static func isNewerGeneration(
        _ lhs: LibraryBackupGeneration,
        _ rhs: LibraryBackupGeneration
    ) -> Bool {
        isNewer(
            leftSequence: lhs.sequence,
            leftDate: lhs.createdAt ?? .distantPast,
            leftID: lhs.id,
            rightSequence: rhs.sequence,
            rightDate: rhs.createdAt ?? .distantPast,
            rightID: rhs.id
        )
    }

    private static func isNewer(
        leftSequence: UInt64?,
        leftDate: Date,
        leftID: String,
        rightSequence: UInt64?,
        rightDate: Date,
        rightID: String
    ) -> Bool {
        switch (leftSequence, rightSequence) {
        case let (left?, right?) where left != right: return left > right
        case (_?, nil): return true
        case (nil, _?): return false
        default:
            if leftDate != rightDate { return leftDate > rightDate }
            return leftID > rightID
        }
    }
}
