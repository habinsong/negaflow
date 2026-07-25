import XCTest
import ScannerKit
@testable import negaflowApp

@MainActor
final class LibraryBackupStoreTests: XCTestCase {
    func testSnapshotRestoreRoundTripPreservesScanWorkflowState() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let session = try makeQueuedSession()
        let assignment = LibraryScanRollAssignment(
            sessionID: session.id,
            rollID: UUID(),
            draftName: "Backup Roll",
            filmType: .colorNegative,
            createdAt: session.createdAt
        )
        let catalog = LibraryCatalog(
            scanSessions: [session],
            scanRollAssignments: [assignment]
        )
        try FileManager.default.createDirectory(
            at: paths.catalog.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(LibraryCatalogFile.encode(catalog))
            .write(to: paths.catalog, options: .atomic)
        _ = try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 50)
        )

        try Data("{broken".utf8).write(to: paths.catalog, options: .atomic)
        let restored = try XCTUnwrap(LibraryBackupStore.restoreLatest(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups
        ))

        XCTAssertEqual(restored.scanSessions, [session])
        XCTAssertEqual(restored.scanRollAssignments, [assignment])
        let persisted = try XCTUnwrap(LibraryCatalogFile.loadPrimary(from: paths.catalog))
        XCTAssertEqual(persisted.scanSessions, [session])
        XCTAssertEqual(persisted.scanRollAssignments, [assignment])
    }

    func testSnapshotIncludesCatalogAndAuthoritativeRecipeAndRetainsThreeGenerations() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let frameID = UUID()
        try DefectSidecarFile.write([], for: frameID, in: paths.defects)

        for generation in 0..<4 {
            try writeCatalog(
                frameID: frameID,
                folder: "/generation-\(generation)",
                hasDefects: true,
                to: paths.catalog
            )
            _ = try LibraryBackupStore.createSnapshot(
                catalogURL: paths.catalog,
                defectDirectory: paths.defects,
                backupDirectory: paths.backups,
                now: Date(timeIntervalSince1970: TimeInterval(generation)),
                retentionCount: 3
            )
        }

        let backupDirectories = try FileManager.default.contentsOfDirectory(
            at: paths.backups,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.lastPathComponent.hasPrefix("backup-") }
        XCTAssertEqual(backupDirectories.count, 3)
        let latest = try XCTUnwrap(LibraryBackupStore.latestValidSnapshot(in: paths.backups))
        XCTAssertEqual(latest.catalog.folders, ["/generation-3"])
        XCTAssertEqual(latest.manifest.defectFrameIDs, [frameID])
        XCTAssertEqual(latest.integrity, .checksummed)
        XCTAssertEqual(latest.manifest.catalogVersion, LibraryCatalog.currentVersion)
        XCTAssertEqual(
            latest.manifest.files?.map(\.relativePath),
            ["defects/\(frameID.uuidString).plist", "library.json"]
        )
        XCTAssertNotNil(
            DefectSidecarFile.load(
                for: frameID,
                in: latest.directoryURL.appendingPathComponent("defects", isDirectory: true)
            )
        )
    }

    func testSnapshotFailsInsteadOfClaimingSuccessWhenRecipeIsMissing() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try writeCatalog(
            frameID: UUID(),
            folder: "/missing-recipe",
            hasDefects: true,
            to: paths.catalog
        )

        XCTAssertThrowsError(
            try LibraryBackupStore.createSnapshot(
                catalogURL: paths.catalog,
                defectDirectory: paths.defects,
                backupDirectory: paths.backups
            )
        )
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            at: paths.backups,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testRestoreLatestRecoversCatalogAndRecipeAndPreservesCorruptPrimary() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let frameID = UUID()
        try DefectSidecarFile.write([], for: frameID, in: paths.defects)
        try writeCatalog(
            frameID: frameID,
            folder: "/recover-me",
            hasDefects: true,
            to: paths.catalog
        )
        _ = try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 100)
        )

        try Data("{broken".utf8).write(to: paths.catalog, options: .atomic)
        try Data("broken recipe".utf8).write(
            to: DefectSidecarFile.url(for: frameID, in: paths.defects),
            options: .atomic
        )

        let restored = try LibraryBackupStore.restoreLatest(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups
        )

        XCTAssertEqual(restored?.folders, ["/recover-me"])
        XCTAssertEqual(LibraryCatalogFile.loadPrimary(from: paths.catalog)?.folders, ["/recover-me"])
        XCTAssertNotNil(DefectSidecarFile.load(for: frameID, in: paths.defects))
        let preserved = try FileManager.default.contentsOfDirectory(
            at: paths.catalog.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("library.corrupt-") }
        XCTAssertEqual(preserved.count, 1)
        let preservedDefects = try FileManager.default.contentsOfDirectory(
            at: paths.catalog.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("defects.corrupt-") }
        XCTAssertEqual(preservedDefects.count, 1)
        let preservedDefectDirectory = try XCTUnwrap(preservedDefects.first)
        XCTAssertEqual(
            try Data(
                contentsOf: DefectSidecarFile.url(for: frameID, in: preservedDefectDirectory)
            ),
            Data("broken recipe".utf8)
        )
    }

    func testRestoreLatestReplacesWholeDefectSetWithoutLeavingStaleSidecars() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let frameID = UUID()
        try writeCatalog(
            frameID: frameID,
            folder: "/replace-defects",
            hasDefects: false,
            to: paths.catalog
        )
        _ = try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 110)
        )

        let staleFrameID = UUID()
        try DefectSidecarFile.write([], for: staleFrameID, in: paths.defects)
        try Data("{broken".utf8).write(to: paths.catalog, options: .atomic)

        let restored = try LibraryBackupStore.restoreLatest(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups
        )

        XCTAssertEqual(restored?.folders, ["/replace-defects"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: DefectSidecarFile.url(for: staleFrameID, in: paths.defects).path
            )
        )
        let preservedDefects = try FileManager.default.contentsOfDirectory(
            at: paths.catalog.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("defects.corrupt-") }
        XCTAssertEqual(preservedDefects.count, 1)
        let preservedDefectDirectory = try XCTUnwrap(preservedDefects.first)
        XCTAssertNotNil(
            DefectSidecarFile.load(for: staleFrameID, in: preservedDefectDirectory)
        )
    }

    func testInvalidSnapshotDoesNotChangeLiveCatalogOrDefectBytes() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let frameID = UUID()
        try DefectSidecarFile.write([], for: frameID, in: paths.defects)
        try writeCatalog(
            frameID: frameID,
            folder: "/invalid-snapshot",
            hasDefects: true,
            to: paths.catalog
        )
        let snapshot = try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 120)
        )
        try Data("damaged snapshot recipe".utf8).write(
            to: DefectSidecarFile.url(
                for: frameID,
                in: snapshot.appendingPathComponent("defects", isDirectory: true)
            ),
            options: .atomic
        )

        let liveCatalogData = Data("{live catalog bytes".utf8)
        let liveDefectData = Data("live defect bytes".utf8)
        try liveCatalogData.write(to: paths.catalog, options: .atomic)
        try liveDefectData.write(
            to: DefectSidecarFile.url(for: frameID, in: paths.defects),
            options: .atomic
        )

        let restored = try LibraryBackupStore.restoreLatest(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups
        )

        XCTAssertNil(restored)
        XCTAssertEqual(try Data(contentsOf: paths.catalog), liveCatalogData)
        XCTAssertEqual(
            try Data(contentsOf: DefectSidecarFile.url(for: frameID, in: paths.defects)),
            liveDefectData
        )
    }

    func testCorruptNewestSnapshotFallsBackToPreviousValidGeneration() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let frameID = UUID()
        try writeCatalog(frameID: frameID, folder: "/older", hasDefects: false, to: paths.catalog)
        _ = try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 100)
        )
        try writeCatalog(frameID: frameID, folder: "/newer", hasDefects: false, to: paths.catalog)
        let newest = try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 200)
        )
        try Data("{broken".utf8).write(
            to: newest.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        let latest = try XCTUnwrap(LibraryBackupStore.latestValidSnapshot(in: paths.backups))

        XCTAssertEqual(latest.catalog.folders, ["/older"])
    }

    func testVersionOneSnapshotRestoresAsCurrentCatalog() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let frameID = UUID()
        try writeCatalog(
            frameID: frameID,
            folder: "/legacy-v1",
            hasDefects: false,
            to: paths.catalog
        )
        let currentData = try Data(contentsOf: paths.catalog)
        let legacyData = try rewriteVersion(
            currentData,
            version: 1,
            minimumReaderVersion: nil
        )
        try legacyData.write(to: paths.catalog, options: .atomic)
        _ = try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 300)
        )
        try FileManager.default.removeItem(at: paths.catalog)

        let restored = try LibraryBackupStore.restoreLatest(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups
        )

        XCTAssertEqual(restored?.folders, ["/legacy-v1"])
        guard case let .loaded(onDisk, sourceVersion) = LibraryCatalogFile.read(from: paths.catalog) else {
            return XCTFail("restored catalog should be readable")
        }
        XCTAssertEqual(sourceVersion, LibraryCatalog.currentVersion)
        XCTAssertEqual(onDisk.version, LibraryCatalog.currentVersion)
        XCTAssertEqual(onDisk.frames.map(\.id), [frameID])
    }

    func testRestoreLatestRefusesToReplaceFuturePrimary() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let frameID = UUID()
        try writeCatalog(
            frameID: frameID,
            folder: "/snapshot",
            hasDefects: false,
            to: paths.catalog
        )
        _ = try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 400)
        )
        let currentData = try Data(contentsOf: paths.catalog)
        let futureVersion = LibraryCatalog.currentVersion + 1
        let futureData = try rewriteVersion(
            currentData,
            version: futureVersion,
            minimumReaderVersion: futureVersion
        )
        try futureData.write(to: paths.catalog, options: .atomic)

        XCTAssertThrowsError(
            try LibraryBackupStore.restoreLatest(
                catalogURL: paths.catalog,
                defectDirectory: paths.defects,
                backupDirectory: paths.backups
            )
        ) { error in
            guard case LibraryBackupError.unsupportedCatalogVersion(futureVersion) = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: paths.catalog), futureData)
    }

    func testChecksumMismatchInvalidatesOtherwiseDecodableSnapshot() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try writeCatalog(
            frameID: UUID(),
            folder: "/checksummed",
            hasDefects: false,
            to: paths.catalog
        )
        let snapshot = try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 500)
        )
        let catalogURL = snapshot.appendingPathComponent("library.json")
        let originalData = try Data(contentsOf: catalogURL)
        let originalText = try XCTUnwrap(String(data: originalData, encoding: .utf8))
        let tamperedData = try XCTUnwrap(
            originalText.replacingOccurrences(
                of: "/checksummed",
                with: "/tamperedxxx"
            ).data(using: .utf8)
        )
        XCTAssertEqual(tamperedData.count, originalData.count)
        XCTAssertNotNil(LibraryCatalogFile.decode(tamperedData))
        try tamperedData.write(
            to: catalogURL,
            options: .atomic
        )

        XCTAssertNil(LibraryBackupStore.latestValidSnapshot(in: paths.backups))
    }

    func testChecksummedManifestCannotSilentlyDropChecksumFields() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try writeCatalog(
            frameID: UUID(),
            folder: "/required-checksums",
            hasDefects: false,
            to: paths.catalog
        )
        let snapshot = try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 550)
        )
        let manifestURL = snapshot.appendingPathComponent("manifest.json")
        var manifestObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
                as? [String: Any]
        )
        XCTAssertEqual(
            manifestObject["version"] as? Int,
            LibraryBackupManifest.currentVersion
        )
        manifestObject["files"] = nil
        try JSONSerialization.data(withJSONObject: manifestObject, options: [.sortedKeys])
            .write(to: manifestURL, options: .atomic)

        XCTAssertNil(LibraryBackupStore.latestValidSnapshot(in: paths.backups))
    }

    func testLegacyManifestWithoutChecksumsRemainsStructurallyRestorable() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try writeCatalog(
            frameID: UUID(),
            folder: "/legacy-manifest",
            hasDefects: false,
            to: paths.catalog
        )
        let snapshot = try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 600)
        )
        let manifestURL = snapshot.appendingPathComponent("manifest.json")
        var manifestObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
                as? [String: Any]
        )
        manifestObject["version"] = 1
        manifestObject["catalogVersion"] = nil
        manifestObject["files"] = nil
        try JSONSerialization.data(withJSONObject: manifestObject, options: [.sortedKeys])
            .write(to: manifestURL, options: .atomic)

        let legacy = try XCTUnwrap(LibraryBackupStore.latestValidSnapshot(in: paths.backups))
        XCTAssertEqual(legacy.integrity, .legacyStructureOnly)
        try FileManager.default.removeItem(at: paths.catalog)
        let restored = try LibraryBackupStore.restoreLatest(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups
        )
        XCTAssertEqual(restored?.folders, ["/legacy-manifest"])
    }

    func testGenerationsReportsRawVersionForLegacyCatalog() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try writeCatalog(
            frameID: UUID(),
            folder: "/legacy-catalog-version",
            hasDefects: false,
            to: paths.catalog
        )
        let snapshot = try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 650)
        )

        let snapshotCatalogURL = snapshot.appendingPathComponent("library.json")
        let legacyCatalogData = try rewriteVersion(
            Data(contentsOf: snapshotCatalogURL),
            version: 1,
            minimumReaderVersion: nil
        )
        try legacyCatalogData.write(to: snapshotCatalogURL, options: .atomic)

        let manifestURL = snapshot.appendingPathComponent("manifest.json")
        var manifestObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
                as? [String: Any]
        )
        manifestObject["version"] = 1
        manifestObject["catalogVersion"] = nil
        manifestObject["files"] = nil
        try JSONSerialization.data(withJSONObject: manifestObject, options: [.sortedKeys])
            .write(to: manifestURL, options: .atomic)

        let decodedSnapshot = try XCTUnwrap(
            LibraryBackupStore.latestValidSnapshot(in: paths.backups)
        )
        XCTAssertEqual(decodedSnapshot.catalog.version, LibraryCatalog.currentVersion)
        XCTAssertEqual(decodedSnapshot.sourceCatalogVersion, 1)
        let generation = try XCTUnwrap(
            LibraryBackupStore.generations(in: paths.backups).first
        )
        XCTAssertEqual(generation.state, .legacyStructureOnly)
        XCTAssertEqual(generation.catalogVersion, 1)
    }

    func testVersionTwoSnapshotPreservesRawSourceCatalogVersion() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try writeCatalog(
            frameID: UUID(),
            folder: "/legacy-catalog-v2",
            hasDefects: false,
            to: paths.catalog
        )
        let legacyData = try rewriteVersion(
            Data(contentsOf: paths.catalog),
            version: 2,
            minimumReaderVersion: 2
        )
        try legacyData.write(to: paths.catalog, options: .atomic)

        let directory = try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 700)
        )
        let snapshot = try XCTUnwrap(
            LibraryBackupStore.validateSnapshotDirectory(at: directory)
        )

        XCTAssertEqual(snapshot.sourceCatalogVersion, 2)
        XCTAssertEqual(snapshot.manifest.catalogVersion, 2)
        XCTAssertEqual(snapshot.catalog.version, LibraryCatalog.currentVersion)
        XCTAssertEqual(snapshot.catalog.rolls.map(\.id), [LibraryRoll.unassignedID])
        XCTAssertTrue(snapshot.catalog.scanSessions.isEmpty)
        XCTAssertTrue(snapshot.catalog.scanRollAssignments.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(LibraryBackupStore.generations(in: paths.backups).first).catalogVersion,
            2
        )
    }

    private func makePaths() throws -> (
        root: URL,
        catalog: URL,
        defects: URL,
        backups: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-backups-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        let defects = support.appendingPathComponent("defects", isDirectory: true)
        let backups = support.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: defects, withIntermediateDirectories: true)
        return (root, support.appendingPathComponent("library.json"), defects, backups)
    }

    private func writeCatalog(
        frameID: UUID,
        folder: String,
        hasDefects: Bool,
        to url: URL
    ) throws {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/source.tiff"),
            filmType: .colorNegative,
            id: frameID
        )
        var record = LibraryFrameRecord(frame: frame)
        record.hasDefectEdits = hasDefects ? true : nil
        let catalog = LibraryCatalog(folders: [folder], frames: [record])
        let data = try XCTUnwrap(LibraryCatalogFile.encode(catalog))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private func rewriteVersion(
        _ data: Data,
        version: Int,
        minimumReaderVersion: Int?
    ) throws -> Data {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["version"] = version
        object["minimumReaderVersion"] = minimumReaderVersion
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func makeQueuedSession() throws -> ScanSession {
        let sessionID = UUID()
        let jobID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let scannerID = "plugin:test-plugin:device-1"
        var options = ScanOptions.strongDefault(scannerID: scannerID)
        options.requestID = jobID
        options.temporaryOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-job-\(jobID.uuidString).tiff")
        let job = try ScanJob(
            id: jobID,
            sessionID: sessionID,
            ordinal: 1,
            kind: .full,
            requestedOptions: options,
            framePublication: try ScanFramePublicationSnapshot(
                frameID: jobID,
                scanIndex: 1,
                initialTransform: .identity,
                developTarget: .main,
                storageGroupName: "TestScanner"
            ),
            createdAt: createdAt
        )
        return try ScanSession(
            id: sessionID,
            createdAt: createdAt,
            device: ScannerDescriptor(
                id: scannerID,
                displayName: "Test Scanner",
                vendor: "Test Vendor",
                model: "Test Model",
                backendType: .plugin
            ),
            backend: ScanBackendSnapshot(
                type: .plugin,
                identifier: "external-json",
                pluginIdentifier: "test-plugin"
            ),
            environment: ScanEnvironmentSnapshot(
                applicationName: "negaflow",
                applicationVersion: "1.0",
                operatingSystem: "macOS",
                operatingSystemVersion: "15.0",
                architecture: "arm64"
            ),
            jobs: [job]
        )
    }
}
