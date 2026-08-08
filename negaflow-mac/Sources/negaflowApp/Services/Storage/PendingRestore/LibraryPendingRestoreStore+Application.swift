import Foundation

extension LibraryPendingRestoreStore {
    static func applyIfScheduled(
        catalogURL: URL,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL(),
        backupDirectory: URL = LibraryBackupStore.defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) throws -> LibraryPendingRestoreApplication {
        try applyIfScheduled(
            catalogURL: catalogURL,
            defectDirectory: defectDirectory,
            backupDirectory: backupDirectory,
            fileManager: fileManager,
            cleanup: .fileSystem(fileManager: fileManager)
        )
    }

    static func applyIfScheduled(
        catalogURL: URL,
        defectDirectory: URL,
        backupDirectory: URL,
        fileManager: FileManager,
        cleanup: LibraryPendingRestoreCleanup
    ) throws -> LibraryPendingRestoreApplication {
        let markerURL = markerURL(for: catalogURL)
        guard fileManager.fileExists(atPath: markerURL.path) else { return .none }
        guard let marker = rawMarker(for: catalogURL),
              supportedMarkerVersion(marker.version),
              validPendingDirectoryName(marker.directoryName) else {
            throw LibraryPendingRestoreError.invalidMarker
        }
        if marker.effectivePhase == .applied {
            return cleanup.run(
                marker: marker,
                catalogURL: catalogURL,
                fileManager: fileManager
            ) ? .cleanupOnly(sourceGenerationID: marker.sourceGenerationID)
              : .cleanupPending(
                  sourceGenerationID: marker.sourceGenerationID,
                  didApplyRestore: false
              )
        }
        let pendingDirectory = defaultDirectoryURL(for: catalogURL)
            .appendingPathComponent(marker.directoryName, isDirectory: true)
        guard let snapshot = LibraryBackupStore.validateSnapshotDirectory(
            at: pendingDirectory,
            fileManager: fileManager
        ) else {
            throw LibraryPendingRestoreError.invalidPendingSnapshot
        }

        let currentRead = LibraryCatalogFile.read(from: catalogURL, fileManager: fileManager)
        if case let .unsupportedVersion(version) = currentRead {
            throw LibraryPendingRestoreError.unsupportedCurrentCatalog(version)
        }
        try preserveCurrentState(
            currentRead: currentRead,
            catalogURL: catalogURL,
            defectDirectory: defectDirectory,
            backupDirectory: backupDirectory,
            fileManager: fileManager
        )
        try apply(
            snapshot: snapshot,
            catalogURL: catalogURL,
            defectDirectory: defectDirectory,
            fileManager: fileManager
        )
        var appliedMarker = marker
        appliedMarker.version = LibraryPendingRestoreMarker.currentVersion
        appliedMarker.phase = .applied
        try LibraryPendingRestoreMarkerCodec.encode(appliedMarker).write(
            to: markerURL,
            options: .atomic
        )
        guard rawMarker(for: catalogURL)?.effectivePhase == .applied else {
            throw LibraryPendingRestoreError.invalidMarker
        }
        return cleanup.run(
            marker: appliedMarker,
            catalogURL: catalogURL,
            fileManager: fileManager
        ) ? .applied(sourceGenerationID: marker.sourceGenerationID)
          : .cleanupPending(
              sourceGenerationID: marker.sourceGenerationID,
              didApplyRestore: true
          )
    }

}
