import XCTest
@testable import negaflowApp

@MainActor
final class LibraryManualBackupTests: XCTestCase {
    func testTerminatePersistsInMemoryDefectBeforeCatalogHealthCheck() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let model = AppModel(
            libraryCatalogURL: paths.catalog,
            libraryDefectDirectoryURL: paths.defects,
            libraryBackupDirectoryURL: paths.backups
        )
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Terminate roll",
            filmType: .colorNegative,
            activate: true
        ))
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/terminate.tiff"),
            filmType: .colorNegative
        )
        let edit = DefectEditItem(
            edit: .brush([]),
            label: .guided(count: 1),
            summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
            preview: [],
            baseSize: nil
        )
        frame.defectEdits = [edit]
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame], toRollID: roll.id))
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        model.libraryPersistenceEnabled = true

        model.saveLibraryOnTerminate()

        let catalog = try XCTUnwrap(LibraryCatalogFile.loadPrimary(from: paths.catalog))
        XCTAssertEqual(catalog.frames.map(\.id), [frame.id])
        // 기록은 디스크에 남지 않는다 — sidecar 없이도 catalog health가 통과해야 한다.
        XCTAssertNil(DefectSidecarFile.load(for: frame.id, in: paths.defects))
        XCTAssertTrue(
            LibraryCatalogHealthInspector.inspect(
                catalog,
                defectDirectory: paths.defects
            ).canOpenSafely
        )
        XCTAssertNotNil(LibraryBackupStore.latestValidSnapshot(in: paths.backups))
    }

    func testManualBackupCapturesCurrentMemoryAsOneValidatedGeneration() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let model = AppModel(
            libraryCatalogURL: paths.catalog,
            libraryDefectDirectoryURL: paths.defects,
            libraryBackupDirectoryURL: paths.backups
        )
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Backup roll",
            filmType: .colorNegative,
            activate: true,
            createdAt: Date(timeIntervalSince1970: 10)
        ))
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/current-memory.tiff"),
            filmType: .colorNegative
        )
        let edit = DefectEditItem(
            edit: .brush([]),
            label: .guided(count: 1),
            summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
            preview: [],
            baseSize: nil
        )
        frame.defectEdits = [edit]
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame], toRollID: roll.id))
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        model.libraryPersistenceEnabled = true

        let succeeded = await model.createLibraryBackupNow()

        XCTAssertTrue(succeeded)
        XCTAssertFalse(model.isLibraryMaintenanceInProgress)
        let snapshot = try XCTUnwrap(
            LibraryBackupStore.latestValidSnapshot(in: paths.backups)
        )
        XCTAssertEqual(snapshot.catalog.frames.map(\.id), [frame.id])
        XCTAssertEqual(snapshot.catalog.rolls, model.rolls)
        XCTAssertEqual(snapshot.catalog.activeRollID, roll.id)
        XCTAssertNil(snapshot.catalog.frames.first?.hasDefectEdits)
        XCTAssertNil(DefectSidecarFile.load(
            for: frame.id,
            in: snapshot.directoryURL.appendingPathComponent("defects", isDirectory: true)
        ))
    }

    func testManualBackupFailsWithoutPublishingGenerationWhenDestinationIsAFile() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try FileManager.default.createDirectory(
            at: paths.backups.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not a directory".utf8).write(to: paths.backups)
        let model = AppModel(
            libraryCatalogURL: paths.catalog,
            libraryDefectDirectoryURL: paths.defects,
            libraryBackupDirectoryURL: paths.backups
        )
        model.libraryPersistenceEnabled = true

        let succeeded = await model.createLibraryBackupNow()

        XCTAssertFalse(succeeded)
        XCTAssertFalse(model.isLibraryMaintenanceInProgress)
        XCTAssertEqual(
            model.statusMessage,
            model.text(AppLocalizedPhrase.diskLibraryBackupFailedStatus)
        )
    }

    func testManualBackupFailsClosedForDuplicateFrameIdentifiers() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let duplicateID = UUID()
        let first = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/first.tiff"),
            filmType: .colorNegative,
            id: duplicateID
        )
        let second = ScanFrame(
            scanIndex: 2,
            rawScanURL: URL(fileURLWithPath: "/offline/second.tiff"),
            filmType: .colorNegative,
            id: duplicateID
        )
        let model = AppModel(
            libraryCatalogURL: paths.catalog,
            libraryDefectDirectoryURL: paths.defects,
            libraryBackupDirectoryURL: paths.backups
        )
        model.frames = [first, second]
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        model.libraryPersistenceEnabled = true

        let succeeded = await model.createLibraryBackupNow()

        XCTAssertFalse(succeeded)
        XCTAssertNil(LibraryBackupStore.latestValidSnapshot(in: paths.backups))
        XCTAssertFalse(model.isLibraryMaintenanceInProgress)
    }

    func testManualBackupFailsClosedForSplitVirtualCopyFamily() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let original = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/original.tiff"),
            filmType: .colorNegative
        )
        let copy = original.makeVirtualCopy(copyNumber: 1)
        let firstRoll = try XCTUnwrap(LibraryRoll.physical(
            name: "First",
            filmType: .colorNegative,
            frameIDs: [original.id]
        ))
        let secondRoll = try XCTUnwrap(LibraryRoll.physical(
            name: "Second",
            filmType: .colorNegative,
            frameIDs: [copy.id]
        ))
        let model = AppModel(
            libraryCatalogURL: paths.catalog,
            libraryDefectDirectoryURL: paths.defects,
            libraryBackupDirectoryURL: paths.backups
        )
        model.frames = [original, copy]
        model.replaceRollState(with: RollStoreSnapshot(
            rolls: [firstRoll, secondRoll],
            activeRollID: nil
        ))
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        model.libraryPersistenceEnabled = true
        defer {
            model.libraryPersistenceEnabled = false
            model.librarySaveTask?.cancel()
            model.librarySaveTask = nil
        }

        let succeeded = await model.createLibraryBackupNow()

        XCTAssertFalse(succeeded)
        XCTAssertNil(LibraryBackupStore.latestValidSnapshot(in: paths.backups))
        XCTAssertFalse(model.isLibraryMaintenanceInProgress)
    }

    private func makePaths() throws -> (
        root: URL,
        catalog: URL,
        defects: URL,
        backups: URL
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-manual-backup-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        let support = root.appendingPathComponent("support", isDirectory: true)
        return (
            root,
            support.appendingPathComponent("library.json"),
            support.appendingPathComponent("defects", isDirectory: true),
            support.appendingPathComponent("Backups", isDirectory: true)
        )
    }
}
