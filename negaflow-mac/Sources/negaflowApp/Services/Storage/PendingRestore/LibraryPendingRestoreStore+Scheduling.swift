import Foundation

extension LibraryPendingRestoreStore {
    static func defaultDirectoryURL(for catalogURL: URL) -> URL {
        catalogURL.deletingLastPathComponent()
            .appendingPathComponent("PendingRestore", isDirectory: true)
    }

    static func markerURL(for catalogURL: URL) -> URL {
        defaultDirectoryURL(for: catalogURL).appendingPathComponent("pending-restore.json")
    }

    static func pendingMarker(
        for catalogURL: URL,
        fileManager: FileManager = .default
    ) -> LibraryPendingRestoreMarker? {
        guard let data = try? Data(contentsOf: markerURL(for: catalogURL)),
              let marker = try? LibraryPendingRestoreMarkerCodec.decode(data),
              supportedMarkerVersion(marker.version),
              marker.effectivePhase == .scheduled,
              validPendingDirectoryName(marker.directoryName) else { return nil }
        let directory = defaultDirectoryURL(for: catalogURL)
            .appendingPathComponent(marker.directoryName, isDirectory: true)
        guard LibraryBackupStore.validateSnapshotDirectory(
            at: directory,
            fileManager: fileManager
        ) != nil else { return nil }
        return marker
    }

    @discardableResult
    static func schedule(
        generationID: String,
        catalogURL: URL,
        backupDirectory: URL = LibraryBackupStore.defaultDirectoryURL(),
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> LibraryPendingRestoreMarker {
        guard let snapshot = LibraryBackupStore.validatedSnapshot(
            generationID: generationID,
            in: backupDirectory,
            fileManager: fileManager
        ) else {
            throw LibraryPendingRestoreError.invalidGeneration
        }
        let root = defaultDirectoryURL(for: catalogURL)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let previousMarker = rawMarker(for: catalogURL)
        let staging = root.appendingPathComponent(
            "staging-\(UUID().uuidString).tmp",
            isDirectory: true
        )
        let destinationName = "restore-\(UUID().uuidString)"
        let destination = root.appendingPathComponent(destinationName, isDirectory: true)
        var committedDirectory = false
        defer {
            if !committedDirectory { try? fileManager.removeItem(at: staging) }
        }

        try copySnapshot(snapshot, to: staging, fileManager: fileManager)
        guard LibraryBackupStore.validateSnapshotDirectory(
            at: staging,
            fileManager: fileManager
        ) != nil else {
            throw LibraryPendingRestoreError.invalidPendingSnapshot
        }
        try fileManager.moveItem(at: staging, to: destination)
        committedDirectory = true

        let marker = LibraryPendingRestoreMarker(
            directoryName: destinationName,
            sourceGenerationID: generationID,
            scheduledAt: now,
            phase: .scheduled
        )
        do {
            try LibraryPendingRestoreMarkerCodec.encode(marker).write(
                to: markerURL(for: catalogURL),
                options: .atomic
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        if let previousMarker,
           previousMarker.directoryName != destinationName,
           validPendingDirectoryName(previousMarker.directoryName) {
            try? fileManager.removeItem(
                at: root.appendingPathComponent(
                    previousMarker.directoryName,
                    isDirectory: true
                )
            )
        }
        guard let persistedMarker = rawMarker(for: catalogURL) else {
            throw LibraryPendingRestoreError.invalidMarker
        }
        return persistedMarker
    }

    static func cancel(
        catalogURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let marker = rawMarker(for: catalogURL)
        let markerURL = markerURL(for: catalogURL)
        if fileManager.fileExists(atPath: markerURL.path) {
            try fileManager.removeItem(at: markerURL)
        }
        if let marker, validPendingDirectoryName(marker.directoryName) {
            try? fileManager.removeItem(
                at: defaultDirectoryURL(for: catalogURL).appendingPathComponent(
                    marker.directoryName,
                    isDirectory: true
                )
            )
        }
    }

}
