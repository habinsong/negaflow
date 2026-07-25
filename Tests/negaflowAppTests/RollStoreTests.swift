import AppKit
import Chromabase
import XCTest
@testable import negaflowApp

@MainActor
final class RollStoreTests: XCTestCase {
    func testNewPersistentFramesRequireExplicitAssignment() throws {
        let model = AppModel()
        let first = makeFrame(index: 1, scannedAt: Date(timeIntervalSince1970: 20))
        let second = makeFrame(index: 2, scannedAt: Date(timeIntervalSince1970: 10))
        model.frames = [first, second]

        XCTAssertTrue(model.rolls.isEmpty)
        XCTAssertNil(model.rollID(containing: first.id))

        let physical = try XCTUnwrap(model.createPhysicalRoll(
            name: "  Portra 400  ",
            filmType: .colorNegative,
            createdAt: Date(timeIntervalSince1970: 5)
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([first], toRollID: physical.id))
        XCTAssertTrue(model.assignNewPersistentFrames([second]))
        XCTAssertFalse(model.assignNewPersistentFrames([first]))

        XCTAssertEqual(model.rolls[0].name, "Portra 400")
        XCTAssertEqual(model.rolls[0].frameIDs, [first.id])
        XCTAssertEqual(model.rolls[1].kind, .unassigned)
        XCTAssertEqual(model.rolls[1].frameIDs, [second.id])
        XCTAssertNil(model.activeRollID)
        XCTAssertFalse(model.activatePhysicalRoll(id: LibraryRoll.unassignedID))
        XCTAssertTrue(model.activatePhysicalRoll(id: physical.id))

        let globalIDs = model.frames.map(\.id)
        let sourcePaths = model.frames.map { $0.rawScanURL.path }
        XCTAssertTrue(model.deletePhysicalRoll(id: physical.id))

        XCTAssertEqual(model.frames.map(\.id), globalIDs)
        XCTAssertEqual(model.frames.map { $0.rawScanURL.path }, sourcePaths)
        XCTAssertEqual(model.rolls.map(\.id), [LibraryRoll.unassignedID])
        XCTAssertEqual(model.rolls[0].frameIDs, [second.id, first.id])
        XCTAssertNil(model.activeRollID)

        let empty = try XCTUnwrap(model.createPhysicalRoll(
            name: "Empty",
            filmType: .colorNegative
        ))
        XCTAssertEqual(
            model.rolls.first(where: { $0.id == empty.id })?.frameIDs,
            []
        )
    }

    func testVirtualCopyIsInsertedImmediatelyAfterSourceInSameRoll() throws {
        let model = AppModel()
        let original = makeFrame(index: 1)
        let sibling = makeFrame(index: 2)
        model.frames = [original, sibling]
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Roll 1",
            filmType: .colorNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original, sibling], toRollID: roll.id))

        model.createVirtualCopy(from: original)

        XCTAssertEqual(model.frames.count, 3)
        let copy = model.frames[1]
        XCTAssertTrue(copy.isVirtualCopy)
        XCTAssertEqual(copy.rootFrameID, original.id)
        XCTAssertEqual(model.frames.map(\.id), [original.id, copy.id, sibling.id])
        XCTAssertEqual(model.rolls[0].frameIDs, [original.id, copy.id, sibling.id])
        XCTAssertEqual(model.rollID(containing: copy.id), roll.id)
    }

    func testMultipleVirtualCopiesStayInCopyNumberOrderAcrossFramesAndRoll() throws {
        let model = AppModel()
        let original = makeFrame(index: 1)
        model.frames = [original]
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Roll",
            filmType: .colorNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original], toRollID: roll.id))

        model.createVirtualCopy(from: original)
        model.createVirtualCopy(from: original)

        XCTAssertEqual(model.frames.map(\.virtualCopyNumber), [nil, 1, 2])
        XCTAssertEqual(model.rolls[0].frameIDs, model.frames.map(\.id))
    }

    func testVirtualCopyPreservesImmutableScanProvenance() {
        let sessionID = UUID()
        let jobID = UUID()
        let original = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/scanned.tiff"),
            filmType: .colorNegative,
            scanSessionID: sessionID,
            scanJobID: jobID
        )

        let copy = original.makeVirtualCopy(copyNumber: 1)

        XCTAssertEqual(copy.scanSessionID, sessionID)
        XCTAssertEqual(copy.scanJobID, jobID)
        XCTAssertEqual(copy.rootFrameID, original.id)
    }

    func testOriginalRemovalIncludesCopiesAndUndoPreservesUnrelatedRollChanges() throws {
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let original = makeFrame(index: 1)
        let sibling = makeFrame(index: 2)
        model.frames = [original, sibling]
        let firstRoll = try XCTUnwrap(model.createPhysicalRoll(
            name: "First",
            filmType: .colorNegative
        ))
        let secondRoll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Second",
            filmType: .bwNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original, sibling], toRollID: firstRoll.id))
        model.createVirtualCopy(from: original)
        let copy = try XCTUnwrap(model.frames.first(where: { $0.isVirtualCopy }))

        model.removeFramesFromLibrary([original])

        XCTAssertEqual(model.frames.map(\.id), [sibling.id])
        XCTAssertEqual(
            model.rolls.first(where: { $0.id == firstRoll.id })?.frameIDs,
            [sibling.id]
        )

        XCTAssertTrue(model.renamePhysicalRoll(id: firstRoll.id, name: "Renamed first"))
        XCTAssertTrue(model.renamePhysicalRoll(id: secondRoll.id, name: "Renamed second"))
        let laterRoll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Created later",
            filmType: .colorPositive
        ))
        XCTAssertTrue(model.activatePhysicalRoll(id: secondRoll.id))

        undoManager.undo()

        XCTAssertEqual(model.frames.map(\.id), [original.id, copy.id, sibling.id])
        XCTAssertEqual(
            model.rolls.first(where: { $0.id == firstRoll.id })?.frameIDs,
            [original.id, copy.id, sibling.id]
        )
        XCTAssertEqual(
            model.rolls.first(where: { $0.id == firstRoll.id })?.name,
            "Renamed first"
        )
        XCTAssertEqual(
            model.rolls.first(where: { $0.id == secondRoll.id })?.name,
            "Renamed second"
        )
        XCTAssertNotNil(model.rolls.first(where: { $0.id == laterRoll.id }))
        XCTAssertEqual(model.activeRollID, secondRoll.id)

        undoManager.redo()

        XCTAssertEqual(model.frames.map(\.id), [sibling.id])
        XCTAssertEqual(
            model.rolls.first(where: { $0.id == firstRoll.id })?.frameIDs,
            [sibling.id]
        )
        XCTAssertEqual(
            model.rolls.first(where: { $0.id == firstRoll.id })?.name,
            "Renamed first"
        )
        XCTAssertEqual(
            model.rolls.first(where: { $0.id == secondRoll.id })?.name,
            "Renamed second"
        )
        XCTAssertNotNil(model.rolls.first(where: { $0.id == laterRoll.id }))
        XCTAssertEqual(model.activeRollID, secondRoll.id)
    }

    func testVirtualCopyCanBeRemovedWithoutRemovingOriginal() throws {
        let model = AppModel()
        let original = makeFrame(index: 1)
        model.frames = [original]
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Roll",
            filmType: .colorNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original], toRollID: roll.id))
        model.createVirtualCopy(from: original)
        let copy = try XCTUnwrap(model.frames.first(where: { $0.isVirtualCopy }))

        model.removeFramesFromLibrary([copy], undoable: false)

        XCTAssertEqual(model.frames.map(\.id), [original.id])
        XCTAssertEqual(model.rolls[0].frameIDs, [original.id])
    }

    func testScanProvenanceRollIsProtectedButRootRemovalIsAllowed() throws {
        let model = AppModel()
        let sessionID = UUID()
        let jobID = UUID()
        let original = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/protected-scan.tiff"),
            filmType: .colorNegative,
            scanSessionID: sessionID,
            scanJobID: jobID
        )
        model.frames = [original]
        let source = try XCTUnwrap(model.createPhysicalRoll(
            name: "Capture Roll",
            filmType: .colorNegative
        ))
        let target = try XCTUnwrap(model.createPhysicalRoll(
            name: "Target",
            filmType: .colorNegative
        ))
        let unrelated = try XCTUnwrap(model.createPhysicalRoll(
            name: "Unrelated",
            filmType: .bwNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original], toRollID: source.id))
        model.scanRollAssignments = [LibraryScanRollAssignment(
            sessionID: sessionID,
            rollID: source.id,
            draftName: "Capture Roll",
            filmType: .colorNegative,
            createdAt: Date(timeIntervalSince1970: 1)
        )]
        model.createVirtualCopy(from: original)
        let copy = try XCTUnwrap(model.frames.first(where: { $0.isVirtualCopy }))

        model.removeFramesFromLibrary([copy], undoable: false)
        XCTAssertEqual(model.frames.map(\.id), [original.id])
        XCTAssertTrue(model.moveOriginalFrameFamily(containing: original, toRollID: source.id))
        XCTAssertFalse(model.moveOriginalFrameFamily(containing: original, toRollID: target.id))
        XCTAssertEqual(model.rollID(containing: original.id), source.id)
        XCTAssertFalse(model.deletePhysicalRoll(id: source.id))
        XCTAssertTrue(model.renamePhysicalRoll(id: source.id, name: "Renamed Capture"))
        XCTAssertTrue(model.deletePhysicalRoll(id: unrelated.id))

        model.removeFramesFromLibrary([original], undoable: false)
        XCTAssertTrue(model.frames.isEmpty)
    }

    func testCopyOnlyRemovalUndoFollowsLivingRootFamilyCurrentRoll() throws {
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let original = makeFrame(index: 1)
        model.frames = [original]
        let source = try XCTUnwrap(model.createPhysicalRoll(
            name: "Source",
            filmType: .colorNegative
        ))
        let target = try XCTUnwrap(model.createPhysicalRoll(
            name: "Target",
            filmType: .colorNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original], toRollID: source.id))
        model.createVirtualCopy(from: original)
        let copy = try XCTUnwrap(model.frames.first(where: { $0.isVirtualCopy }))

        model.removeFramesFromLibrary([copy])
        XCTAssertTrue(model.moveOriginalFrameFamily(containing: original, toRollID: target.id))
        undoManager.undo()

        XCTAssertEqual(model.frames.map(\.id), [original.id, copy.id])
        XCTAssertEqual(model.rollID(containing: original.id), target.id)
        XCTAssertEqual(model.rollID(containing: copy.id), target.id)
        let report = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: model.frames.map { LibraryFrameRecord(frame: $0) },
            rolls: model.rolls
        ))
        XCTAssertTrue(report.canOpenSafely)
        XCTAssertFalse(report.issues.contains { $0.code == .splitVirtualCopyFamily })
    }

    func testRedoRecapturesCurrentMembershipForFollowingUndo() throws {
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let original = makeFrame(index: 1)
        model.frames = [original]
        let source = try XCTUnwrap(model.createPhysicalRoll(
            name: "Source",
            filmType: .colorNegative
        ))
        let target = try XCTUnwrap(model.createPhysicalRoll(
            name: "Target",
            filmType: .colorNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original], toRollID: source.id))

        model.removeFramesFromLibrary([original])
        undoManager.undo()
        XCTAssertTrue(model.moveOriginalFrameFamily(containing: original, toRollID: target.id))

        undoManager.redo()
        XCTAssertTrue(model.frames.isEmpty)
        undoManager.undo()

        XCTAssertEqual(model.frames.map(\.id), [original.id])
        XCTAssertEqual(model.rollID(containing: original.id), target.id)
    }

    func testSuccessfulSourceTrashInvalidatesStaleCatalogUndoHistory() throws {
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let original = makeFrame(index: 1)
        model.frames = [original]
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Roll",
            filmType: .colorNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original], toRollID: roll.id))
        model.removeFramesFromLibrary([original])
        undoManager.undo()
        XCTAssertTrue(undoManager.canRedo)

        model.invalidateCatalogUndoHistoryAfterSourceTrash()

        XCTAssertFalse(undoManager.canUndo)
        XCTAssertFalse(undoManager.canRedo)
    }

    func testUndoRecreatesRemovedUnassignedWithoutOverwritingLaterState() throws {
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let original = makeFrame(index: 1, scannedAt: Date(timeIntervalSince1970: 10))
        model.frames = [original]
        XCTAssertTrue(model.assignNewPersistentFrames([original]))

        model.removeFramesFromLibrary([original])
        XCTAssertTrue(model.rolls.isEmpty)

        let later = makeFrame(index: 2, scannedAt: Date(timeIntervalSince1970: 20))
        model.frames.append(later)
        XCTAssertTrue(model.assignNewPersistentFrames([later]))
        let physical = try XCTUnwrap(model.createPhysicalRoll(
            name: "Unrelated",
            filmType: .bwNegative
        ))
        XCTAssertTrue(model.activatePhysicalRoll(id: physical.id))

        undoManager.undo()

        XCTAssertEqual(model.frames.map(\.id), [original.id, later.id])
        let unassigned = try XCTUnwrap(model.rolls.first(where: { $0.kind == .unassigned }))
        XCTAssertEqual(unassigned.createdAt, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(unassigned.frameIDs, [original.id, later.id])
        XCTAssertEqual(model.rolls.map(\.id), [LibraryRoll.unassignedID, physical.id])
        XCTAssertNotNil(model.rolls.first(where: { $0.id == physical.id }))
        XCTAssertEqual(model.activeRollID, physical.id)
    }

    func testFailedMembershipRestoreIsTransactional() throws {
        let model = AppModel()
        let original = makeFrame(index: 1)
        model.frames = [original]
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Roll",
            filmType: .colorNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original], toRollID: roll.id))
        let delta = model.rollStore.removalDelta(for: [original.id])
        model.rollStore.removeFrameIDs([original.id])
        let before = model.rollStateSnapshot()

        XCTAssertFalse(model.rollStore.restoreMemberships(
            from: delta,
            targetRollByFrameID: [original.id: UUID()]
        ))
        XCTAssertEqual(model.rollStateSnapshot(), before)
    }

    func testMoveFamilyAndLibraryOrganizationRemainAvailableDuringScan() throws {
        let model = AppModel()
        let original = makeFrame(index: 7)
        model.frames = [original]
        let source = try XCTUnwrap(model.createPhysicalRoll(
            name: "Source",
            filmType: .colorNegative
        ))
        let target = try XCTUnwrap(model.createPhysicalRoll(
            name: "Target",
            filmType: .colorNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original], toRollID: source.id))
        model.createVirtualCopy(from: original)
        let globalIDs = model.frames.map(\.id)
        let scanIndexes = model.frames.map(\.scanIndex)
        let sourcePaths = model.frames.map { $0.rawScanURL.path }

        XCTAssertTrue(model.moveOriginalFrameFamily(containing: original, toRollID: target.id))
        XCTAssertEqual(model.frames.map(\.id), globalIDs)
        XCTAssertEqual(model.frames.map(\.scanIndex), scanIndexes)
        XCTAssertEqual(model.frames.map { $0.rawScanURL.path }, sourcePaths)
        XCTAssertEqual(
            model.rolls.first(where: { $0.id == target.id })?.frameIDs,
            globalIDs
        )

        XCTAssertTrue(model.activatePhysicalRoll(id: target.id))
        model.isScanning = true
        XCTAssertTrue(model.renamePhysicalRoll(id: target.id, name: "Renamed"))
        XCTAssertTrue(model.activatePhysicalRoll(id: source.id))
        XCTAssertTrue(model.moveOriginalFrameFamily(containing: original, toRollID: source.id))
        model.removeFramesFromLibrary([original], undoable: false)
        XCTAssertTrue(model.frames.isEmpty)
        XCTAssertTrue(model.deletePhysicalRoll(id: source.id))
    }

    func testLifecycleGateBlocksPersistentMutationsDuringRestoreAndBlockedState() throws {
        let model = AppModel()
        let original = makeFrame(index: 1)
        model.frames = [original]
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Roll",
            filmType: .colorNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original], toRollID: roll.id))

        model.transitionLibraryLifecycle(to: .restoring)
        XCTAssertFalse(model.allowsLibraryMutation)
        XCTAssertNil(model.createPhysicalRoll(name: "Blocked", filmType: .colorNegative))
        XCTAssertFalse(model.renamePhysicalRoll(id: roll.id, name: "Blocked"))
        model.createVirtualCopy(from: original)
        model.removeFramesFromLibrary([original], undoable: false)
        model.importImages(urls: [URL(fileURLWithPath: "/tmp/blocked-import.jpg")])
        XCTAssertEqual(model.frames.map(\.id), [original.id])
        XCTAssertEqual(model.rolls.count, 1)

        model.transitionLibraryLifecycle(to: .blocked)
        XCTAssertFalse(model.deletePhysicalRoll(id: roll.id))
        XCTAssertEqual(model.frames.map(\.id), [original.id])

        model.transitionLibraryLifecycle(to: .ready)
        XCTAssertTrue(model.renamePhysicalRoll(id: roll.id, name: "Ready"))
    }

    func testSaveFailsClosedBeforeWritingSplitVirtualCopyFamily() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-roll-health-save-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = root.appendingPathComponent("library.json")
        let model = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        let original = makeFrame(index: 1)
        let copy = original.makeVirtualCopy(copyNumber: 1)
        model.frames = [original, copy]
        let first = try XCTUnwrap(LibraryRoll.physical(
            name: "First",
            filmType: .colorNegative,
            frameIDs: [original.id]
        ))
        let second = try XCTUnwrap(LibraryRoll.physical(
            name: "Second",
            filmType: .colorNegative,
            frameIDs: [copy.id]
        ))
        model.replaceRollState(with: RollStoreSnapshot(
            rolls: [first, second],
            activeRollID: nil
        ))
        model.libraryPersistenceEnabled = true
        defer {
            model.libraryPersistenceEnabled = false
            model.librarySaveTask?.cancel()
            model.librarySaveTask = nil
        }

        XCTAssertFalse(model.saveLibrary(synchronous: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: catalogURL.path))
    }

    func testCatalogSaveAndRestorePreservesRollsAndActiveRoll() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-roll-store-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = root.appendingPathComponent("library.json")
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        let model = AppModel(
            libraryCatalogURL: catalog,
            libraryDefectDirectoryURL: defects,
            libraryBackupDirectoryURL: backups
        )
        let frame = makeFrame(index: 1)
        model.frames = [frame]
        model.libraryPersistenceEnabled = true
        XCTAssertFalse(model.saveLibrary(synchronous: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: catalog.path))
        model.libraryPersistenceEnabled = false
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Persisted",
            filmType: .colorNegative,
            activate: true,
            createdAt: Date(timeIntervalSince1970: 30)
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([frame], toRollID: roll.id))
        model.libraryPersistenceEnabled = true
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        model.libraryPersistenceEnabled = false
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil

        let restored = AppModel(
            libraryCatalogURL: catalog,
            libraryDefectDirectoryURL: defects,
            libraryBackupDirectoryURL: backups
        )
        await restored.restoreLibraryOnLaunch()
        defer {
            restored.libraryPersistenceEnabled = false
            restored.librarySaveTask?.cancel()
            restored.librarySaveTask = nil
        }

        XCTAssertEqual(restored.frames.map(\.id), [frame.id])
        XCTAssertEqual(restored.rolls, model.rolls)
        XCTAssertEqual(restored.activeRollID, roll.id)
        XCTAssertEqual(restored.rollID(containing: frame.id), roll.id)
        XCTAssertEqual(restored.libraryLifecycleState, .ready)
        XCTAssertTrue(restored.allowsLibraryMutation)
    }

    private func makeFrame(
        index: Int,
        scannedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: URL(fileURLWithPath: "/offline/roll-\(UUID().uuidString).tiff"),
            filmType: .colorNegative,
            scannedAt: scannedAt
        )
    }
}
