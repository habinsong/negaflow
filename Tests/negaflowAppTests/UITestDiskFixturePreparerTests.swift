import XCTest
@testable import negaflowApp

final class UITestDiskFixturePreparerTests: XCTestCase {
    func testCreatesValidatedBackupBeforeCorruptingPrimaryCatalog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-corrupt-fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = root.appendingPathComponent("Library/catalog.sqlite")
        try FileManager.default.createDirectory(
            at: catalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(LibraryCatalogFile.writeSync(
            try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog())),
            to: catalogURL
        ))
        let configuration = AppLaunchConfiguration(
            uiTestRoot: root,
            importsSyntheticNegative: false,
            enablesDemoScanner: false,
            preparesCorruptCatalog: true,
            createsDropTargetFolder: false,
            developsImportsAutomatically: false
        )

        UITestDiskFixturePreparer.prepare(configuration)

        XCTAssertNil(LibraryCatalogFile.loadPrimary(from: catalogURL))
        XCTAssertNotNil(LibraryBackupStore.latestValidSnapshot(
            in: root.appendingPathComponent("Library/Backups", isDirectory: true)
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("fixture-error.txt").path
        ))
    }
}
