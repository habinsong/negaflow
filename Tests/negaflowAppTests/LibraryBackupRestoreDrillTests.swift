import XCTest
@testable import negaflowApp

final class LibraryBackupRestoreDrillTests: XCTestCase {
    func testDrillRestoresGenerationIntoIsolatedLocationAndOpensIt() throws {
        let fixture = try makeGeneration()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = LibraryBackupRestoreDrill.verify(
            generationURL: fixture.generation,
            now: Date(timeIntervalSince1970: 500)
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.generationID, fixture.generation.lastPathComponent)
        XCTAssertEqual(result.verifiedAt, Date(timeIntervalSince1970: 500))
        XCTAssertNotNil(LibraryBackupStore.validateSnapshotDirectory(at: fixture.generation))
    }

    func testDrillFailsForDamagedGeneration() throws {
        let fixture = try makeGeneration()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("damaged".utf8).write(
            to: fixture.generation.appendingPathComponent("library.json"),
            options: .atomic
        )

        let result = LibraryBackupRestoreDrill.verify(generationURL: fixture.generation)

        XCTAssertFalse(result.succeeded)
    }

    private func makeGeneration() throws -> (root: URL, generation: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-restore-drill-test-\(UUID().uuidString)", isDirectory: true
        )
        let source = root.appendingPathComponent("source", isDirectory: true)
        let catalogURL = source.appendingPathComponent("library.json")
        let defects = source.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let catalog = LibraryCatalog()
        try XCTUnwrap(LibraryCatalogFile.encode(catalog)).write(to: catalogURL, options: .atomic)
        let generation = try LibraryBackupStore.createSnapshot(
            catalogURL: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups
        )
        return (root, generation)
    }
}
