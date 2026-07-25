import XCTest
@testable import negaflowApp

@MainActor
final class DevelopOwnershipTests: XCTestCase {
    func testOwnershipUsesFrameIdentityInsteadOfOnlyUUID() {
        let model = AppModel()
        let id = UUID()
        let owned = Self.makeFrame(id: id)
        let detachedCopy = Self.makeFrame(id: id)
        model.frames = [owned]

        XCTAssertTrue(model.ownsFrame(owned))
        XCTAssertFalse(model.ownsFrame(detachedCopy))
    }

    func testOwnershipFallsBackToIdentityWhenDuplicateUUIDsAreExcludedFromIndex() {
        let model = AppModel()
        let id = UUID()
        let first = Self.makeFrame(id: id)
        let second = Self.makeFrame(id: id)
        let detachedCopy = Self.makeFrame(id: id)
        model.frames = [first, second]

        XCTAssertNil(model.uniqueLibraryFramesByID()[id])
        XCTAssertTrue(model.ownsFrame(first))
        XCTAssertTrue(model.ownsFrame(second))
        XCTAssertFalse(model.ownsFrame(detachedCopy))
    }

    func testDevelopIgnoresFrameRemovedFromStore() async {
        let model = AppModel()
        let frame = Self.makeFrame(id: UUID())
        let initialRevision = frame.developRevision

        await model.developFrame(frame)

        XCTAssertEqual(frame.developRevision, initialRevision)
        XCTAssertFalse(frame.isDeveloping)
        XCTAssertFalse(frame.hasDevelopedOnce)
    }

    func testSelectionBoundDevelopIgnoresDeselectedFrame() async {
        let model = AppModel()
        let frame = Self.makeFrame(id: UUID())
        model.frames = [frame]
        let initialRevision = frame.developRevision

        await model.developFrame(frame, selectionBoundFrameID: frame.id)

        XCTAssertEqual(frame.developRevision, initialRevision)
        XCTAssertFalse(frame.isDeveloping)
    }

    func testBasePickerIgnoresFrameRemovedFromStore() async {
        let model = AppModel()
        let frame = Self.makeFrame(id: UUID())
        model.statusMessage = "unchanged"

        model.pickFilmBase(at: CGPoint(x: 0.5, y: 0.5), frame: frame)
        await Task.yield()

        XCTAssertEqual(model.statusMessage, "unchanged")
        XCTAssertNil(frame.params.manualBaseRGB)
    }

    private static func makeFrame(id: UUID) -> ScanFrame {
        ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-develop-owner-\(UUID().uuidString).tiff"),
            filmType: .colorNegative,
            id: id
        )
    }
}
