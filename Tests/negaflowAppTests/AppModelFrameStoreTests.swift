import Combine
import XCTest
import AppKit
import Chromabase
@testable import negaflowApp

final class AppModelFrameStoreTests: XCTestCase {
    // cleaned-raw persist 가 사용자 머신의 실제/iCloud 폴더를 쓰지 않게 per-test temp 로 격리한다.
    private var cleanedRawIsolation: CleanedRawFolderIsolation?

    override func setUp() {
        super.setUp()
        cleanedRawIsolation = CleanedRawFolderIsolation()
    }

    override func tearDown() {
        cleanedRawIsolation?.restore()
        cleanedRawIsolation = nil
        super.tearDown()
    }

    @MainActor
    func testMostRecentAvailableFrameSelectionSkipsPreviewAndOfflineSources() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-recent-selection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let olderURL = directory.appendingPathComponent("older.tiff")
        let recentURL = directory.appendingPathComponent("recent.tiff")
        let previewURL = directory.appendingPathComponent("preview.tiff")
        try Data("older".utf8).write(to: olderURL)
        try Data("recent".utf8).write(to: recentURL)
        try Data("preview".utf8).write(to: previewURL)

        let older = ScanFrame(
            scanIndex: 1,
            rawScanURL: olderURL,
            filmType: .colorNegative,
            scannedAt: Date(timeIntervalSince1970: 100)
        )
        let recent = ScanFrame(
            scanIndex: 2,
            rawScanURL: recentURL,
            filmType: .colorNegative,
            scannedAt: Date(timeIntervalSince1970: 300)
        )
        let preview = ScanFrame(
            scanIndex: 3,
            rawScanURL: previewURL,
            filmType: .colorNegative,
            isPreviewScan: true,
            scannedAt: Date(timeIntervalSince1970: 400)
        )
        let offline = ScanFrame(
            scanIndex: 4,
            rawScanURL: directory.appendingPathComponent("offline.tiff"),
            filmType: .colorNegative,
            scannedAt: Date(timeIntervalSince1970: 500)
        )
        let model = AppModel()
        model.frames = [recent, older, preview, offline]
        model.updateInteractionScope(model.frames.map(\.id))

        XCTAssertTrue(model.selectMostRecentAvailableFrameIfNeeded())
        XCTAssertEqual(model.selectedFrameID, recent.id)
        XCTAssertFalse(model.selectMostRecentAvailableFrameIfNeeded())

