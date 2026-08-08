import Foundation

extension LibraryCatalogFile {
    static func prepareForUse(
        at url: URL,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL(),
        backupDirectory: URL = LibraryBackupStore.defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) -> LibraryCatalogOpenResult {
        if let migration = LibraryCatalogSQLiteMigration.migrateLegacyJSONIfNeeded(
            to: url,
            defectDirectory: defectDirectory,
            backupDirectory: backupDirectory,
            fileManager: fileManager
        ) {
            return migration
        }
        let primary = read(from: url, fileManager: fileManager)
        switch primary {
        case let .loaded(catalog, sourceVersion):
            let health = LibraryCatalogHealthInspector.inspect(
                catalog,
                defectDirectory: defectDirectory,
                fileManager: fileManager
            )
            guard health.canOpenSafely else {
                if let recovered = try? LibraryBackupStore.restoreLatest(
                    catalogURL: url,
                    defectDirectory: defectDirectory,
                    backupDirectory: backupDirectory,
                    fileManager: fileManager
                ) {
                    return finalizePreparedCatalog(
                        recovered,
                        at: url,
                        recoveredFromBackup: true,
                        fileManager: fileManager
                    )
                }
                return .blocked(openFailure(for: health))
            }
            return finalizePreparedCatalog(
                catalog,
                sourceVersion: sourceVersion,
                at: url,
                recoveredFromBackup: false,
                defectDirectory: defectDirectory,
                backupDirectory: backupDirectory,
                fileManager: fileManager
            )

        case let .unsupportedVersion(version):
            return .blocked(.unsupportedVersion(version))

        case let .unsupportedStorageVersion(version):
            return .blocked(.unsupportedStorageVersion(version))

        case .missing, .unreadable, .invalid:
            if let recovered = try? LibraryBackupStore.restoreLatest(
                catalogURL: url,
                defectDirectory: defectDirectory,
                backupDirectory: backupDirectory,
                fileManager: fileManager
            ) {
                return finalizePreparedCatalog(
                    recovered,
                    at: url,
                    recoveredFromBackup: true,
                    fileManager: fileManager
                )
            }

            let legacyBackup = read(from: backupURL(for: url), fileManager: fileManager)
            switch legacyBackup {
            case let .loaded(catalog, sourceVersion):
                let health = LibraryCatalogHealthInspector.inspect(
                    catalog,
                    defectDirectory: defectDirectory,
                    fileManager: fileManager
                )
                guard health.canOpenSafely else {
                    return .blocked(openFailure(for: health))
                }
                do {
                    _ = try LibraryBackupStore.createSnapshot(
                        catalogURL: backupURL(for: url),
                        defectDirectory: defectDirectory,
                        backupDirectory: backupDirectory,
                        fileManager: fileManager
                    )
                } catch {
                    return .blocked(.writeFailed)
                }
                guard preservePrimaryIfPresent(at: url, fileManager: fileManager),
                      writeAndVerify(catalog, to: url, fileManager: fileManager) else {
                    return .blocked(.writeFailed)
                }
                return .loaded(
                    catalog: catalog,
                    recoveredFromBackup: true,
                    migratedFromVersion: sourceVersion < LibraryCatalog.currentVersion
                        ? sourceVersion
                        : nil
                )
            case let .unsupportedVersion(version):
                return .blocked(.unsupportedVersion(version))
            case let .unsupportedStorageVersion(version):
                return .blocked(.unsupportedStorageVersion(version))
            case .invalid:
                return .blocked(.corrupt)
            case .unreadable:
                return .blocked(.unreadable)
            case .missing:
                switch primary {
                case .missing:
                    return hasRecoveryArtifacts(
                        defectDirectory: defectDirectory,
                        backupDirectory: backupDirectory,
                        fileManager: fileManager
                    ) ? .blocked(.missingAuthoritativeData) : .newLibrary
                case .unreadable:
                    return .blocked(.unreadable)
                case .invalid:
                    return .blocked(.corrupt)
                case .loaded, .unsupportedVersion:
                    preconditionFailure("handled above")
                case .unsupportedStorageVersion:
                    preconditionFailure("handled above")
                }
            }
        }
    }

