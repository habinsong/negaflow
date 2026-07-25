import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class LibraryCollectionStoreTests: XCTestCase {
    func testEmptyFrameCatalogRestoresOrganizerBeforeEarlyReturn() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-empty-organizer-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let catalogURL = root.appendingPathComponent("library.json")
        let envelope = try searchEnvelope(query: LibraryQuery())
        let manual = LibraryManualCollection(id: UUID(), name: "Empty", frameIDs: [])
        let smart = LibrarySmartCollection(id: UUID(), name: "All", definition: envelope)
        let saved = LibrarySavedSearch(id: UUID(), name: "All Search", definition: envelope)
        try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog(
            manualCollections: [manual],
            smartCollections: [smart],
            savedSearches: [saved]
        ))).write(to: catalogURL, options: .atomic)
        let model = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )

        await model.restoreLibraryOnLaunch()

        XCTAssertTrue(model.frames.isEmpty)
        XCTAssertEqual(model.manualCollections, [manual])
        XCTAssertEqual(model.smartCollections, [smart])
        XCTAssertEqual(model.savedSearches, [saved])
        XCTAssertEqual(model.libraryLifecycleState, .ready)
    }

    func testAcknowledgedCommitPreservesOrganizerAndQueuesTransactionMutation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-organizer-ack-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = root.appendingPathComponent("library.json")
        let model = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        await model.restoreLibraryOnLaunch()
        let definition = LibrarySearchDefinition(
            query: LibraryQuery(),
            sort: LibrarySortDescriptor(key: .inputOrder, ascending: true)
        )
        _ = try XCTUnwrap(model.createManualCollection(named: "Empty"))
        _ = try XCTUnwrap(model.createSmartCollection(named: "All", definition: definition))
        _ = try XCTUnwrap(model.createSavedSearch(named: "All Search", definition: definition))
        XCTAssertTrue(model.beginAcknowledgedLibraryTransaction())
        _ = try XCTUnwrap(model.createManualCollection(named: "During Transaction"))
        XCTAssertTrue(model.librarySaveRequestedDuringTransaction)

        guard case .success = model.commitAcknowledgedLibrarySnapshot(
            frames: [],
            rolls: [],
            activeRollID: nil,
            scanSessions: [],
            scanRollAssignments: []
        ) else {
            return XCTFail("organizer snapshot should commit")
        }
        model.endAcknowledgedLibraryTransaction()

        let catalog = try XCTUnwrap(
            LibraryCatalogFile.decode(Data(contentsOf: catalogURL))
        )
        XCTAssertEqual(catalog.manualCollections.map(\.name), ["Empty", "During Transaction"])
        XCTAssertEqual(catalog.smartCollections.map(\.name), ["All"])
        XCTAssertEqual(catalog.savedSearches.map(\.name), ["All Search"])
    }

    func testRestoreSaveAndQueryContextPreserveOrganizerStateAndRawDamage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-collection-restore-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let catalogURL = root.appendingPathComponent("library.json")
        let member = makeFrame(index: 1, root: root)
        let nonmember = makeFrame(index: 2, root: root)
        let validDefinition = try searchEnvelope(query: LibraryQuery(conditions: [
            .rating(comparison: .greaterThanOrEqual, value: 4),
        ]))
        let damagedPayload = #"{"version":1,"query":{"version":999}}"#
        let manual = LibraryManualCollection(
            id: UUID(),
            name: "Portfolio",
            frameIDs: [member.id]
        )
        let smart = LibrarySmartCollection(
            id: UUID(),
            name: "Four Stars",
            definition: validDefinition
        )
        let saved = LibrarySavedSearch(
            id: UUID(),
            name: "Damaged",
            definition: LibraryStoredSearchEnvelope(payloadJSON: damagedPayload)
        )
        let records = [member, nonmember].map(LibraryFrameRecord.init(frame:))
        let catalog = LibraryCatalog(
            frames: records,
            rolls: [LibraryRoll.unassigned(
                createdAt: member.scannedAt,
                frameIDs: [member.id, nonmember.id]
            )],
            manualCollections: [manual],
            smartCollections: [smart],
            savedSearches: [saved]
        )
        try XCTUnwrap(LibraryCatalogFile.encode(catalog)).write(
            to: catalogURL,
            options: .atomic
        )
        let model = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )

        await model.restoreLibraryOnLaunch()

        XCTAssertEqual(model.manualCollections, [manual])
        XCTAssertEqual(model.smartCollections, [smart])
        XCTAssertEqual(model.savedSearches, [saved])
        let context = model.makeLibraryQueryContext()
        XCTAssertEqual(context.factsByFrameID[member.id]?.textValues[.collection], ["portfolio"])
        XCTAssertEqual(context.factsByFrameID[nonmember.id]?.textValues[.collection], [])
        XCTAssertFalse(context.factsByFrameID[member.id]?.unknownTextFields.contains(.collection) ?? true)
        XCTAssertFalse(context.factsByFrameID[nonmember.id]?.unknownTextFields.contains(.collection) ?? true)

        XCTAssertTrue(model.saveLibrary(synchronous: true))
        let savedCatalog = try XCTUnwrap(
            LibraryCatalogFile.decode(Data(contentsOf: catalogURL))
        )
        XCTAssertEqual(savedCatalog.manualCollections, [manual])
        XCTAssertEqual(savedCatalog.smartCollections, [smart])
        XCTAssertEqual(savedCatalog.savedSearches.first?.definition.payloadJSON, damagedPayload)
    }

    func testFrameRemovalUndoRestoresManualMembershipAtExactIndices() throws {
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let first = makeFrame(index: 1)
        let second = makeFrame(index: 2)
        let third = makeFrame(index: 3)
        model.frames = [first, second, third]
        let collectionID = try XCTUnwrap(model.createManualCollection(
            named: "Sequence",
            frameIDs: [first.id, second.id, third.id]
        ))
        undoManager.removeAllActions()

        model.removeFramesFromLibrary([second])

        XCTAssertEqual(model.manualCollections.first?.frameIDs, [first.id, third.id])
        undoManager.undo()
        XCTAssertEqual(model.frames.map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(model.manualCollections.first?.frameIDs, [first.id, second.id, third.id])

        undoManager.redo()
        XCTAssertEqual(model.frames.map(\.id), [first.id, third.id])
        XCTAssertEqual(model.manualCollections.first?.id, collectionID)
        XCTAssertEqual(model.manualCollections.first?.frameIDs, [first.id, third.id])
    }

    func testFrameRemovalUndoPreservesLaterMembershipAndDoesNotRecreateDeletedCollection() throws {
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let first = makeFrame(index: 1)
        let second = makeFrame(index: 2)
        let later = makeFrame(index: 3)
        model.frames = [first, second, later]
        _ = try XCTUnwrap(model.createManualCollection(
            named: "Sequence",
            frameIDs: [first.id, second.id]
        ))
        undoManager.removeAllActions()
        model.removeFramesFromLibrary([second])
        var changedLater = try XCTUnwrap(model.manualCollections.first)
        changedLater.frameIDs.append(later.id)
        model.replaceManualCollections(with: [changedLater])

        undoManager.undo()

        XCTAssertEqual(model.frames.map(\.id), [first.id, second.id, later.id])
        XCTAssertEqual(model.manualCollections.first?.frameIDs, [first.id, second.id, later.id])

        undoManager.removeAllActions()
        model.removeFramesFromLibrary([second])
        model.replaceManualCollections(with: [])
        undoManager.undo()
        XCTAssertEqual(model.frames.map(\.id), [first.id, second.id, later.id])
        XCTAssertTrue(model.manualCollections.isEmpty)
    }

    func testManualCollectionMutationsAreValidatedOrderedAndUndoable() throws {
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let first = makeFrame(index: 1)
        let second = makeFrame(index: 2)
        model.frames = [first, second]

        XCTAssertNil(model.createManualCollection(named: "  "))
        XCTAssertNil(model.createManualCollection(
            named: "Invalid",
            frameIDs: [first.id, first.id]
        ))
        let id = try XCTUnwrap(model.createManualCollection(
            named: "  Selects  ",
            frameIDs: [first.id]
        ))
        XCTAssertEqual(model.manualCollections.first?.name, "Selects")
        undoManager.removeAllActions()
        XCTAssertTrue(model.addFrameIDs([second.id], toManualCollection: id))
        XCTAssertEqual(model.manualCollections.first?.frameIDs, [first.id, second.id])

        undoManager.undo()
        XCTAssertEqual(model.manualCollections.first?.frameIDs, [first.id])
        undoManager.redo()
        XCTAssertEqual(model.manualCollections.first?.frameIDs, [first.id, second.id])

        undoManager.removeAllActions()
        XCTAssertTrue(model.renameManualCollection(id: id, to: "Finals"))
        XCTAssertEqual(model.manualCollections.first?.name, "Finals")
        undoManager.undo()
        XCTAssertEqual(model.manualCollections.first?.name, "Selects")

        undoManager.removeAllActions()
        XCTAssertTrue(model.deleteManualCollection(id: id))
        XCTAssertTrue(model.manualCollections.isEmpty)
        undoManager.undo()
        XCTAssertEqual(model.manualCollections.first?.id, id)
        XCTAssertEqual(model.manualCollections.first?.frameIDs, [first.id, second.id])
    }

    func testSmartCollectionsAndSavedSearchesRejectInvalidDefinitionsAndUndoCRUD() throws {
        let model = AppModel()
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let valid = LibrarySearchDefinition(
            query: LibraryQuery(conditions: [
                .pickState(isAnyOf: [.picked]),
            ]),
            sort: LibrarySortDescriptor(key: .rating, ascending: false)
        )
        let invalid = LibrarySearchDefinition(
            query: LibraryQuery(version: LibraryQuery.currentVersion + 1),
            sort: LibrarySortDescriptor(key: .inputOrder, ascending: true)
        )

        XCTAssertNil(model.createSmartCollection(named: "Future", definition: invalid))
        XCTAssertNil(model.createSavedSearch(named: "Future", definition: invalid))
        let smartID = try XCTUnwrap(model.createSmartCollection(
            named: "Picked",
            definition: valid
        ))
        let savedID = try XCTUnwrap(model.createSavedSearch(
            named: "Picked Search",
            definition: valid
        ))
        XCTAssertEqual(
            model.smartCollections.first?.definition.decodedDefinition(),
            valid
        )
        XCTAssertEqual(
            model.savedSearches.first?.definition.decodedDefinition(),
            valid
        )

        undoManager.removeAllActions()
        XCTAssertTrue(model.renameSmartCollection(id: smartID, to: "Flagged"))
        XCTAssertTrue(model.renameSavedSearch(id: savedID, to: "Flagged Search"))
        undoManager.removeAllActions()
        XCTAssertTrue(model.deleteSavedSearch(id: savedID))
        XCTAssertTrue(model.savedSearches.isEmpty)
        undoManager.undo()
        XCTAssertEqual(model.savedSearches.first?.id, savedID)
        XCTAssertEqual(model.savedSearches.first?.name, "Flagged Search")

        undoManager.removeAllActions()
        XCTAssertTrue(model.deleteSmartCollection(id: smartID))
        XCTAssertTrue(model.smartCollections.isEmpty)
        undoManager.undo()
        XCTAssertEqual(model.smartCollections.first?.id, smartID)
        XCTAssertEqual(model.smartCollections.first?.name, "Flagged")
    }

    func testOrganizerProjectionUsesManualIDsAndStoredQueryReplacement() throws {
        let firstID = UUID()
        let secondID = UUID()
        let manualID = UUID()
        let manual = LibraryManualCollection(
            id: manualID,
            name: "Same Name",
            frameIDs: [firstID]
        )
        let sameName = LibraryManualCollection(
            id: UUID(),
            name: "Same Name",
            frameIDs: [secondID]
        )
        let currentQuery = LibraryQuery(conditions: [
            .rating(comparison: .greaterThanOrEqual, value: 3),
        ])
        let currentSort = LibrarySortDescriptor(key: .name, ascending: true)
        let storedQuery = LibraryQuery(matchMode: .any, conditions: [
            .pickState(isAnyOf: [.picked]),
            .pickState(isAnyOf: [.rejected]),
        ])
        let storedSort = LibrarySortDescriptor(key: .rating, ascending: false)
        let envelope = try LibraryStoredSearchEnvelope(definition: LibrarySearchDefinition(
            query: storedQuery,
            sort: storedSort
        ))
        let smartID = UUID()
        let smart = LibrarySmartCollection(id: smartID, name: "Flags", definition: envelope)

        let manualRequest = try XCTUnwrap(LibraryOrganizerProjectionRequest.resolve(
            selection: .manual(manualID),
            manualCollections: [manual, sameName],
            smartCollections: [],
            savedSearches: [],
            currentQuery: currentQuery,
            currentSort: currentSort
        ))
        XCTAssertEqual(manualRequest.sourceFrameIDs, [firstID])
        XCTAssertEqual(manualRequest.query, currentQuery)
        XCTAssertEqual(manualRequest.sort, currentSort)

        let smartRequest = try XCTUnwrap(LibraryOrganizerProjectionRequest.resolve(
            selection: .smart(smartID),
            manualCollections: [manual, sameName],
            smartCollections: [smart],
            savedSearches: [],
            currentQuery: currentQuery,
            currentSort: currentSort
        ))
        XCTAssertNil(smartRequest.sourceFrameIDs)
        XCTAssertEqual(smartRequest.query, storedQuery)
        XCTAssertEqual(smartRequest.sort, storedSort)
        XCTAssertNil(LibraryOrganizerProjectionRequest.resolve(
            selection: .smart(UUID()),
            manualCollections: [],
            smartCollections: [smart],
            savedSearches: [],
            currentQuery: currentQuery,
            currentSort: currentSort
        ))
    }

    private func searchEnvelope(query: LibraryQuery) throws -> LibraryStoredSearchEnvelope {
        try LibraryStoredSearchEnvelope(definition: LibrarySearchDefinition(
            query: query,
            sort: LibrarySortDescriptor(key: .inputOrder, ascending: true)
        ))
    }

    private func makeFrame(
        index: Int,
        root: URL = FileManager.default.temporaryDirectory
    ) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: root.appendingPathComponent("collection-\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
    }
}