        model.clearFrameSelection()
        model.updateInteractionScope([older.id])
        XCTAssertTrue(model.selectMostRecentAvailableFrameIfNeeded())
        XCTAssertEqual(model.selectedFrameID, older.id)
    }

    func testFramesFacadeUpdatesSelectedFrameAndResidency() async {
        await MainActor.run {
            let model = AppModel()
            let first = Self.makeFrame(index: 1)
            let second = Self.makeFrame(index: 2)

            model.frames = [first, second]
            model.selectedFrameID = second.id

            XCTAssertEqual(model.frames.map(\.id), [first.id, second.id])
            XCTAssertEqual(model.selectedFrame?.id, second.id)
            XCTAssertEqual(model.residentDevelopedIDs, [second.id])
        }
    }

    func testFrameFacadeForwardsObjectWillChange() async {
        await MainActor.run {
            let model = AppModel()
            var changeCount = 0
            let cancellable = model.objectWillChange.sink { changeCount += 1 }

            model.frames = [Self.makeFrame(index: 1)]

            XCTAssertGreaterThanOrEqual(changeCount, 1)
            withExtendedLifetime(cancellable) {}
        }
    }

    func testFrameStoreRepairsSelectionWhenSelectedFrameIsRemoved() async {
        await MainActor.run {
            let store = FrameStore()
            let first = Self.makeFrame(index: 1)
            let second = Self.makeFrame(index: 2)

            store.frames = [first, second]
            store.selectedFrameID = second.id
            store.frames.removeAll { $0.id == second.id }

            XCTAssertEqual(store.frames.map(\.id), [first.id])
            XCTAssertEqual(store.selectedFrameID, first.id)
            XCTAssertEqual(store.selectedFrame?.id, first.id)
        }
    }

    func testShiftRangeAndCommandToggleKeepAnActiveFrame() async {
        await MainActor.run {
            let model = AppModel()
            let first = Self.makeFrame(index: 1)
            let second = Self.makeFrame(index: 2)
            let third = Self.makeFrame(index: 3)
            let orderedIDs = [first.id, second.id, third.id]
            model.frames = [first, second, third]

            model.selectFrame(first, orderedFrameIDs: orderedIDs, modifiers: [])
            model.selectFrame(third, orderedFrameIDs: orderedIDs, modifiers: [.shift])
            XCTAssertEqual(model.selectedFrameIDs, Set(orderedIDs))
            XCTAssertEqual(model.selectedFrameID, third.id)

            model.selectFrame(second, orderedFrameIDs: orderedIDs, modifiers: [.command])
            XCTAssertEqual(model.selectedFrameIDs, Set([first.id, third.id]))
            XCTAssertEqual(model.selectedFrameID, third.id)
        }
    }

    func testSelectionModifiersCannotCarrySelectionAcrossInteractionScopes() async {
        await MainActor.run {
            let model = AppModel()
            let first = Self.makeFrame(index: 1)
            let second = Self.makeFrame(index: 2)
            let third = Self.makeFrame(index: 3)
            let fourth = Self.makeFrame(index: 4)
            model.frames = [first, second, third, fourth]

            model.selectFrame(first, orderedFrameIDs: [first.id, second.id], modifiers: [])
            model.selectFrame(second, orderedFrameIDs: [first.id, second.id], modifiers: [.command])
            XCTAssertEqual(model.selectedFrameIDs, Set([first.id, second.id]))

            model.selectFrame(fourth, orderedFrameIDs: [third.id, fourth.id], modifiers: [.shift])

            XCTAssertEqual(model.interactionFrameIDs, [third.id, fourth.id])
            XCTAssertEqual(model.selectedFrameIDs, Set([fourth.id]))
            XCTAssertEqual(model.selectedFrameID, fourth.id)
            XCTAssertEqual(model.frameSelectionAnchorID, fourth.id)

            model.selectFrame(third, orderedFrameIDs: [third.id, fourth.id], modifiers: [.command])
            XCTAssertEqual(model.selectedFrameIDs, Set([third.id, fourth.id]))
        }
    }

    func testInteractionScopeProjectsHiddenSelectionWithoutSelectingReplacement() async {
        await MainActor.run {
            let model = AppModel()
            let first = Self.makeFrame(index: 1)
            let second = Self.makeFrame(index: 2)
            let hidden = Self.makeFrame(index: 3)
            model.frames = [first, second, hidden]
            model.selectFrame(first, orderedFrameIDs: [first.id, second.id], modifiers: [])
            model.selectFrame(second, orderedFrameIDs: [first.id, second.id], modifiers: [.command])

            model.updateInteractionScope([hidden.id])

            XCTAssertEqual(model.interactionFrameIDs, [hidden.id])
            XCTAssertTrue(model.selectedFrameIDs.isEmpty)
            XCTAssertNil(model.selectedFrameID)
            XCTAssertNil(model.frameSelectionAnchorID)
            XCTAssertNil(model.actionableFrame)
            XCTAssertTrue(model.actionableSelectedFrames.isEmpty)
        }
    }

    func testInteractionScopeReanchorsToSurvivingActiveSelection() async {
        await MainActor.run {
            let model = AppModel()
            let first = Self.makeFrame(index: 1)
            let second = Self.makeFrame(index: 2)
            let third = Self.makeFrame(index: 3)
            model.frames = [first, second, third]
            model.selectFrame(first, orderedFrameIDs: [first.id, second.id, third.id], modifiers: [])
            model.selectFrame(second, orderedFrameIDs: [first.id, second.id, third.id], modifiers: [.command])
            model.frameSelectionAnchorID = first.id
            model.activateFrame(second.id)

            model.updateInteractionScope([second.id, third.id])

            XCTAssertEqual(model.selectedFrameIDs, [second.id])
            XCTAssertEqual(model.selectedFrameID, second.id)
            XCTAssertEqual(model.frameSelectionAnchorID, second.id)

            model.selectFrame(third, orderedFrameIDs: [second.id, third.id], modifiers: [.shift])

            XCTAssertEqual(model.selectedFrameIDs, [second.id, third.id])
            XCTAssertEqual(model.selectedFrameID, third.id)
        }
    }

    func testRemovalSelectsAdjacentFrameWithinInteractionScope() async {
        await MainActor.run {
            let model = AppModel()
            let first = Self.makeFrame(index: 1)
            let selected = Self.makeFrame(index: 2)
            let hiddenGlobalLast = Self.makeFrame(index: 3)
            model.frames = [first, selected, hiddenGlobalLast]
            model.selectFrame(
                selected,
                orderedFrameIDs: [first.id, selected.id],
                modifiers: []
            )

            model.removeFramesFromLibrary([selected], undoable: false)

            XCTAssertEqual(model.frames.map(\.id), [first.id, hiddenGlobalLast.id])
            XCTAssertEqual(model.interactionFrameIDs, [first.id])
            XCTAssertEqual(model.selectedFrameIDs, [first.id])
            XCTAssertEqual(model.selectedFrameID, first.id)
            XCTAssertEqual(model.frameSelectionAnchorID, first.id)
            XCTAssertEqual(model.actionableFrame?.id, first.id)
            XCTAssertFalse(model.residentDevelopedIDs.contains(hiddenGlobalLast.id))
        }
    }

    func testRemovalOfOnlyScopedFrameDoesNotActivateHiddenFrame() async {
        await MainActor.run {
            let model = AppModel()
            let visible = Self.makeFrame(index: 1)
            let hidden = Self.makeFrame(index: 2)
            model.frames = [visible, hidden]
            model.selectFrame(visible, orderedFrameIDs: [visible.id], modifiers: [])

            model.removeFramesFromLibrary([visible], undoable: false)

            XCTAssertEqual(model.frames.map(\.id), [hidden.id])
            XCTAssertTrue(model.interactionFrameIDs.isEmpty)
            XCTAssertTrue(model.selectedFrameIDs.isEmpty)
            XCTAssertNil(model.selectedFrameID)
            XCTAssertNil(model.frameSelectionAnchorID)
            XCTAssertNil(model.actionableFrame)
            XCTAssertFalse(model.residentDevelopedIDs.contains(hidden.id))
        }
    }

    func testRemovalDoesNotPromoteStaleHiddenSelection() async {
        await MainActor.run {
            let model = AppModel()
            let visible = Self.makeFrame(index: 1)
            let hidden = Self.makeFrame(index: 2)
            model.frames = [visible, hidden]
            model.updateInteractionScope([visible.id])
            model.selectedFrameIDs = [visible.id, hidden.id]
            model.activateFrame(visible.id)

            model.removeFramesFromLibrary([visible], undoable: false)

            XCTAssertEqual(model.frames.map(\.id), [hidden.id])
            XCTAssertTrue(model.interactionFrameIDs.isEmpty)
            XCTAssertTrue(model.selectedFrameIDs.isEmpty)
            XCTAssertNil(model.selectedFrameID)
            XCTAssertNil(model.frameSelectionAnchorID)
            XCTAssertNil(model.actionableFrame)
            XCTAssertFalse(model.residentDevelopedIDs.contains(hidden.id))
        }
    }

    func testHiddenProgrammaticSelectionLoadsOnlyAfterScopeExpansion() async {
        await MainActor.run {
            let model = AppModel()
            let visible = Self.makeFrame(index: 1)
            let programmatic = Self.makeFrame(index: 2)
            model.frames = [visible, programmatic]
            model.updateInteractionScope([visible.id])

            model.selectedFrameID = programmatic.id

            XCTAssertEqual(model.selectedFrameID, programmatic.id)
            XCTAssertNil(model.actionableFrame)
            XCTAssertFalse(model.residentDevelopedIDs.contains(programmatic.id))

            model.updateInteractionScope([visible.id, programmatic.id])

            XCTAssertEqual(model.actionableFrame?.id, programmatic.id)
            XCTAssertTrue(model.residentDevelopedIDs.contains(programmatic.id))
        }
    }

    func testProjectionReconciliationClearsProgrammaticSelectionOutsideUnchangedScope() async {
        await MainActor.run {
            let model = AppModel()
            let offlineVisible = Self.makeFrame(index: 1)
            let importedOnline = Self.makeFrame(index: 2)
            model.frames = [offlineVisible, importedOnline]
            model.updateInteractionScope([offlineVisible.id])
            model.selectedFrameID = importedOnline.id

            model.reconcileSelection(with: [offlineVisible.id])

            XCTAssertEqual(model.interactionFrameIDs, [offlineVisible.id])
            XCTAssertTrue(model.selectedFrameIDs.isEmpty)
            XCTAssertNil(model.selectedFrameID)
            XCTAssertNil(model.frameSelectionAnchorID)
            XCTAssertNil(model.actionableFrame)
        }
    }

    @MainActor
    func testRemovalUndoRestoresScopedSelectionWithoutSelectingHiddenFrame() {
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let first = Self.makeFrame(index: 1)
        let selected = Self.makeFrame(index: 2)
        let hidden = Self.makeFrame(index: 3)
        model.frames = [first, selected, hidden]
        model.selectFrame(
            selected,
            orderedFrameIDs: [first.id, selected.id],
            modifiers: []
        )

        model.removeFramesFromLibrary([selected])

        XCTAssertEqual(model.selectedFrameID, first.id)
        XCTAssertEqual(model.interactionFrameIDs, [first.id])
        XCTAssertFalse(model.selectedFrameIDs.contains(hidden.id))

        undoManager.undo()

        XCTAssertEqual(model.frames.map(\.id), [first.id, selected.id, hidden.id])
        XCTAssertEqual(model.interactionFrameIDs, [first.id, selected.id])
        XCTAssertEqual(model.selectedFrameIDs, [selected.id])
        XCTAssertEqual(model.selectedFrameID, selected.id)
        XCTAssertEqual(model.frameSelectionAnchorID, selected.id)
        XCTAssertEqual(model.actionableFrame?.id, selected.id)
        XCTAssertFalse(model.selectedFrameIDs.contains(hidden.id))
    }

    @MainActor
    func testRemovalUndoPreservesSelectionWhenScopeChangedAfterRemoval() {
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let removed = Self.makeFrame(index: 1)
        let currentVisible = Self.makeFrame(index: 2)
        model.frames = [removed, currentVisible]
        model.selectFrame(removed, orderedFrameIDs: [removed.id], modifiers: [])

        model.removeFramesFromLibrary([removed])
        model.selectFrame(currentVisible, orderedFrameIDs: [currentVisible.id], modifiers: [])

        undoManager.undo()

        XCTAssertEqual(model.frames.map(\.id), [removed.id, currentVisible.id])
        XCTAssertEqual(model.interactionFrameIDs, [currentVisible.id])
        XCTAssertEqual(model.selectedFrameIDs, [currentVisible.id])
        XCTAssertEqual(model.selectedFrameID, currentVisible.id)
        XCTAssertEqual(model.frameSelectionAnchorID, currentVisible.id)
        XCTAssertEqual(model.actionableFrame?.id, currentVisible.id)
        XCTAssertFalse(model.residentDevelopedIDs.contains(removed.id))
    }

    func testContextActionsUseExplicitScopeAndExcludeHiddenSelection() async {
        await MainActor.run {
            let model = AppModel()
            let first = Self.makeFrame(index: 1)
            let second = Self.makeFrame(index: 2)
            let third = Self.makeFrame(index: 3)
            model.frames = [first, second, third]
            model.selectFrame(first, orderedFrameIDs: [first.id, second.id, third.id], modifiers: [])
            model.selectFrame(second, orderedFrameIDs: [first.id, second.id, third.id], modifiers: [.command])

            XCTAssertEqual(
                model.framesForContextAction(first, within: [first.id]).map(\.id),
                [first.id]
            )
            XCTAssertEqual(
                model.framesForContextAction(first, within: [first.id, second.id]).map(\.id),
                [first.id, second.id]
            )
            XCTAssertTrue(
                model.framesForContextAction(first, within: [third.id]).isEmpty
            )
        }
    }

    func testActionableSelectionExcludesHiddenIDsEvenBeforeSelectionProjectionRuns() async {
        await MainActor.run {
            let model = AppModel()
            let visible = Self.makeFrame(index: 1)
            let hidden = Self.makeFrame(index: 2)
            model.frames = [visible, hidden]
            model.updateInteractionScope([visible.id])

            model.selectedFrameIDs = [visible.id, hidden.id]
            model.activateFrame(visible.id)

            XCTAssertEqual(model.selectedFrames.map(\.id), [visible.id, hidden.id])
            XCTAssertEqual(model.actionableSelectedFrames.map(\.id), [visible.id])
            XCTAssertEqual(model.actionableFrame?.id, visible.id)
        }
    }

    func testVirtualCopyCannotCreateSourceDeletionPlan() async {
        await MainActor.run {
            let model = AppModel()
            let original = Self.makeFrame(index: 1)
            let copy = original.makeVirtualCopy(copyNumber: 1)
            model.frames = [original, copy]

            XCTAssertNil(model.sourceDeletionPlan(for: [copy]))
        }
    }

    func testSourceDeletionPlanIncludesEveryFrameSharingTheFile() async {
        await MainActor.run {
            let model = AppModel()
            let original = Self.makeFrame(index: 1)
            let copy = original.makeVirtualCopy(copyNumber: 1)
            let duplicate = ScanFrame(
                scanIndex: 2,
                rawScanURL: original.rawScanURL,
                filmType: .colorNegative
            )
            model.frames = [original, copy, duplicate]

            let plan = model.sourceDeletionPlan(for: [original])

            XCTAssertEqual(plan?.sourceCount, 1)
            XCTAssertEqual(plan?.frameCount, 3)
            XCTAssertEqual(plan?.groups.first?.frameIDs, Set([original.id, copy.id, duplicate.id]))
        }
    }

    @MainActor
    func testScanRootCanBeRemovedFromLibraryAndIncludedInSourceDeletionPlan() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-protected-source-\(UUID().uuidString).tiff")
        try Data("protected".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: sourceURL,
            filmType: .colorNegative,
            scanSessionID: UUID(),
            scanJobID: UUID()
        )
        model.frames = [frame]

        XCTAssertNotNil(model.sourceDeletionPlan(for: [frame]))
        model.removeFramesFromLibrary([frame], undoable: false)
        XCTAssertTrue(model.frames.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @MainActor
    func testSourceDeletionPlanIsRejectedIfSharedCatalogSetChanges() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-stale-source-plan-\(UUID().uuidString).tiff")
        try Data("source".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let model = AppModel()
        let first = ScanFrame(
            scanIndex: 1,
            rawScanURL: sourceURL,
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        model.frames = [first]
        let plan = try XCTUnwrap(model.sourceDeletionPlan(for: [first]))
        let later = ScanFrame(
            scanIndex: 2,
            rawScanURL: sourceURL,
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        model.frames.append(later)

        await model.performSourceDeletion(plan)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(model.frames.map(\.id), [first.id, later.id])
        XCTAssertEqual(
            model.statusMessage,
            model.text(AppLocalizedPhrase.sourceDeletionPlanChangedStatus)
        )
    }

    func testRemoveFromLibraryKeepsSourceFile() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-remove-\(UUID().uuidString).tiff")
        try Data("source".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        await MainActor.run {
            let model = AppModel()
            let frame = ScanFrame(scanIndex: 1, rawScanURL: sourceURL, filmType: .colorNegative)
            model.frames = [frame]

            model.removeFramesFromLibrary([frame])

            XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
            XCTAssertTrue(model.frames.isEmpty)
        }
    }

    @MainActor
    func testUndoableLibraryRemovalRestoresOrderSelectionAndEditState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-remove-undo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstSource = directory.appendingPathComponent("first.tiff")
        let secondSource = directory.appendingPathComponent("second.tiff")
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)

        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager

        let first = ScanFrame(scanIndex: 1, rawScanURL: firstSource, filmType: .colorNegative)
        let second = ScanFrame(scanIndex: 2, rawScanURL: secondSource, filmType: .colorNegative)
        let cleanedCache = CleanedRawCacheFile.makeBuildURL(frameID: second.id)
        defer { try? FileManager.default.removeItem(at: cleanedCache) }
        try Data("cache".utf8).write(to: cleanedCache)
        second.customDisplayName = "edited frame"
        second.setRating(4)
        let copy = second.makeVirtualCopy(copyNumber: 1)
        second.defectEdits = [
            DefectEditItem(
                edit: .brush([]),
                title: "brush",
                summary: "",
                preview: [],
                baseSize: nil
            )
        ]
        second.cleanedRawDiskURL = cleanedCache
        model.frames = [first, second, copy]
        model.selectedFrameIDs = [second.id, copy.id]
        model.frameSelectionAnchorID = second.id
        model.activateFrame(copy.id)

        model.removeFramesFromLibrary([second, copy])

        XCTAssertEqual(model.frames.map(\.id), [first.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondSource.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanedCache.path))
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()

        XCTAssertEqual(model.frames.map(\.id), [first.id, second.id, copy.id])
        XCTAssertTrue(model.frames[1] === second)
        XCTAssertTrue(model.frames[2] === copy)
        XCTAssertEqual(model.selectedFrameIDs, [second.id, copy.id])
        XCTAssertEqual(model.selectedFrameID, copy.id)
        XCTAssertEqual(model.frameSelectionAnchorID, second.id)
        XCTAssertEqual(second.customDisplayName, "edited frame")
        XCTAssertEqual(second.rating, 4)
        XCTAssertEqual(second.defectEdits.count, 1)
        XCTAssertEqual(copy.rootFrameID, second.rootFrameID)
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()

        XCTAssertEqual(model.frames.map(\.id), [first.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondSource.path))
        XCTAssertTrue(undoManager.canUndo)
    }

    func testNonUndoableRemovalDoesNotPolluteCatalogUndoHistory() async {
        await MainActor.run {
            let model = AppModel()
            let undoManager = UndoManager()
            model.catalogUndoManager = undoManager
            let preview = Self.makeFrame(index: 1)
            model.frames = [preview]

            model.removeFramesFromLibrary([preview], undoable: false)

            XCTAssertTrue(model.frames.isEmpty)
            XCTAssertFalse(undoManager.canUndo)
        }
    }

    @MainActor
    func testFolderRemovalUndoRestoresFolderRegistrationAndFrame() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-folder-remove-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let folder = LibraryFolder(url: directory)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: directory.appendingPathComponent("scan.tiff"),
            filmType: .colorNegative
        )
        model.libraryFolders = [folder]
        model.frames = [frame]

        model.removeLibraryFolder(folder)

        XCTAssertTrue(model.libraryFolders.isEmpty)
        XCTAssertTrue(model.frames.isEmpty)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()

        XCTAssertEqual(model.libraryFolders, [folder])
        XCTAssertEqual(model.frames.map(\.id), [frame.id])
    }

    @MainActor
    func testFolderRemovalAllowsScanRootAndKeepsSourceFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-protected-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel()
        let folder = LibraryFolder(url: directory)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: directory.appendingPathComponent("scan.tiff"),
            filmType: .colorNegative,
            scanSessionID: UUID(),
            scanJobID: UUID()
        )
        try Data("scan".utf8).write(to: frame.rawScanURL)
        model.libraryFolders = [folder]
        model.frames = [frame]

        model.removeLibraryFolder(folder)

        XCTAssertTrue(model.libraryFolders.isEmpty)
        XCTAssertTrue(model.frames.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: frame.rawScanURL.path))
    }

    @MainActor
    private static func makeFrame(index: Int) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-test-\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
    }
}
