import XCTest
@testable import negaflowApp

@MainActor
final class LibraryPendingRestoreStoreTests: XCTestCase {
    private enum ForcedFailure: Error { case markerDelete }

    func testGenerationListingKeepsValidLegacyDamagedAndIncompatibleStates() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let valid = try createSnapshot(
            folder: "/valid",
            at: Date(timeIntervalSince1970: 400),
            paths: paths
        )
        let legacy = try createSnapshot(
            folder: "/legacy",
            at: Date(timeIntervalSince1970: 300),
            paths: paths
        )
        let damaged = try createSnapshot(
            folder: "/damaged",
            at: Date(timeIntervalSince1970: 200),
            paths: paths
        )
        let incompatible = try createSnapshot(
            folder: "/future",
            at: Date(timeIntervalSince1970: 100),
            paths: paths
        )
        try rewriteManifestAsLegacy(in: legacy)
        let damagedCatalogURL = damaged.appendingPathComponent("library.json")
        var damagedData = try Data(contentsOf: damagedCatalogURL)
        damagedData.append(0x0A)
        try damagedData.write(to: damagedCatalogURL, options: .atomic)
        let incompatibleCatalogURL = incompatible.appendingPathComponent("library.json")
        let incompatibleData = try rewriteVersion(
            Data(contentsOf: incompatibleCatalogURL),
            version: LibraryCatalog.currentVersion + 1
        )
        try incompatibleData.write(to: incompatibleCatalogURL, options: .atomic)

        let generations = try LibraryBackupStore.generations(in: paths.backups)
        let states = Dictionary(uniqueKeysWithValues: generations.map { ($0.id, $0.state) })

