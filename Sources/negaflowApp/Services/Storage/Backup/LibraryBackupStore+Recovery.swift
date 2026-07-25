import Foundation
import CryptoKit

extension LibraryBackupStore {
    static func preserveUnsafeState(
        catalogURL: URL,
        defectDirectory: URL,
        fileManager: FileManager
    ) throws {
        let identifier = UUID().uuidString
        let parent = catalogURL.deletingLastPathComponent()
        let catalogExtension = catalogURL.pathExtension.isEmpty
            ? ""
            : ".\(catalogURL.pathExtension)"
        let preservedCatalog = parent.appendingPathComponent(
            "library.corrupt-\(identifier)\(catalogExtension)"
        )
        let preservedDefects = parent.appendingPathComponent(
            "defects.corrupt-\(identifier)",
            isDirectory: true
        )
        var created: [URL] = []
        do {
            if fileManager.fileExists(atPath: catalogURL.path) {
                try fileManager.copyItem(at: catalogURL, to: preservedCatalog)
                created.append(preservedCatalog)
            }
            if fileManager.fileExists(atPath: defectDirectory.path) {
                try fileManager.copyItem(at: defectDirectory, to: preservedDefects)
                created.append(preservedDefects)
            }
        } catch {
            for url in created.reversed() {
                try? fileManager.removeItem(at: url)
            }
            throw error
        }
    }

    static func applySnapshot(
        _ snapshot: LibraryBackupSnapshot,
        catalogData: Data,
        catalogURL: URL,
        defectDirectory: URL,
        fileManager: FileManager
    ) throws {
        let defectParent = defectDirectory.deletingLastPathComponent()
        let catalogParent = catalogURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: defectParent, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: catalogParent, withIntermediateDirectories: true)

        let identifier = UUID().uuidString
        let replacementDefects = defectParent.appendingPathComponent(
            ".restore-defects-\(identifier)",
            isDirectory: true
        )
        let previousDefects = defectParent.appendingPathComponent(
            ".previous-defects-\(identifier)",
            isDirectory: true
        )
        let previousCatalog = catalogParent.appendingPathComponent(
            ".previous-library-\(identifier)\(catalogURL.pathExtension.isEmpty ? "" : ".\(catalogURL.pathExtension)")"
        )
        let hadCatalog = fileManager.fileExists(atPath: catalogURL.path)
        let hadDefects = fileManager.fileExists(atPath: defectDirectory.path)
        var movedPreviousDefects = false
        var installedReplacementDefects = false
        var catalogWriteAttempted = false

        try fileManager.createDirectory(
            at: replacementDefects,
            withIntermediateDirectories: true
        )
        defer {
            if fileManager.fileExists(atPath: replacementDefects.path) {
                try? fileManager.removeItem(at: replacementDefects)
            }
        }

        let snapshotDefects = defectsDirectory(in: snapshot.directoryURL)
        for frameID in snapshot.manifest.defectFrameIDs {
            let source = DefectSidecarFile.url(for: frameID, in: snapshotDefects)
            let destination = DefectSidecarFile.url(for: frameID, in: replacementDefects)
            let data = try Data(contentsOf: source)
            try data.write(to: destination, options: .atomic)
        }
        guard LibraryCatalogHealthInspector.inspect(
            snapshot.catalog,
            defectDirectory: replacementDefects,
            fileManager: fileManager
        ).canOpenSafely else {
            throw LibraryBackupError.invalidSnapshot
        }

        if hadCatalog {
            try fileManager.copyItem(at: catalogURL, to: previousCatalog)
        }

        do {
            if hadDefects {
                try fileManager.moveItem(at: defectDirectory, to: previousDefects)
                movedPreviousDefects = true
            }
            try fileManager.moveItem(at: replacementDefects, to: defectDirectory)
            installedReplacementDefects = true

            catalogWriteAttempted = true
            if hadCatalog {
                try fileManager.removeItem(at: catalogURL)
            }
            guard LibraryCatalogFile.writeSync(catalogData, to: catalogURL),
                  case let .loaded(appliedCatalog, sourceVersion) = LibraryCatalogFile.read(
                    from: catalogURL,
                    fileManager: fileManager
                  ),
                  sourceVersion == LibraryCatalog.currentVersion,
                  LibraryCatalogFile.canonicalData(appliedCatalog)
                    == LibraryCatalogFile.canonicalData(snapshot.catalog),
                  LibraryCatalogHealthInspector.inspect(
                    appliedCatalog,
                    defectDirectory: defectDirectory,
                    fileManager: fileManager
                  ).canOpenSafely else {
                throw LibraryBackupError.invalidSnapshot
            }

            if movedPreviousDefects {
                try? fileManager.removeItem(at: previousDefects)
            }
            if hadCatalog {
                try? fileManager.removeItem(at: previousCatalog)
            }
        } catch {
            if catalogWriteAttempted {
                if fileManager.fileExists(atPath: catalogURL.path) {
                    try? fileManager.removeItem(at: catalogURL)
                }
                if hadCatalog, fileManager.fileExists(atPath: previousCatalog.path) {
                    try? fileManager.moveItem(at: previousCatalog, to: catalogURL)
                }
            } else if hadCatalog, fileManager.fileExists(atPath: previousCatalog.path) {
                try? fileManager.removeItem(at: previousCatalog)
            }
            if installedReplacementDefects,
               fileManager.fileExists(atPath: defectDirectory.path) {
                try? fileManager.removeItem(at: defectDirectory)
            }
            if movedPreviousDefects,
               fileManager.fileExists(atPath: previousDefects.path) {
                try? fileManager.moveItem(at: previousDefects, to: defectDirectory)
            }
            throw error
        }
    }


}
