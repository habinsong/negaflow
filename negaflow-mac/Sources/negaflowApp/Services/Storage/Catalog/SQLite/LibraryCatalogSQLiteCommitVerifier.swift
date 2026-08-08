import Foundation

extension LibraryCatalogFile {
    private struct SQLitePrimarySnapshot {
        let existed: Bool
        let copyURL: URL?
    }

    static func commitAndVerifySQLite(
        _ catalog: LibraryCatalog,
        to url: URL,
        defectDirectory: URL,
        fileManager: FileManager,
        catalogSafetyValidated: Bool
    ) -> Result<Void, LibraryCatalogCommitError> {
        if !catalogSafetyValidated {
            let validatedPreviousCatalog = LibraryCatalogSQLiteWriteCache.shared
                .safetyValidatedCatalog(for: url, fileManager: fileManager)
            let health = LibraryCatalogHealthInspector.inspect(
                catalog,
                defectDirectory: defectDirectory,
                fileManager: fileManager,
                includeWarnings: false,
                validatedPreviousCatalog: validatedPreviousCatalog
            )
            guard health.canOpenSafely else { return .failure(.invalidCatalog) }
        }

        let previousCatalog = LibraryCatalogSQLiteWriteCache.shared.currentCatalog(
            for: url,
            fileManager: fileManager
        )
        let snapshot: SQLitePrimarySnapshot
        do {
            snapshot = try makeSQLitePrimarySnapshot(at: url, fileManager: fileManager)
        } catch {
            return .failure(.writeFailed)
        }
        defer {
            if let copyURL = snapshot.copyURL { try? fileManager.removeItem(at: copyURL) }
        }

        guard writeCatalog(catalog, to: url, fileManager: fileManager) else {
            return restoreSQLitePrimary(snapshot, at: url, fileManager: fileManager)
                ? .failure(.writeFailed)
                : .failure(.rollbackFailed)
        }

        let verified: Bool
        if let previousCatalog,
           LibraryCatalogSQLiteIncrementalVerifier.canVerify(
               catalog,
               from: previousCatalog
           ) {
            verified = LibraryCatalogSQLiteIncrementalVerifier.verify(
                catalog,
                from: previousCatalog,
                at: url
            )
        } else {
            verified = sqliteReadbackMatches(
                catalog,
                at: url,
                defectDirectory: defectDirectory,
                fileManager: fileManager
            )
        }
        guard verified else {
            return restoreSQLitePrimary(snapshot, at: url, fileManager: fileManager)
                ? .failure(.readbackFailed)
                : .failure(.rollbackFailed)
        }
        LibraryCatalogSQLiteWriteCache.shared.markSafetyValidated(
            catalog,
            for: url,
            fileManager: fileManager
        )
        return .success(())
    }

    private static func sqliteReadbackMatches(
        _ catalog: LibraryCatalog,
        at url: URL,
        defectDirectory: URL,
        fileManager: FileManager
    ) -> Bool {
        guard case let .loaded(persisted, sourceVersion) = read(from: url, fileManager: fileManager),
              sourceVersion == LibraryCatalog.currentVersion else {
            return false
        }
        let payloadMatches = persisted == catalog
            || canonicalData(persisted) == canonicalData(catalog)
        return payloadMatches
            && LibraryCatalogHealthInspector.inspect(
                persisted,
                defectDirectory: defectDirectory,
                fileManager: fileManager,
                includeWarnings: false
            ).canOpenSafely
    }

    private static func makeSQLitePrimarySnapshot(
        at url: URL,
        fileManager: FileManager
    ) throws -> SQLitePrimarySnapshot {
        guard fileManager.fileExists(atPath: url.path) else {
            return SQLitePrimarySnapshot(existed: false, copyURL: nil)
        }
        let copyURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).rollback"
        )
        do {
            try fileManager.copyItem(at: url, to: copyURL)
            guard fileManager.contentsEqual(atPath: url.path, andPath: copyURL.path) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return SQLitePrimarySnapshot(existed: true, copyURL: copyURL)
        } catch {
            try? fileManager.removeItem(at: copyURL)
            throw error
        }
    }

    private static func restoreSQLitePrimary(
        _ snapshot: SQLitePrimarySnapshot,
        at url: URL,
        fileManager: FileManager
    ) -> Bool {
        LibraryCatalogSQLiteWriteCache.shared.remove(url)
        do {
            guard snapshot.existed else {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
                return !fileManager.fileExists(atPath: url.path)
            }
            guard let copyURL = snapshot.copyURL else { return false }
            let restorationURL = url.deletingLastPathComponent().appendingPathComponent(
                ".\(url.lastPathComponent).\(UUID().uuidString).restoring"
            )
            defer { try? fileManager.removeItem(at: restorationURL) }
            try fileManager.copyItem(at: copyURL, to: restorationURL)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(
                    url,
                    withItemAt: restorationURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try fileManager.moveItem(at: restorationURL, to: url)
            }
            return fileManager.contentsEqual(atPath: url.path, andPath: copyURL.path)
        } catch {
            return false
        }
    }
}