        XCTAssertEqual(states[valid.lastPathComponent], .checksummed)
        XCTAssertEqual(states[legacy.lastPathComponent], .legacyStructureOnly)
        XCTAssertEqual(states[damaged.lastPathComponent], .damaged)
        XCTAssertEqual(states[incompatible.lastPathComponent], .incompatible)
        XCTAssertEqual(
            generations.compactMap(\.sequence),
            generations.compactMap(\.sequence).sorted(by: >)
        )
    }

    func testScheduledRestoreUsesPinnedCopyAfterSourceGenerationIsRemoved() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let source = try createSnapshot(
            folder: "/selected",
            at: Date(timeIntervalSince1970: 100),
            paths: paths
        )
        let marker = try LibraryPendingRestoreStore.schedule(
            generationID: source.lastPathComponent,
            catalogURL: paths.catalog,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 200)
        )
        try FileManager.default.removeItem(at: source)

        XCTAssertEqual(
            LibraryPendingRestoreStore.pendingMarker(for: paths.catalog),
            marker
        )
        let pendingDirectory = LibraryPendingRestoreStore.defaultDirectoryURL(
            for: paths.catalog
        ).appendingPathComponent(marker.directoryName, isDirectory: true)
        XCTAssertNotNil(
            LibraryBackupStore.validateSnapshotDirectory(at: pendingDirectory)
        )

        try LibraryPendingRestoreStore.cancel(catalogURL: paths.catalog)
        XCTAssertNil(LibraryPendingRestoreStore.pendingMarker(for: paths.catalog))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingDirectory.path))
    }

    func testApplyUsesSelectedGenerationAndBacksUpCurrentLibrary() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let selected = try createSnapshot(
            folder: "/selected-old",
            at: Date(timeIntervalSince1970: 100),
            paths: paths
        )
        try writeCatalog(folder: "/current-live", to: paths.catalog)
        _ = try LibraryPendingRestoreStore.schedule(
            generationID: selected.lastPathComponent,
            catalogURL: paths.catalog,
            backupDirectory: paths.backups,
            now: Date(timeIntervalSince1970: 200)
        )

        let result = try LibraryPendingRestoreStore.applyIfScheduled(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups
        )

        XCTAssertEqual(
            result,
            .applied(sourceGenerationID: selected.lastPathComponent)
        )
        XCTAssertEqual(
            LibraryCatalogFile.loadPrimary(from: paths.catalog)?.folders,
            ["/selected-old"]
        )
        XCTAssertNil(LibraryPendingRestoreStore.pendingMarker(for: paths.catalog))
        let snapshots = try FileManager.default.contentsOfDirectory(
            at: paths.backups,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).compactMap {
            LibraryBackupStore.validateSnapshotDirectory(at: $0)
        }
        XCTAssertTrue(snapshots.contains { $0.catalog.folders == ["/current-live"] })
    }

    func testFutureCurrentCatalogBlocksPendingRestoreWithoutChangingEither() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let selected = try createSnapshot(
            folder: "/selected",
            at: Date(timeIntervalSince1970: 100),
            paths: paths
        )
        let marker = try LibraryPendingRestoreStore.schedule(
            generationID: selected.lastPathComponent,
            catalogURL: paths.catalog,
            backupDirectory: paths.backups
        )
        let currentData = try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog()))
        let futureVersion = LibraryCatalog.currentVersion + 1
        let futureData = try rewriteVersion(currentData, version: futureVersion)
        try futureData.write(to: paths.catalog, options: .atomic)

        XCTAssertThrowsError(
            try LibraryPendingRestoreStore.applyIfScheduled(
                catalogURL: paths.catalog,
                defectDirectory: paths.defects,
                backupDirectory: paths.backups
            )
        ) { error in
            XCTAssertEqual(
                error as? LibraryPendingRestoreError,
                .unsupportedCurrentCatalog(futureVersion)
            )
        }
        XCTAssertEqual(try Data(contentsOf: paths.catalog), futureData)
        XCTAssertEqual(
            LibraryPendingRestoreStore.pendingMarker(for: paths.catalog),
            marker
        )
    }

    func testTraversalGenerationIDIsRejected() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        XCTAssertThrowsError(
            try LibraryPendingRestoreStore.schedule(
                generationID: "../backup-escape",
                catalogURL: paths.catalog,
                backupDirectory: paths.backups
            )
        ) { error in
            XCTAssertEqual(error as? LibraryPendingRestoreError, .invalidGeneration)
        }
    }

    func testAppModelAppliesScheduledRestoreBeforeOpeningLibrary() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let selected = try createSnapshot(
            folder: "/selected-on-launch",
            at: Date(timeIntervalSince1970: 100),
            paths: paths
        )
        try writeCatalog(folder: "/current-before-launch", to: paths.catalog)
        _ = try LibraryPendingRestoreStore.schedule(
            generationID: selected.lastPathComponent,
            catalogURL: paths.catalog,
            backupDirectory: paths.backups
        )
        let model = AppModel(
            libraryCatalogURL: paths.catalog,
            libraryDefectDirectoryURL: paths.defects,
            libraryBackupDirectoryURL: paths.backups
        )
        defer {
            model.librarySaveTask?.cancel()
            model.librarySaveTask = nil
        }

        await model.restoreLibraryOnLaunch()

        XCTAssertTrue(model.libraryPersistenceEnabled)
        XCTAssertNil(model.libraryCatalogBlockReason)
        XCTAssertNil(model.libraryPendingRestoreMarker)
        XCTAssertEqual(
            LibraryCatalogFile.loadPrimary(from: paths.catalog)?.folders,
            ["/selected-on-launch"]
        )
        XCTAssertEqual(model.frames.count, 1)
    }

    func testMarkerDeleteFailureOpensAppliedCatalogAndRetriesCleanupOnly() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let selected = try createSnapshot(
            folder: "/selected-cleanup-retry",
            at: Date(timeIntervalSince1970: 100),
            paths: paths
        )
        try writeCatalog(folder: "/current-before-cleanup-retry", to: paths.catalog)
        _ = try LibraryPendingRestoreStore.schedule(
            generationID: selected.lastPathComponent,
            catalogURL: paths.catalog,
            backupDirectory: paths.backups
        )

        let result = try LibraryPendingRestoreStore.applyIfScheduled(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            fileManager: .default,
            cleanup: LibraryPendingRestoreCleanup(
                removeDirectory: { try FileManager.default.removeItem(at: $0) },
                removeMarker: { _ in throw ForcedFailure.markerDelete }
            )
        )

        XCTAssertEqual(result, .cleanupPending(
            sourceGenerationID: selected.lastPathComponent,
            didApplyRestore: true
        ))
        XCTAssertTrue(result.didApplyRestore)
        XCTAssertEqual(
            LibraryCatalogFile.loadPrimary(from: paths.catalog)?.folders,
            ["/selected-cleanup-retry"]
        )
        XCTAssertNil(LibraryPendingRestoreStore.pendingMarker(for: paths.catalog))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: LibraryPendingRestoreStore.markerURL(for: paths.catalog).path
        ))
        let generationCountAfterApply = try LibraryBackupStore.generations(
            in: paths.backups
        ).count

        let model = AppModel(
            libraryCatalogURL: paths.catalog,
            libraryDefectDirectoryURL: paths.defects,
            libraryBackupDirectoryURL: paths.backups
        )
        defer {
            model.librarySaveTask?.cancel()
            model.librarySaveTask = nil
        }
        await model.restoreLibraryOnLaunch()

        XCTAssertTrue(model.libraryPersistenceEnabled)
        XCTAssertEqual(model.libraryLifecycleState, .ready)
        XCTAssertNil(model.libraryCatalogBlockReason)
        XCTAssertEqual(model.frames.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: LibraryPendingRestoreStore.markerURL(for: paths.catalog).path
        ))
        XCTAssertEqual(
            try LibraryBackupStore.generations(in: paths.backups).count,
            generationCountAfterApply,
            "cleanup retry must not apply or safety-backup the generation again"
        )
    }

    private typealias Paths = (
        root: URL,
        catalog: URL,
        defects: URL,
        backups: URL
    )

    private func makePaths() throws -> Paths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-pending-restore-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        let defects = support.appendingPathComponent("defects", isDirectory: true)
        let backups = support.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: defects, withIntermediateDirectories: true)
        return (
            root,
            support.appendingPathComponent("library.json"),
            defects,
            backups
        )
    }

    private func createSnapshot(
        folder: String,
        at date: Date,
        paths: Paths
    ) throws -> URL {
        try writeCatalog(folder: folder, to: paths.catalog)
        return try LibraryBackupStore.createSnapshot(
            catalogURL: paths.catalog,
            defectDirectory: paths.defects,
            backupDirectory: paths.backups,
            now: date,
            retentionCount: 10
        )
    }

    private func writeCatalog(folder: String, to url: URL) throws {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
        let catalog = LibraryCatalog(
            folders: [folder],
            frames: [LibraryFrameRecord(frame: frame)]
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(LibraryCatalogFile.encode(catalog)).write(to: url, options: .atomic)
    }

    private func rewriteManifestAsLegacy(in snapshot: URL) throws {
        let url = snapshot.appendingPathComponent("manifest.json")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        object["version"] = 1
        object["catalogVersion"] = nil
        object["files"] = nil
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            .write(to: url, options: .atomic)
    }

    private func rewriteVersion(_ data: Data, version: Int) throws -> Data {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["version"] = version
        object["minimumReaderVersion"] = version
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
