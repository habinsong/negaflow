import XCTest
import Chromabase
@testable import negaflowApp

final class SourceTrashTransactionTests: XCTestCase {
    func testMoveFailureRestoresEarlierFilesAndSkipsCatalogCommit() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a.tiff")
        let second = root.appendingPathComponent("b.tiff")
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        var committed = false

        let outcome = SourceTrashTransaction.perform(
            urls: [first, second],
            operations: testOperations(trashDirectory: trash, failingPath: second.path)
        ) {
            committed = true
            return true
        }

        XCTAssertEqual(
            outcome,
            .moveFailed(path: second.path, rollbackFailures: [])
        )
        XCTAssertFalse(committed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    func testCatalogCommitFailureRestoresEveryMovedFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a.tiff")
        let second = root.appendingPathComponent("b.tiff")
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let outcome = SourceTrashTransaction.perform(
            urls: [first, second],
            operations: testOperations(trashDirectory: trash)
        ) { false }

        XCTAssertEqual(outcome, .catalogCommitFailed(rollbackFailures: []))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    func testRollbackFailureIsReportedWithoutClaimingCommit() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.tiff")
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: source)
        let operations = SourceTrashFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveToTrash: { original in
                let destination = trash.appendingPathComponent(original.lastPathComponent)
                try FileManager.default.moveItem(at: original, to: destination)
                return destination
            },
            restoreFromTrash: { _, _ in
                throw CocoaError(.fileWriteNoPermission)
            }
        )

        let outcome = SourceTrashTransaction.perform(
            urls: [source],
            operations: operations
        ) { false }

        XCTAssertEqual(
            outcome,
            .catalogCommitFailed(rollbackFailures: [source.path])
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: trash.appendingPathComponent(source.lastPathComponent).path
        ))
    }

    func testMoveErrorAfterSourceDisappearsIsReportedAsRollbackFailure() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.tiff")
        let trashed = root.appendingPathComponent("trashed.tiff")
        try Data("source".utf8).write(to: source)
        let operations = SourceTrashFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveToTrash: { original in
                try FileManager.default.moveItem(at: original, to: trashed)
                throw CocoaError(.fileWriteUnknown)
            },
            restoreFromTrash: { _, _ in
                XCTFail("no completed move record should exist")
            }
        )

        let outcome = SourceTrashTransaction.perform(
            urls: [source],
            operations: operations
        ) { true }

        XCTAssertEqual(
            outcome,
            .moveFailed(path: source.path, rollbackFailures: [source.path])
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path))
    }

    @MainActor
    func testAppModelCommitsCatalogBeforePublishingSuccessfulSourceTrash() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.tiff")
        let infrared = root.appendingPathComponent("source-ir.tiff")
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        let catalogURL = root.appendingPathComponent("catalog/library.json")
        let defectDirectory = root.appendingPathComponent("defects", isDirectory: true)
        let cleanedDirectory = root.appendingPathComponent("cleaned", isDirectory: true)
        let currentCleanedDirectory = root.appendingPathComponent("cleaned-current", isDirectory: true)
        let defaultsSuite = "negaflow-source-trash-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let diskStorage = DiskStorageStore(defaults: defaults)
        diskStorage.cleanedRawPath = cleanedDirectory.path
        diskStorage.cleanedRawPath = currentCleanedDirectory.path
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: source)
        try Data("infrared".utf8).write(to: infrared)
        let model = AppModel(
            diskStorageStore: diskStorage,
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defectDirectory,
            libraryBackupDirectoryURL: root.appendingPathComponent("backups")
        )
        await model.restoreLibraryOnLaunch()
        let original = ScanFrame(
            scanIndex: 1,
            rawScanURL: source,
            filmType: .colorNegative,
            infraredScanURL: infrared,
            sourceKind: .importedFile
        )
        let copy = original.makeVirtualCopy(copyNumber: 1)
        let originalCache = CleanedRawCacheFile.makeBuildURL(
            frameID: original.id,
            in: cleanedDirectory
        )
        let copyCache = CleanedRawCacheFile.makeBuildURL(
            frameID: copy.id,
            in: cleanedDirectory
        )
        let unrelatedCache = CleanedRawCacheFile.makeBuildURL(
            frameID: UUID(),
            in: cleanedDirectory
        )
        try Data("cache".utf8).write(to: originalCache)
        try Data("cache".utf8).write(to: copyCache)
        try Data("keep".utf8).write(to: unrelatedCache)
        try DefectSidecarFile.write([], for: original.id, in: defectDirectory)
        try DefectSidecarFile.write([], for: copy.id, in: defectDirectory)
        model.frames = [original, copy]
        XCTAssertTrue(model.rollStore.assignNewPersistentFrameIDs(
            [original.id, copy.id],
            toPhysicalRollID: nil,
            unassignedCreatedAt: Date(timeIntervalSince1970: 1)
        ))
        let collectionID = try XCTUnwrap(model.createManualCollection(
            named: "Deletion",
            frameIDs: [original.id, copy.id]
        ))
        let plan = try XCTUnwrap(model.sourceDeletionPlan(for: [original]))

        await model.performSourceDeletion(
            plan,
            fileOperations: testOperations(trashDirectory: trash)
        )

        XCTAssertTrue(model.frames.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: infrared.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalCache.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copyCache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedCache.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: DefectSidecarFile.url(for: original.id, in: defectDirectory).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: DefectSidecarFile.url(for: copy.id, in: defectDirectory).path
        ))
        XCTAssertEqual(
            Set(try FileManager.default.contentsOfDirectory(atPath: trash.path)),
            Set([source.lastPathComponent, infrared.lastPathComponent])
        )
        XCTAssertFalse(model.hasUnsavedLibraryChanges)
        guard case let .loaded(catalog, version) = LibraryCatalogFile.read(from: catalogURL) else {
            return XCTFail("committed catalog was not readable")
        }
        XCTAssertEqual(version, LibraryCatalog.currentVersion)
        XCTAssertTrue(catalog.frames.isEmpty)
        XCTAssertTrue(catalog.rolls.isEmpty)
        XCTAssertEqual(
            catalog.manualCollections.first(where: { $0.id == collectionID })?.frameIDs,
            []
        )
    }

    @MainActor
    func testAppModelRestoresFilesAndKeepsFramesWhenCatalogCommitFails() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.tiff")
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        let catalogURL = root.appendingPathComponent("catalog/library.json")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: source)
        let model = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups")
        )
        await model.restoreLibraryOnLaunch()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: source,
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        model.frames = [frame]
        XCTAssertTrue(model.rollStore.assignNewPersistentFrameIDs(
            [frame.id],
            toPhysicalRollID: nil,
            unassignedCreatedAt: Date(timeIntervalSince1970: 1)
        ))
        let plan = try XCTUnwrap(model.sourceDeletionPlan(for: [frame]))
        try FileManager.default.createDirectory(
            at: catalogURL,
            withIntermediateDirectories: true
        )

        await model.performSourceDeletion(
            plan,
            fileOperations: testOperations(trashDirectory: trash)
        )

        XCTAssertEqual(model.frames.map(\.id), [frame.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
        XCTAssertEqual(
            model.statusMessage,
            model.text(AppLocalizedPhrase.sourceDeletionCatalogFailedStatus)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-source-trash-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func testOperations(
        trashDirectory: URL,
        failingPath: String? = nil
    ) -> SourceTrashFileOperations {
        SourceTrashFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveToTrash: { original in
                if original.path == failingPath {
                    throw CocoaError(.fileWriteNoPermission)
                }
                let destination = trashDirectory.appendingPathComponent(
                    original.lastPathComponent
                )
                try FileManager.default.moveItem(at: original, to: destination)
                return destination
            },
            restoreFromTrash: { trashed, original in
                try FileManager.default.moveItem(at: trashed, to: original)
            }
        )
    }
}
