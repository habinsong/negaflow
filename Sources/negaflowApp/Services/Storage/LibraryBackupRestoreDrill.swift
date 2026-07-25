import Foundation

struct LibraryBackupRestoreDrillResult: Codable, Equatable, Sendable {
    let generationID: String
    let verifiedAt: Date
    let succeeded: Bool
}

enum LibraryBackupRestoreDrill {
    static func verify(
        generationURL: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> LibraryBackupRestoreDrillResult {
        let failed = LibraryBackupRestoreDrillResult(
            generationID: generationURL.lastPathComponent,
            verifiedAt: now,
            succeeded: false
        )
        guard let source = LibraryBackupStore.validateSnapshotDirectory(
            at: generationURL,
            fileManager: fileManager
        ) else { return failed }

        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "negaflow-restore-drill-\(UUID().uuidString)", isDirectory: true
        )
        defer { try? fileManager.removeItem(at: root) }
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        let copiedGeneration = backupRoot.appendingPathComponent(
            generationURL.lastPathComponent, isDirectory: true
        )
        let liveRoot = root.appendingPathComponent("live", isDirectory: true)
        let catalogURL = liveRoot.appendingPathComponent("library.json")
        let defectDirectory = liveRoot.appendingPathComponent("defects", isDirectory: true)

        do {
            try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
            try fileManager.copyItem(at: generationURL, to: copiedGeneration)
            guard let restored = try LibraryBackupStore.restoreLatest(
                catalogURL: catalogURL,
                defectDirectory: defectDirectory,
                backupDirectory: backupRoot,
                fileManager: fileManager
            ),
            restored.frames.count == source.catalog.frames.count,
            LibraryCatalogHealthInspector.inspect(
                restored,
                defectDirectory: defectDirectory,
                fileManager: fileManager
            ).canOpenSafely,
            LibraryBackupStore.hasValidAuthoritativeData(
                for: restored,
                defectDirectory: defectDirectory
            ) else { return failed }
            return LibraryBackupRestoreDrillResult(
                generationID: generationURL.lastPathComponent,
                verifiedAt: now,
                succeeded: true
            )
        } catch {
            return failed
        }
    }
}
