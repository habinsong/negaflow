import XCTest
@testable import negaflowApp

@MainActor
final class LibraryFolderWorkflowTests: XCTestCase {
    func testCreatingFolderRegistersItAndPersistsRecentScanDestination() throws {
        let suiteName = "negaflow.library-folder-workflow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-library-folder-workflow-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let diskStorage = DiskStorageStore(defaults: defaults)
        let model = AppModel(diskStorageStore: diskStorage)

        let first = try XCTUnwrap(model.createLibraryFolder(named: "Roll A", in: root))
        let second = try XCTUnwrap(model.createLibraryFolder(named: "Roll B", in: root))

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(model.libraryFolders.map(\.url), [first, second])
        XCTAssertEqual(model.recentCreatedScanFolder, second)
        XCTAssertEqual(
            DiskStorageStore(defaults: defaults).recentCreatedScanFolderURL,
            second
        )
    }

    func testRemovingRecentCreatedFolderClearsScanDestinationWithoutDeletingFolder() throws {
        let suiteName = "negaflow.library-folder-remove.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-library-folder-remove-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(diskStorageStore: DiskStorageStore(defaults: defaults))
        let created = try XCTUnwrap(model.createLibraryFolder(named: "Scan Here", in: root))
        XCTAssertEqual(model.libraryFolders.count, 1)
        let folder = try XCTUnwrap(model.libraryFolders.first)

        model.removeLibraryFolder(folder)

        XCTAssertNil(model.recentCreatedScanFolder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path))
    }
}
