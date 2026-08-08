import XCTest
@testable import negaflowApp

final class LibraryBackupMonotonicSequenceTests: XCTestCase {
    func testReverseTimestampsDoNotChangeRetentionLatestOrRestoreOrder() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let timestamps = [300.0, 100.0, 200.0]

        for index in timestamps.indices {
            try writeCatalog(folder: "/sequence-\(index + 1)", to: fixture.catalog)
            _ = try LibraryBackupStore.createSnapshot(
                catalogURL: fixture.catalog,
                defectDirectory: fixture.defects,
                backupDirectory: fixture.backups,
                now: Date(timeIntervalSince1970: timestamps[index]),
                retentionCount: 2
            )
        }

        let generations = try LibraryBackupStore.generations(in: fixture.backups)
        XCTAssertEqual(generations.compactMap(\.sequence), [3, 2])
        let latest = try XCTUnwrap(LibraryBackupStore.latestValidSnapshot(in: fixture.backups))
        XCTAssertEqual(latest.manifest.sequence, 3)
        XCTAssertEqual(latest.catalog.folders, ["/sequence-3"])
        try Data("broken".utf8).write(to: fixture.catalog, options: .atomic)

        let restored = try LibraryBackupStore.restoreLatest(
            catalogURL: fixture.catalog,
            defectDirectory: fixture.defects,
            backupDirectory: fixture.backups
        )
        XCTAssertEqual(restored?.folders, ["/sequence-3"])
    }

    func testDamagedGenerationStillPreventsSequenceReuse() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try writeCatalog(folder: "/first", to: fixture.catalog)
        let first = try LibraryBackupStore.createSnapshot(
            catalogURL: fixture.catalog,
            defectDirectory: fixture.defects,
            backupDirectory: fixture.backups
        )
        try Data("damaged".utf8).write(
            to: first.appendingPathComponent("library.json"),
            options: .atomic
        )
        try writeCatalog(folder: "/second", to: fixture.catalog)

        let second = try LibraryBackupStore.createSnapshot(
            catalogURL: fixture.catalog,
            defectDirectory: fixture.defects,
            backupDirectory: fixture.backups
        )

        let snapshot = try XCTUnwrap(LibraryBackupStore.validateSnapshotDirectory(at: second))
        XCTAssertEqual(snapshot.manifest.sequence, 2)
    }

    private func writeCatalog(folder: String, to url: URL) throws {
        let catalog = LibraryCatalog(folders: [folder])
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(LibraryCatalogFile.encode(catalog)).write(to: url, options: .atomic)
    }

    private func makeFixture() throws -> (
        catalog: URL,
        defects: URL,
        backups: URL,
        cleanup: () -> Void
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-monotonic-backup-\(UUID().uuidString)", isDirectory: true
        )
        let support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return (
            support.appendingPathComponent("library.json"),
            support.appendingPathComponent("defects", isDirectory: true),
            root.appendingPathComponent("backups", isDirectory: true),
            { try? FileManager.default.removeItem(at: root) }
        )
    }
}
