import XCTest
@testable import negaflowApp

@MainActor
final class StackStoreTests: XCTestCase {
    func testCatalogRoundTripPreservesStacksAndHealthRejectsOverlap() throws {
        let first = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/stack-a.tiff"),
            filmType: .colorNegative
        )
        let second = ScanFrame(
            scanIndex: 2,
            rawScanURL: URL(fileURLWithPath: "/offline/stack-b.tiff"),
            filmType: .colorNegative
        )
        let third = ScanFrame(
            scanIndex: 3,
            rawScanURL: URL(fileURLWithPath: "/offline/stack-c.tiff"),
            filmType: .colorNegative
        )
        let firstStack = try XCTUnwrap(LibraryPhotoStack(frameIDs: [first.id, second.id]))
        let catalog = LibraryCatalog(
            frames: [first, second, third].map { LibraryFrameRecord(frame: $0) },
            stacks: [firstStack]
        )
        let data = try XCTUnwrap(LibraryCatalogFile.encode(catalog))
        let decoded = try XCTUnwrap(LibraryCatalogFile.decode(data))

        XCTAssertEqual(decoded.stacks, [firstStack])

        let overlap = try XCTUnwrap(LibraryPhotoStack(frameIDs: [second.id, third.id]))
        let unhealthy = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: catalog.frames,
            stacks: [firstStack, overlap]
        ))
        XCTAssertFalse(unhealthy.canOpenSafely)
        XCTAssertTrue(unhealthy.issues.contains {
            $0.code == .duplicateStackMembership && $0.frameID == second.id
        })
    }

    func testCreateRejectsOverlapAndCollapsedProjectionKeepsFirstVisibleMember() throws {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let store = StackStore()
        let stack = try XCTUnwrap(store.create(frameIDs: [first, second, third]))

        XCTAssertNil(store.create(frameIDs: [third, UUID()]))
        XCTAssertEqual(store.projectedFrameIDs([second, third]), [second])
        XCTAssertTrue(store.toggleCollapsed(id: stack.id))
        XCTAssertEqual(store.projectedFrameIDs([second, third]), [second, third])
    }

    func testRemovalDeletesOneMemberStackAndRestoresExactPosition() throws {
        let first = UUID()
        let second = UUID()
        let unrelated = try XCTUnwrap(LibraryPhotoStack(frameIDs: [UUID(), UUID()]))
        let store = StackStore()
        let affected = try XCTUnwrap(store.create(frameIDs: [first, second]))
        let createdUnrelated = try XCTUnwrap(store.create(frameIDs: unrelated.frameIDs))
        let delta = store.removalDelta(for: [first])

        store.removeFrameIDs([first])
        XCTAssertNil(store.stack(containing: second))
        XCTAssertTrue(store.restore(delta))
        XCTAssertEqual(store.stacks.map(\.id), [affected.id, createdUnrelated.id])
        XCTAssertEqual(store.stack(containing: first)?.frameIDs, [first, second])
    }

    func testRestoreFailsClosedWhenAffectedStackChangedAfterRemoval() throws {
        let first = UUID()
        let second = UUID()
        let store = StackStore()
        _ = try XCTUnwrap(store.create(frameIDs: [first, second]))
        let delta = store.removalDelta(for: [first])
        store.removeFrameIDs([first])
        _ = store.create(frameIDs: [second, UUID()])

        XCTAssertFalse(store.restore(delta))
    }

    func testLibraryRemovalUndoRestoresStackWithoutTouchingSources() throws {
        let first = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/undo-stack-a.tiff"),
            filmType: .colorNegative
        )
        let second = ScanFrame(
            scanIndex: 2,
            rawScanURL: URL(fileURLWithPath: "/offline/undo-stack-b.tiff"),
            filmType: .colorNegative
        )
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        model.frames = [first, second]
        let stack = try XCTUnwrap(model.createStack(frameIDs: [first.id, second.id]))

        model.removeFramesFromLibrary([first])
        XCTAssertTrue(model.stacks.isEmpty)

        undoManager.undo()
        XCTAssertEqual(model.frames.map(\.id), [first.id, second.id])
        XCTAssertEqual(model.stacks, [stack])
    }
}
