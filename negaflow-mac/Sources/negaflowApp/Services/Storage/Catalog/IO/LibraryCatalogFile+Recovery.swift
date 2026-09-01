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
            if health.canOpenSafely {
                return finalizePreparedCatalog(
                    catalog,
                    sourceVersion: sourceVersion,
                    at: url,
                    recoveredFromBackup: false,
                    defectDirectory: defectDirectory,
                    backupDirectory: backupDirectory,
                    fileManager: fileManager
                )
            }
            // 되돌릴 수 있는 어긋남만 있으면 백업으로 물러나기 전에 카탈로그 안에서 고친다.
            // 사진은 그대로 두고 소속·이력·지문만 맞추므로, 백업 복원보다 잃는 것이 적다.
            if !health.blocksOpen,
               let repaired = LibraryCatalogRepair.repairedCatalogIfOpenable(
                   catalog,
                   defectDirectory: defectDirectory,
                   fileManager: fileManager
               ) {
                return finalizeRepairedCatalog(
                    repaired,
                    sourceVersion: sourceVersion,
                    at: url,
                    defectDirectory: defectDirectory,
                    backupDirectory: backupDirectory,
                    fileManager: fileManager
                )
            }
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
            case let .loaded(legacyCatalog, sourceVersion):
                var catalog = legacyCatalog
                var repairReport: LibraryCatalogRepairReport?
                let health = LibraryCatalogHealthInspector.inspect(
                    catalog,
                    defectDirectory: defectDirectory,
                    fileManager: fileManager
                )
                if !health.canOpenSafely {
                    guard !health.blocksOpen,
                          let repaired = LibraryCatalogRepair.repairedCatalogIfOpenable(
                              catalog,
                              defectDirectory: defectDirectory,
                              fileManager: fileManager
                          ) else {
                        return .blocked(openFailure(for: health))
                    }
                    catalog = repaired.catalog
                    repairReport = repaired.report
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
                        : nil,
                    repairReport: repairReport
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
                    // 백업도 legacy 사본도 없다. sqlite 로 옮기면서 옆에 둔 예전 JSON 이
                    // 남아 있으면 그것이 마지막 원본이다.
                    if let recovered = recoverFromPreservedLegacyJSON(
                        at: url,
                        defectDirectory: defectDirectory,
                        backupDirectory: backupDirectory,
                        fileManager: fileManager
                    ) {
                        return recovered
                    }
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

    /// 수리 결과를 자리에 기록한다. 고치기 전 상태는 정식 백업 세대와 옆에 둔 사본 두 벌로
    /// 남긴다 — 수리가 마음에 들지 않으면 사용자가 되돌릴 수 있어야 한다.
    static func finalizeRepairedCatalog(
        _ repaired: LibraryCatalogRepairResult,
        sourceVersion: Int,
        at url: URL,
        defectDirectory: URL,
        backupDirectory: URL,
        fileManager: FileManager
    ) -> LibraryCatalogOpenResult {
        _ = try? LibraryBackupStore.createSnapshot(
            catalogURL: url,
            defectDirectory: defectDirectory,
            backupDirectory: backupDirectory,
            fileManager: fileManager
        )
        guard preserveRepairSource(at: url, fileManager: fileManager),
              writeAndVerify(repaired.catalog, to: url, fileManager: fileManager) else {
            return .blocked(.writeFailed)
        }
        return .loaded(
            catalog: repaired.catalog,
            recoveredFromBackup: false,
            migratedFromVersion: sourceVersion < LibraryCatalog.currentVersion
                ? sourceVersion
                : nil,
            repairReport: repaired.report
        )
    }

    static func preserveRepairSource(
        at url: URL,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return true }
        let fileExtension = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
        let preserved = url.deletingLastPathComponent().appendingPathComponent(
            "library.pre-repair-\(UUID().uuidString)\(fileExtension)"
        )
        do {
            try fileManager.copyItem(at: url, to: preserved)
            LibraryCatalogSidelinedFiles.prune(
                in: url.deletingLastPathComponent(),
                fileManager: fileManager
            )
            return true
        } catch {
            return false
        }
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

    /// 되살릴 것이 남아 있으면 빈 라이브러리로 조용히 시작하지 않는다. 결함 기록은 아직
    /// 이미지에 굽지 못한 사용자 편집일 수 있어서, 카탈로그가 없다고 그것을 버리면 안 된다.
    /// 여기서 막힌 사용자는 복구 화면의 "새 라이브러리로 시작" 으로 빠져나올 수 있다.
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

    /// sqlite 로 옮기면서 `library.pre-sqlite-*.json` 으로 남겨 둔 원본에서 되살린다.
    static func recoverFromPreservedLegacyJSON(
        at url: URL,
        defectDirectory: URL,
        backupDirectory: URL,
        fileManager: FileManager
    ) -> LibraryCatalogOpenResult? {
        guard LibraryCatalogSQLiteStore.isSQLiteURL(url) else { return nil }
        let candidates = LibraryCatalogSQLiteMigration.preservedLegacyURLs(
            besides: url,
            fileManager: fileManager
        )
        for candidate in candidates {
            guard case let .loaded(catalog, sourceVersion) = read(
                from: candidate,
                fileManager: fileManager
            ) else { continue }
            var recovered = catalog
            let health = LibraryCatalogHealthInspector.inspect(
                recovered,
                defectDirectory: defectDirectory,
                fileManager: fileManager
            )
            if !health.canOpenSafely {
                guard !health.blocksOpen,
                      let repaired = LibraryCatalogRepair.repairedCatalogIfOpenable(
                          recovered,
                          defectDirectory: defectDirectory,
                          fileManager: fileManager
                      ) else { continue }
                recovered = repaired.catalog
            }
            guard writeAndVerify(recovered, to: url, fileManager: fileManager) else { continue }
            _ = try? LibraryBackupStore.createSnapshot(
                catalogURL: url,
                defectDirectory: defectDirectory,
                backupDirectory: backupDirectory,
                fileManager: fileManager
            )
            return .loaded(
                catalog: recovered,
                recoveredFromBackup: true,
                migratedFromVersion: sourceVersion < LibraryCatalog.currentVersion
                    ? sourceVersion
                    : nil,
                repairReport: nil
            )
        }
        return nil
    }

    static func openFailure(
        for health: LibraryCatalogHealthReport
    ) -> LibraryCatalogOpenFailure {
        let authoritativeCodes: Set<LibraryCatalogHealthIssueCode> = [
            .missingDefectRecipe,
            .invalidDefectRecipe,
        ]
        let errorCodes = Set(health.blockingIssues.map(\.code))
        return !errorCodes.isEmpty && errorCodes.isSubset(of: authoritativeCodes)
            ? .missingAuthoritativeData
            : .corrupt
    }


}
