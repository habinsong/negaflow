import XCTest
import ImageIO
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class AppMetadataOverlayRuntimeTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-overlay-runtime-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try await super.tearDown()
    }

    func testBatchEditPersistsPerFrameFingerprintWithoutTouchingSourceOrThirdPartyXMP() async throws {
        let model = makeModel()
        await model.restoreLibraryOnLaunch()
        let first = try makeFrame(index: 1)
        let second = try makeFrame(index: 2)
        model.frames = [first, second]
        let sourceBytes = try Data(contentsOf: first.rawScanURL)
        let xmpURL = first.rawScanURL.deletingPathExtension().appendingPathExtension("xmp")
        let xmpBytes = Data("third-party-xmp".utf8)
        try xmpBytes.write(to: xmpURL)

        XCTAssertTrue(model.applyAppMetadataOverlay(
            AppMetadataOverlayDraftValues(
                title: "Batch title",
                caption: "Batch caption",
                keywords: "film, archive, film",
                copyright: "Copyright 2026"
            ).draft,
            to: [first, second]
        ))

        XCTAssertEqual(first.appMetadataOverlay?.title, "Batch title")
        XCTAssertEqual(second.appMetadataOverlay?.title, "Batch title")
        XCTAssertEqual(first.appMetadataOverlay?.keywords, ["film", "archive"])
        XCTAssertEqual(first.appMetadataOverlay?.revision, 1)
        XCTAssertEqual(second.appMetadataOverlay?.revision, 1)
        XCTAssertEqual(try Data(contentsOf: first.rawScanURL), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: xmpURL), xmpBytes)
    }

    func testOverlayAppearsInActualExportAndConflictsFailBeforePublication() throws {
        let frame = try makeFrame(index: 1)
        let overlay = AppMetadataOverlay(
            title: "Overlay title",
            caption: "Overlay caption",
            keywords: ["overlay", "film"],
            copyright: "Copyright 2026",
            sourceMetadataSHA256: frame.sourceMetadata?.appMetadataIdentitySHA256(),
            revision: 1
        )
        frame.setAppMetadataOverlay(overlay)
        let output = directory.appendingPathComponent("overlay.tif")
        let snapshot = try buildSnapshot(frame: frame, output: output)
        _ = try ExportFrameWriter.write(snapshot)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [String: Any]
        XCTAssertEqual(iptc?[kCGImagePropertyIPTCObjectName as String] as? String, "Overlay title")
        XCTAssertEqual(iptc?[kCGImagePropertyIPTCCaptionAbstract as String] as? String, "Overlay caption")
        XCTAssertEqual(iptc?[kCGImagePropertyIPTCCopyrightNotice as String] as? String, "Copyright 2026")
        let xmp = try String(
            contentsOf: output.deletingPathExtension().appendingPathExtension("xmp"),
            encoding: .utf8
        )
        XCTAssertTrue(xmp.contains("dc:title=\"Overlay title\""))
        XCTAssertTrue(xmp.contains("dc:description=\"Overlay caption\""))

        var changedMetadata = try XCTUnwrap(frame.sourceMetadata)
        changedMetadata.discardedInvalidValues.toggle()
        frame.updateSourceLocation(
            rawURL: frame.rawScanURL,
            infraredURL: frame.infraredScanURL,
            sourceMetadata: changedMetadata
        )
        let conflictedOutput = directory.appendingPathComponent("conflict.tif")
        let conflicted = try buildSnapshot(frame: frame, output: conflictedOutput)
        XCTAssertThrowsError(try ExportFrameWriter.write(conflicted))
        XCTAssertFalse(FileManager.default.fileExists(atPath: conflictedOutput.path))
    }

    private func makeFrame(index: Int) throws -> ScanFrame {
        let source = directory.appendingPathComponent("source-\(index).tif")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: source)
        return ScanFrame(
            scanIndex: index,
            rawScanURL: source,
            filmType: .colorPositive,
            sourceMetadata: SourceMetadataReader.read(from: source)
        )
    }

    private func buildSnapshot(frame: ScanFrame, output: URL) throws -> ExportFrameSnapshot {
        ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: output,
            format: .tiff16,
            writeSidecar: true,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: ExportOptions(metadataPolicy: .all),
            scannerModel: nil,
            backendUsed: nil,
            metadataDate: Date(timeIntervalSince1970: 1_800_000_000)
        ).snapshot
    }

    private func makeModel() -> AppModel {
        AppModel(
            libraryCatalogURL: directory.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: directory.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: directory.appendingPathComponent("backups")
        )
    }
}

private struct AppMetadataOverlayDraftValues {
    let title: String
    let caption: String
    let keywords: String
    let copyright: String

    var draft: AppMetadataOverlayDraft {
        var value = AppMetadataOverlayDraft()
        value.title = title
        value.caption = caption
        value.keywords = keywords
        value.copyright = copyright
        return value
    }
}
