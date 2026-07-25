import XCTest
@testable import negaflowApp

@MainActor
final class WorkspacePresentationStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "WorkspacePresentationStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testPresentationStatePersistsWithoutCatalogData() {
        let activeFrameID = UUID()
        let store = WorkspacePresentationStore(defaults: defaults)
        store.module = .library
        store.sidebarTab = .output
        store.searchText = "portra 400"
        store.recordActiveFrameID(activeFrameID)

        let restored = WorkspacePresentationStore(defaults: defaults)
        XCTAssertEqual(restored.module, .library)
        XCTAssertEqual(restored.sidebarTab, .output)
        XCTAssertEqual(restored.searchText, "portra 400")
        XCTAssertEqual(restored.activeFrameID, activeFrameID)
    }

    func testPrintModulePersistsWithoutCatalogData() {
        let store = WorkspacePresentationStore(defaults: defaults)
        store.module = .print

        XCTAssertEqual(WorkspacePresentationStore(defaults: defaults).module, .print)
    }

    func testInvalidEnumAndFrameValuesFallBackSafely() {
        defaults.set("missing-module", forKey: "workspace.module")
        defaults.set("missing-tab", forKey: "workspace.sidebarTab")
        defaults.set("not-a-uuid", forKey: "workspace.activeFrameID")

        let store = WorkspacePresentationStore(defaults: defaults)
        XCTAssertEqual(store.module, .develop)
        XCTAssertEqual(store.sidebarTab, .library)
        XCTAssertNil(store.activeFrameID)
    }

    func testActiveFrameRestoresOnlyForExactOnlineCatalogMember() {
        let expected = UUID()
        let other = UUID()
        let store = WorkspacePresentationStore(defaults: defaults)
        store.recordActiveFrameID(expected)

        XCTAssertEqual(
            store.restorableActiveFrameID(
                availableFrameIDs: [expected, other],
                sourceAvailableFrameIDs: [expected]
            ),
            expected
        )
        XCTAssertNil(store.restorableActiveFrameID(
            availableFrameIDs: [expected, other],
            sourceAvailableFrameIDs: [other]
        ))
        XCTAssertNil(store.restorableActiveFrameID(
            availableFrameIDs: [other],
            sourceAvailableFrameIDs: [other]
        ))
    }

    func testDiscardStaleFrameDoesNotSelectReplacement() {
        let store = WorkspacePresentationStore(defaults: defaults)
        store.recordActiveFrameID(UUID())

        store.discardStaleActiveFrame()

        XCTAssertNil(store.activeFrameID)
        XCTAssertNil(defaults.string(forKey: "workspace.activeFrameID"))
    }
}
