import Foundation
import CryptoKit

enum LibraryBackupStore {

    static let defaultRetentionCount = 3

    static func defaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        LibraryCatalogFile.defaultURL(fileManager: fileManager)
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
    }

    @discardableResult
    static func createSnapshot(
        catalogURL: URL,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL(),
        backupDirectory: URL = defaultDirectoryURL(),
        now: Date = Date(),
        retentionCount: Int = defaultRetentionCount,
        fileManager: FileManager = .default
    ) throws -> URL {
        let catalogData: Data
        let catalog: LibraryCatalog
        if LibraryCatalogSQLiteStore.isSQLiteURL(catalogURL) {
            guard case let .loaded(value, _) = LibraryCatalogFile.read(
                from: catalogURL,
                fileManager: fileManager
            ), let encoded = LibraryCatalogFile.encode(value) else {
                throw LibraryBackupError.invalidCatalog
            }
            catalog = value
            catalogData = encoded
        } else {
            let rawData = try Data(contentsOf: catalogURL)
            guard let decoded = LibraryCatalogFile.decode(rawData) else {
                throw LibraryBackupError.invalidCatalog
            }
            catalog = decoded
            catalogData = rawData
        }
        let defectFrameIDs = catalog.frames
            .filter { $0.hasDefectEdits == true }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }

        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let sequence = try LibraryBackupOrdering.nextSequence(
            in: backupDirectory,
            fileManager: fileManager,
            loadManifest: { directory in
                guard let data = try? Data(contentsOf: manifestURL(in: directory)) else {
                    return nil
                }
                return try? decodeManifest(data)
            }
        )
        let staging = backupDirectory.appendingPathComponent(
            "staging-\(UUID().uuidString).tmp",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        var committed = false
        defer {
            if !committed { try? fileManager.removeItem(at: staging) }
        }

        try catalogData.write(to: Self.catalogURL(in: staging), options: .atomic)
        let snapshotDefects = defectsDirectory(in: staging)
        try fileManager.createDirectory(at: snapshotDefects, withIntermediateDirectories: true)
        for frameID in defectFrameIDs {
            guard let data = DefectSidecarFile.validatedRawData(
                for: frameID,
                in: defectDirectory
            ) else {
                throw LibraryBackupError.missingDefectSidecar(frameID)
            }
            try data.write(
                to: DefectSidecarFile.url(for: frameID, in: snapshotDefects),
                options: .atomic
            )
        }

        let manifest = LibraryBackupManifest(
            sequence: sequence,
            createdAt: now,
            frameCount: catalog.frames.count,
            defectFrameIDs: defectFrameIDs,
            catalogVersion: sourceCatalogVersion(in: catalogData),
            files: try backupFileRecords(
                defectFrameIDs: defectFrameIDs,
                in: staging,
                fileManager: fileManager
            )
        )
        try encodeManifest(manifest).write(to: manifestURL(in: staging), options: .atomic)
        guard validateSnapshot(at: staging, fileManager: fileManager) != nil else {
            throw LibraryBackupError.invalidSnapshot
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let destination = backupDirectory.appendingPathComponent(
            String(format: "backup-%020llu-", sequence)
                + "\(formatter.string(from: now))-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.moveItem(at: staging, to: destination)
        committed = true
        pruneSnapshots(
            in: backupDirectory,
            keeping: max(1, retentionCount),
            fileManager: fileManager
        )
        return destination
    }

    static func latestValidSnapshot(
        in backupDirectory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) -> LibraryBackupSnapshot? {
        validSnapshots(in: backupDirectory, fileManager: fileManager)
            .sorted(by: LibraryBackupOrdering.isNewerSnapshot)
            .first
    }

    static func generations(
        in backupDirectory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) throws -> [LibraryBackupGeneration] {
        guard fileManager.fileExists(atPath: backupDirectory.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return urls.compactMap { url in
            guard url.lastPathComponent.hasPrefix("backup-") else { return nil }
            let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
            )
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { return nil }
            if let snapshot = validateSnapshot(at: url, fileManager: fileManager) {
                return LibraryBackupGeneration(
                    id: url.lastPathComponent,
                    sequence: snapshot.manifest.sequence,
                    createdAt: snapshot.manifest.createdAt,
                    frameCount: snapshot.manifest.frameCount,
                    defectRecipeCount: snapshot.manifest.defectFrameIDs.count,
                    catalogVersion: snapshot.sourceCatalogVersion,
                    state: snapshot.integrity == .checksummed
                        ? .checksummed
                        : .legacyStructureOnly
                )
            }

            let manifest = (try? Data(contentsOf: manifestURL(in: url)))
                .flatMap { try? decodeManifest($0) }
            let catalogRead = LibraryCatalogFile.read(
                from: catalogURL(in: url),
                fileManager: fileManager
            )
            let incompatible: Bool
            switch catalogRead {
            case .unsupportedVersion, .unsupportedStorageVersion:
                incompatible = true
            case .missing, .unreadable, .invalid, .loaded:
                incompatible = (manifest?.version ?? 0) > LibraryBackupManifest.currentVersion
            }
            return LibraryBackupGeneration(
                id: url.lastPathComponent,
                sequence: manifest?.sequence,
                createdAt: manifest?.createdAt ?? values?.contentModificationDate,
                frameCount: manifest?.frameCount,
                defectRecipeCount: manifest?.defectFrameIDs.count,
                catalogVersion: manifest?.catalogVersion,
                state: incompatible ? .incompatible : .damaged
            )
        }.sorted(by: LibraryBackupOrdering.isNewerGeneration)
    }

    static func validatedSnapshot(
        generationID: String,
        in backupDirectory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) -> LibraryBackupSnapshot? {
        guard generationID == (generationID as NSString).lastPathComponent,
              generationID.hasPrefix("backup-") else { return nil }
        let root = backupDirectory.standardizedFileURL
        let candidate = root.appendingPathComponent(generationID, isDirectory: true)
            .standardizedFileURL
        guard candidate.deletingLastPathComponent() == root else { return nil }
        return validateSnapshot(at: candidate, fileManager: fileManager)
    }

    static func validateSnapshotDirectory(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> LibraryBackupSnapshot? {
        validateSnapshot(at: directory, fileManager: fileManager)
    }

    static func hasValidAuthoritativeData(
        for catalog: LibraryCatalog,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL()
    ) -> Bool {
        catalog.frames
            .filter { $0.hasDefectEdits == true }
            .allSatisfy { DefectSidecarFile.load(for: $0.id, in: defectDirectory) != nil }
    }

    /// primary와 직전 단일 백업을 모두 읽지 못할 때만 호출한다. 손상 live 상태는 별도 복구점으로
    /// 보존하고, snapshot의 카탈로그와 recipe를 staging 검증 후 세대 단위로 교체한다.
    static func restoreLatest(
        catalogURL: URL,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL(),
        backupDirectory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) throws -> LibraryCatalog? {
        let primaryRead = LibraryCatalogFile.read(
            from: catalogURL,
            fileManager: fileManager
        )
        if case let .unsupportedVersion(version) = primaryRead {
            throw LibraryBackupError.unsupportedCatalogVersion(version)
        }
        if case let .unsupportedStorageVersion(version) = primaryRead {
            throw LibraryBackupError.unsupportedStorageVersion(version)
        }
        guard let snapshot = latestValidSnapshot(in: backupDirectory, fileManager: fileManager) else {
            return nil
        }
        guard let catalogData = LibraryCatalogFile.encode(snapshot.catalog) else {
            throw LibraryBackupError.invalidSnapshot
        }
        let parent = catalogURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let shouldPreserveUnsafeState: Bool
        switch primaryRead {
        case let .loaded(catalog, _):
            shouldPreserveUnsafeState = !LibraryCatalogHealthInspector.inspect(
                catalog,
                defectDirectory: defectDirectory,
                fileManager: fileManager
            ).canOpenSafely
        case .missing:
            shouldPreserveUnsafeState = fileManager.fileExists(atPath: defectDirectory.path)
        case .unreadable, .invalid:
            shouldPreserveUnsafeState = true
        case .unsupportedVersion, .unsupportedStorageVersion:
            shouldPreserveUnsafeState = false
        }
        if shouldPreserveUnsafeState {
            try preserveUnsafeState(
                catalogURL: catalogURL,
                defectDirectory: defectDirectory,
                fileManager: fileManager
            )
        }
        try applySnapshot(
            snapshot,
            catalogData: catalogData,
            catalogURL: catalogURL,
            defectDirectory: defectDirectory,
            fileManager: fileManager
        )
        return snapshot.catalog
    }


}
