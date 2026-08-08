import XCTest
@testable import negaflowApp

@MainActor
final class LibraryFolderExpansionStoreTests: XCTestCase {
    func testCollapsedFoldersPersistAndNewFoldersDoNotExpandExistingFolders() throws {
        let suiteName = "negaflow.folder-expansion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = "/library/first"
        let second = "/library/second"
        let newlyCreated = "/library/new"
        let store = LibraryFolderExpansionStore(defaults: defaults)

        store.toggle(first)
        store.toggle(second)

        XCTAssertFalse(store.isExpanded(first))
        XCTAssertFalse(store.isExpanded(second))
        XCTAssertTrue(store.isExpanded(newlyCreated))

        let restored = LibraryFolderExpansionStore(defaults: defaults)
        XCTAssertFalse(restored.isExpanded(first))
        XCTAssertFalse(restored.isExpanded(second))
        XCTAssertTrue(restored.isExpanded(newlyCreated))
    }
}
