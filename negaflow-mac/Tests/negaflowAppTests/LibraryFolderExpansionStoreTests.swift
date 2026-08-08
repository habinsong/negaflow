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

    /// 사이드바 파일 목록과 사진 격자는 접힘을 따로 기억한다. 한 키를 나눠 쓰면 격자에서
    /// 썸네일을 접는 순간 사이드바의 파일 목록까지 사라진다.
    func testGridCollapseIsRememberedSeparatelyFromTheFileList() throws {
        let suiteName = "negaflow.folder-expansion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folder = "/library/roll"
        let tree = LibraryFolderExpansionStore(defaults: defaults)
        let grid = LibraryFolderExpansionStore(
            defaults: defaults,
            defaultsKey: LibraryFolderExpansionStore.gridDefaultsKey
        )

        grid.toggle(folder)

        XCTAssertFalse(grid.isExpanded(folder))
        XCTAssertTrue(tree.isExpanded(folder))

        let restoredTree = LibraryFolderExpansionStore(defaults: defaults)
        let restoredGrid = LibraryFolderExpansionStore(
            defaults: defaults,
            defaultsKey: LibraryFolderExpansionStore.gridDefaultsKey
        )
        XCTAssertTrue(restoredTree.isExpanded(folder))
        XCTAssertFalse(restoredGrid.isExpanded(folder))
    }
}
