import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class ImportDuplicateTests: XCTestCase {
    func testExactExistingAndWithinBatchDuplicatesAreSkippedInInputOrder() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-import-dedup-\(UUID().uuidString)", isDirectory: true)
        let existing = folder.appendingPathComponent("existing.tiff")
        let first = folder.appendingPathComponent("first.dng")
        let second = folder.appendingPathComponent("second.jpg")

        let result = AppModel.filterDuplicateImports(
            [existing, first, first, second, existing],
            existingSourceURLs: [existing]
        )

        XCTAssertEqual(result.urls, [first, second])
        XCTAssertEqual(result.duplicateCount, 3)
    }

    func testDifferentPathsWithSameFilenameRemainDistinct() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-import-distinct-\(UUID().uuidString)", isDirectory: true)
        let first = root.appendingPathComponent("a/frame.tiff")
        let second = root.appendingPathComponent("b/frame.tiff")

        let result = AppModel.filterDuplicateImports([first, second], existingSourceURLs: [])

        XCTAssertEqual(result.urls, [first, second])
        XCTAssertEqual(result.duplicateCount, 0)
    }

    func testImportedFrameGetsExplicitUnassignedMembershipBeforeCatalogSave() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-import-roll-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 6, to: sourceURL)
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )

        model.importImages(urls: [sourceURL])

        let frame = try XCTUnwrap(model.frames.first)
        XCTAssertEqual(model.frames.count, 1)
        XCTAssertEqual(model.rolls.count, 1)
        XCTAssertEqual(model.rolls[0].kind, .unassigned)
        XCTAssertEqual(model.rolls[0].frameIDs, [frame.id])
        XCTAssertEqual(model.rollID(containing: frame.id), LibraryRoll.unassignedID)

        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        model.libraryPersistenceEnabled = true
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        let persisted = try XCTUnwrap(
            LibraryCatalogFile.decode(try Data(contentsOf: model.libraryCatalogURL))?.rolls.only
        )
        let inMemory = try XCTUnwrap(model.rolls.only)
        XCTAssertEqual(persisted.id, inMemory.id)
        XCTAssertEqual(persisted.kind, inMemory.kind)
        XCTAssertEqual(persisted.frameIDs, inMemory.frameIDs)
        XCTAssertEqual(persisted.name, inMemory.name)
        XCTAssertEqual(persisted.filmType, inMemory.filmType)
        XCTAssertLessThan(abs(persisted.createdAt.timeIntervalSince(inMemory.createdAt)), 1)
    }

    func testImportDoesNotApplyScannerOrientationTemplateAfterImageIOOrientation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-import-orientation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 6, to: sourceURL)
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        let scannerTemplate = ImageTransform(rotation: .deg90, flipHorizontal: true)
        model.nextScanOrientation = scannerTemplate

        model.importImages(urls: [sourceURL])

        XCTAssertEqual(model.frames.first?.imageTransform, .identity)
        XCTAssertEqual(model.nextScanOrientation, scannerTemplate)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
