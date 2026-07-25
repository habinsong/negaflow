import XCTest
import CoreGraphics
import Chromabase
@testable import negaflowApp

final class SourceMoveTests: XCTestCase {
    @MainActor
    func testPhotoNumberCanChangeOnlyWhenUnusedInSameFolder() throws {
        let folder = URL(fileURLWithPath: "/tmp/negaflow-numbering", isDirectory: true)
        let first = ScanFrame(
            scanIndex: 1,
            rawScanURL: folder.appendingPathComponent("first.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        let second = ScanFrame(
            scanIndex: 2,
            rawScanURL: folder.appendingPathComponent("second.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        let model = AppModel()
        model.frames = [first, second]

        XCTAssertFalse(model.renamePhotoNumber(2, for: first))
        XCTAssertNil(first.assignedPhotoNumber)
        XCTAssertTrue(model.renamePhotoNumber(5, for: first))
        XCTAssertEqual(first.assignedPhotoNumber, 5)
        XCTAssertEqual(first.displayName(language: .korean), "사진 5")
    }

    @MainActor
    func testMovedPhotoNumberStartsAfterDestinationMaximum() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFolder = root.appendingPathComponent("A", isDirectory: true)
        let destinationFolder = root.appendingPathComponent("C", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let movingURL = sourceFolder.appendingPathComponent("moving.tiff")
        try Data().write(to: movingURL)
        let movingFrame = ScanFrame(
            scanIndex: 2,
            rawScanURL: movingURL,
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        let destinationFrames = (1...4).map { number in
            ScanFrame(
                scanIndex: number,
                rawScanURL: destinationFolder.appendingPathComponent("existing-\(number).tiff"),
                filmType: .colorNegative,
                sourceKind: .importedFile
            )
        }
        let model = AppModel()
        model.frames = destinationFrames + [movingFrame]
        let plan = try SourceMovePlanner.files([
            .init(rawURL: movingURL, infraredURL: nil)
        ], to: destinationFolder).get()

        XCTAssertEqual(
            model.movedPhotoNumberAssignments(for: plan)[movingURL.standardizedFileURL.path],
            5
        )
    }

    func testFilePlanMovesRGBAndIRWithoutOverwritingDestination() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let raw = source.appendingPathComponent("frame.tiff")
        let infrared = source.appendingPathComponent("frame-ir.tiff")
        try Data("raw".utf8).write(to: raw)
        try Data("ir".utf8).write(to: infrared)

        let result = SourceMovePlanner.files([
            .init(rawURL: raw, infraredURL: infrared)
        ], to: destination)
        let plan = try XCTUnwrap(try? result.get())

        XCTAssertEqual(plan.sourceCount, 1)
        XCTAssertEqual(plan.fileMoves.count, 2)
        XCTAssertEqual(plan.relinkPlan.mappings.first?.newSourceURL, destination.appendingPathComponent("frame.tiff"))
        XCTAssertEqual(
            plan.relinkPlan.companionMappings.first?.newSourceURL,
            destination.appendingPathComponent("frame-ir.tiff")
        )

        try Data("existing".utf8).write(to: destination.appendingPathComponent("frame.tiff"))
        XCTAssertEqual(
            SourceMovePlanner.files([.init(rawURL: raw, infraredURL: infrared)], to: destination),
            .failure(.collision)
        )
    }

    func testFolderPlanRejectsDescendantAndMapsNestedSources() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Film", isDirectory: true)
        let nested = source.appendingPathComponent("nested", isDirectory: true)
        let targetParent = root.appendingPathComponent("Target", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetParent, withIntermediateDirectories: true)
        let raw = nested.appendingPathComponent("frame.tiff")
        try Data("raw".utf8).write(to: raw)

        XCTAssertEqual(
            SourceMovePlanner.folder(
                from: source,
                to: nested.appendingPathComponent("Film"),
                sources: [.init(rawURL: raw, infraredURL: nil)]
            ),
            .failure(.invalidDestination)
        )

        let destination = targetParent.appendingPathComponent("Film", isDirectory: true)
        let plan = try XCTUnwrap(try? SourceMovePlanner.folder(
            from: source,
            to: destination,
            sources: [.init(rawURL: raw, infraredURL: nil)]
        ).get())
        XCTAssertEqual(
            plan.relinkPlan.mappings.first?.newSourceURL,
            destination.appendingPathComponent("nested/frame.tiff")
        )
    }

    func testFilePlanCombinesSourcesFromDifferentFoldersIntoOneDestination() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstFolder = root.appendingPathComponent("first", isDirectory: true)
        let secondFolder = root.appendingPathComponent("second", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let first = firstFolder.appendingPathComponent("first.tiff")
        let second = secondFolder.appendingPathComponent("second.tiff")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let plan = try SourceMovePlanner.files([
            .init(rawURL: first, infraredURL: nil),
            .init(rawURL: second, infraredURL: nil),
        ], to: destination).get()
        guard case .moved = SourceMoveTransaction.move(plan.fileMoves) else {
            return XCTFail("expected both files to move")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("first.tiff").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("second.tiff").path
        ))
    }

    func testMoveTransactionRollsBackCompletedMovesAfterFailure() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.tiff")
        let second = root.appendingPathComponent("second.tiff")
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let secondDestination = destination.appendingPathComponent("second.tiff")
        let operations = SourceMoveFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            move: { source, destination in
                if destination == secondDestination {
                    throw CocoaError(.fileWriteNoPermission)
                }
                try FileManager.default.moveItem(at: source, to: destination)
            }
        )

        let outcome = SourceMoveTransaction.move([
            .init(sourceURL: first, destinationURL: destination.appendingPathComponent("first.tiff")),
            .init(sourceURL: second, destinationURL: secondDestination),
        ], operations: operations)

        guard case .failed(let rollbackFailures) = outcome else {
            return XCTFail("expected rollback")
        }
        XCTAssertTrue(rollbackFailures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    @MainActor
    func testAppModelMovesFileAndCommitsCurrentSourcePath() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFolder = root.appendingPathComponent("source", isDirectory: true)
        let destinationFolder = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("frame.tiff")
        try makeValidTIFF(at: source)
        let catalogURL = root.appendingPathComponent("catalog/library.json")
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
            sourceKind: .importedFile,
            sourceMetadata: SourceMetadataReader.read(from: source)
        )
        model.frames = [frame]
        XCTAssertTrue(model.rollStore.assignNewPersistentFrameIDs(
            [frame.id],
            toPhysicalRollID: nil,
            unassignedCreatedAt: Date(timeIntervalSince1970: 1)
        ))
        let plan = try SourceMovePlanner.files([
            .init(rawURL: source, infraredURL: nil)
        ], to: destinationFolder).get()

        let moved = await model.performSourceMove(plan)
        XCTAssertTrue(moved)

        let destination = destinationFolder.appendingPathComponent(source.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(frame.rawScanURL, destination)
        XCTAssertEqual(frame.assignedPhotoNumber, 1)
        XCTAssertEqual(frame.displayName(language: .korean), "사진 1")
        guard case .loaded(let catalog, _) = LibraryCatalogFile.read(from: catalogURL) else {
            return XCTFail("moved catalog was not readable")
        }
        XCTAssertEqual(catalog.frames.first?.rawScanPath, destination.path)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-source-move-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeValidTIFF(at url: URL) throws {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        XCTAssertTrue(ImageLoader.saveScannerTIFF(image, to: url))
    }
}