    static func finalizePreparedCatalog(
        _ catalog: LibraryCatalog,
        sourceVersion: Int? = nil,
        at url: URL,
        recoveredFromBackup: Bool,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL(),
        backupDirectory: URL = LibraryBackupStore.defaultDirectoryURL(),
        fileManager: FileManager
    ) -> LibraryCatalogOpenResult {
        let resolvedSourceVersion: Int
        if let sourceVersion {
            resolvedSourceVersion = sourceVersion
        } else {
            guard case let .loaded(_, version) = read(from: url, fileManager: fileManager) else {
                return .blocked(.writeFailed)
            }
            resolvedSourceVersion = version
        }

        let migratedFromVersion = resolvedSourceVersion < LibraryCatalog.currentVersion
            ? resolvedSourceVersion
            : nil
        if migratedFromVersion != nil {
            if !recoveredFromBackup {
                do {
                    _ = try LibraryBackupStore.createSnapshot(
                        catalogURL: url,
                        defectDirectory: defectDirectory,
                        backupDirectory: backupDirectory,
                        fileManager: fileManager
                    )
                    let legacyURL = backupURL(for: url)
                    if case let .loaded(legacy, _) = read(
                        from: legacyURL,
                        fileManager: fileManager
                    ), LibraryBackupStore.hasValidAuthoritativeData(
                        for: legacy,
                        defectDirectory: defectDirectory
                    ) {
                        _ = try LibraryBackupStore.createSnapshot(
                            catalogURL: legacyURL,
                            defectDirectory: defectDirectory,
                            backupDirectory: backupDirectory,
                            fileManager: fileManager
                        )
                    }
                } catch {
                    return .blocked(.writeFailed)
                }
            }
            guard writeAndVerify(catalog, to: url, fileManager: fileManager) else {
                return .blocked(.writeFailed)
            }
        }
        if LibraryCatalogSQLiteStore.isSQLiteURL(url) {
            LibraryCatalogSQLiteWriteCache.shared.markSafetyValidated(
                catalog,
                for: url,
                fileManager: fileManager
            )
        }
        return .loaded(
            catalog: catalog,
            recoveredFromBackup: recoveredFromBackup,
            migratedFromVersion: migratedFromVersion
        )
    }

    static func preservePrimaryIfPresent(
        at url: URL,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return true }
        let preserved = url.deletingLastPathComponent().appendingPathComponent(
            "library.unreadable-\(UUID().uuidString).json"
        )
        do {
            try fileManager.copyItem(at: url, to: preserved)
            return true
        } catch {
            return false
        }
    }

    static func writeAndVerify(
        _ catalog: LibraryCatalog,
        to url: URL,
        fileManager: FileManager
    ) -> Bool {
        guard writeCatalogSync(catalog, to: url),
              case let .loaded(persisted, sourceVersion) = read(
                from: url,
                fileManager: fileManager
              ),
              sourceVersion == LibraryCatalog.currentVersion,
              canonicalData(persisted) == canonicalData(catalog) else {
            return false
        }
        if LibraryCatalogSQLiteStore.isSQLiteURL(url) {
            LibraryCatalogSQLiteWriteCache.shared.markSafetyValidated(
                persisted,
                for: url,
                fileManager: fileManager
            )
        }
        return true
    }

    static func canonicalData(_ catalog: LibraryCatalog) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(catalog)
    }

    static func hasRecoveryArtifacts(
        defectDirectory: URL,
        backupDirectory: URL,
        fileManager: FileManager
    ) -> Bool {
        [defectDirectory, backupDirectory].contains { directory in
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { return false }
            return !contents.isEmpty
        }
    }

    static func openFailure(
        for health: LibraryCatalogHealthReport
    ) -> LibraryCatalogOpenFailure {
        let authoritativeCodes: Set<LibraryCatalogHealthIssueCode> = [
            .missingDefectRecipe,
            .invalidDefectRecipe,
        ]
        let errorCodes = Set(
            health.issues
                .filter { $0.severity == .error }
                .map(\.code)
        )
        return !errorCodes.isEmpty && errorCodes.isSubset(of: authoritativeCodes)
            ? .missingAuthoritativeData
            : .corrupt
    }


}
