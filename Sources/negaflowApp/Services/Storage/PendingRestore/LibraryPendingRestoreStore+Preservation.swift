import Foundation

extension LibraryPendingRestoreStore {
    static func preserveCurrentState(
        currentRead: LibraryCatalogReadResult,
        catalogURL: URL,
        defectDirectory: URL,
        backupDirectory: URL,
        fileManager: FileManager
    ) throws {
        switch currentRead {
        case let .loaded(catalog, _):
            let health = LibraryCatalogHealthInspector.inspect(
                catalog,
                defectDirectory: defectDirectory,
                fileManager: fileManager
            )
            if health.canOpenSafely {
                do {
                    _ = try LibraryBackupStore.createSnapshot(
                        catalogURL: catalogURL,
                        defectDirectory: defectDirectory,
                        backupDirectory: backupDirectory,
                        fileManager: fileManager
                    )
                    return
                } catch {
                    throw LibraryPendingRestoreError.safetyBackupFailed
                }
            }
            try preserveUnsafeState(
                catalogURL: catalogURL,
                defectDirectory: defectDirectory,
                fileManager: fileManager
            )
        case .missing:
            if directoryHasFiles(defectDirectory, fileManager: fileManager) {
                try preserveUnsafeState(
                    catalogURL: catalogURL,
                    defectDirectory: defectDirectory,
                    fileManager: fileManager
                )
            }
        case .unreadable, .invalid:
            try preserveUnsafeState(
                catalogURL: catalogURL,
                defectDirectory: defectDirectory,
                fileManager: fileManager
            )
        case let .unsupportedVersion(version):
            throw LibraryPendingRestoreError.unsupportedCurrentCatalog(version)
        case let .unsupportedStorageVersion(version):
            throw LibraryPendingRestoreError.unsupportedCurrentCatalog(version)
        }
    }

    static func preserveUnsafeState(
        catalogURL: URL,
        defectDirectory: URL,
        fileManager: FileManager
    ) throws {
        let root = catalogURL.deletingLastPathComponent()
            .appendingPathComponent("RestoreRollbacks", isDirectory: true)
        let destination = root.appendingPathComponent(
            "rollback-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: catalogURL.path) {
                try fileManager.copyItem(
                    at: catalogURL,
                    to: destination.appendingPathComponent(catalogURL.lastPathComponent)
                )
            }
            if fileManager.fileExists(atPath: defectDirectory.path) {
                try fileManager.copyItem(
                    at: defectDirectory,
                    to: destination.appendingPathComponent("defects", isDirectory: true)
                )
            }
        } catch {
            try? fileManager.removeItem(at: destination)
            throw LibraryPendingRestoreError.safetyBackupFailed
        }
    }

    static func apply(
        snapshot: LibraryBackupSnapshot,
        catalogURL: URL,
        defectDirectory: URL,
        fileManager: FileManager
    ) throws {
        guard let catalogData = LibraryCatalogFile.encode(snapshot.catalog) else {
            throw LibraryPendingRestoreError.applyFailed
        }
        let defectParent = defectDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: defectParent, withIntermediateDirectories: true)
        let replacement = defectParent.appendingPathComponent(
            ".restore-defects-\(UUID().uuidString)",
            isDirectory: true
        )
        let previous = defectParent.appendingPathComponent(
            ".previous-defects-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: replacement, withIntermediateDirectories: true)
        var movedPrevious = false
        var installedReplacement = false
        let originalCatalogData = try? Data(contentsOf: catalogURL)
        defer {
            if fileManager.fileExists(atPath: replacement.path) {
                try? fileManager.removeItem(at: replacement)
            }
            if fileManager.fileExists(atPath: previous.path) {
                try? fileManager.removeItem(at: previous)
            }
        }

        do {
            for frameID in snapshot.manifest.defectFrameIDs {
                try fileManager.copyItem(
                    at: DefectSidecarFile.url(
                        for: frameID,
                        in: snapshot.directoryURL.appendingPathComponent("defects", isDirectory: true)
                    ),
                    to: DefectSidecarFile.url(for: frameID, in: replacement)
                )
            }
            guard LibraryCatalogHealthInspector.inspect(
                snapshot.catalog,
                defectDirectory: replacement,
                fileManager: fileManager
            ).canOpenSafely else {
                throw LibraryPendingRestoreError.applyFailed
            }
            if fileManager.fileExists(atPath: defectDirectory.path) {
                try fileManager.moveItem(at: defectDirectory, to: previous)
                movedPrevious = true
            }
            try fileManager.moveItem(at: replacement, to: defectDirectory)
            installedReplacement = true
            guard LibraryCatalogFile.writeSync(catalogData, to: catalogURL),
                  case let .loaded(applied, sourceVersion) = LibraryCatalogFile.read(
                    from: catalogURL,
                    fileManager: fileManager
                  ),
                  sourceVersion == LibraryCatalog.currentVersion,
                  LibraryCatalogHealthInspector.inspect(
                    applied,
                    defectDirectory: defectDirectory,
                    fileManager: fileManager
                  ).canOpenSafely else {
                throw LibraryPendingRestoreError.applyFailed
            }
            if movedPrevious { try? fileManager.removeItem(at: previous) }
        } catch {
            if installedReplacement, fileManager.fileExists(atPath: defectDirectory.path) {
                try? fileManager.removeItem(at: defectDirectory)
            }
            if movedPrevious, fileManager.fileExists(atPath: previous.path) {
                try? fileManager.moveItem(at: previous, to: defectDirectory)
            }
            if let originalCatalogData {
                try? originalCatalogData.write(to: catalogURL, options: .atomic)
            } else if fileManager.fileExists(atPath: catalogURL.path) {
                try? fileManager.removeItem(at: catalogURL)
            }
            throw error
        }
    }

}
