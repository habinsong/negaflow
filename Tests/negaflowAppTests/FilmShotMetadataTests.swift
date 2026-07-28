import XCTest
import ImageIO
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class FilmShotMetadataTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-film-shot-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try await super.tearDown()
    }

    func testShutterSpeedTextRoundTripsAndRejectsUnreadableValues() {
        XCTAssertEqual(FilmShotMetadata.exposureTime(fromText: "1/125"), 1.0 / 125)
        XCTAssertEqual(FilmShotMetadata.exposureTime(fromText: " 1/125s "), 1.0 / 125)
        XCTAssertEqual(FilmShotMetadata.exposureTime(fromText: "2"), 2)
        XCTAssertEqual(FilmShotMetadata.exposureTime(fromText: "2s"), 2)
        XCTAssertEqual(FilmShotMetadata.exposureTimeText(1.0 / 125), "1/125")
        XCTAssertEqual(FilmShotMetadata.exposureTimeText(2), "2")

        XCTAssertNil(FilmShotMetadata.exposureTime(fromText: ""))
        XCTAssertNil(FilmShotMetadata.exposureTime(fromText: "fast"))
        XCTAssertNil(FilmShotMetadata.exposureTime(fromText: "1/0"))
        XCTAssertNil(FilmShotMetadata.exposureTime(fromText: "-1/125"))
        XCTAssertNil(FilmShotMetadata.exposureTime(fromText: "0"))
        // 상한을 넘는 값은 오타로 보고 버린다.
        XCTAssertNil(FilmShotMetadata.exposureTime(fromText: "100000"))
    }

    func testDraftKeepsWritableValuesAndDropsUnreadableNumbers() {
        var draft = AppMetadataOverlayDraft()
        draft.cameraMake = "  Nikon  "
        draft.cameraModel = "FM2"
        draft.lensModel = "Nikkor 50mm f/1.4"
        draft.filmStock = "Kodak Portra 400"
        draft.isoSpeed = "400"
        draft.shutterSpeed = "1/250"
        draft.aperture = "f/2.8"
        draft.focalLength = "50mm"

        let shot = draft.filmShotValues
        XCTAssertEqual(shot.cameraMake, "Nikon")
        XCTAssertEqual(shot.cameraModel, "FM2")
        XCTAssertEqual(shot.lensModel, "Nikkor 50mm f/1.4")
        XCTAssertEqual(shot.filmStock, "Kodak Portra 400")
        XCTAssertEqual(shot.isoSpeed, 400)
        XCTAssertEqual(shot.exposureTimeSeconds, 1.0 / 250)
        XCTAssertEqual(shot.fNumber, 2.8)
        XCTAssertEqual(shot.focalLengthMM, 50)
        XCTAssertTrue(shot.isValid)

        draft.isoSpeed = "high"
        draft.aperture = "wide"
        XCTAssertNil(draft.filmShotValues.isoSpeed)
        XCTAssertNil(draft.filmShotValues.fNumber)

        XCTAssertTrue(AppMetadataOverlayDraft().filmShotValues.isEmpty)
    }

    func testEmptyShotDoesNotCreateAnOverlay() async throws {
        let model = makeModel()
        await model.restoreLibraryOnLaunch()
        let frame = try makeFrame(index: 1)
        model.frames = [frame]

        XCTAssertTrue(model.applyAppMetadataOverlay(AppMetadataOverlayDraft(), to: [frame]))
        XCTAssertNil(frame.appMetadataOverlay)
    }

    func testCatalogRoundTripPreservesShotAndOlderRecordsStillDecode() throws {
        let source = directory.appendingPathComponent("catalog.tif")
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 8, to: source)
        let metadata = SourceMetadataReader.read(from: source)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: source,
            filmType: .colorNegative,
            sourceMetadata: metadata,
            appMetadataOverlay: AppMetadataOverlay(
                title: "Roll 12",
                filmShot: FilmShotMetadata(
                    cameraMake: "Nikon",
                    cameraModel: "FM2",
                    filmStock: "Kodak Portra 400",
                    isoSpeed: 400,
                    exposureTimeSeconds: 1.0 / 250,
                    fNumber: 2.8,
                    focalLengthMM: 50
                ),
                sourceMetadataSHA256: metadata.appMetadataIdentitySHA256(),
                revision: 1
            )
        )

        let encoded = try JSONEncoder().encode(LibraryFrameRecord(frame: frame))
        let decoded = try JSONDecoder().decode(LibraryFrameRecord.self, from: encoded)
        XCTAssertEqual(decoded.makeFrame(presets: []).appMetadataOverlay, frame.appMetadataOverlay)

        // 촬영 기록이 없던 카탈로그도 그대로 열려야 한다.
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var overlay = try XCTUnwrap(object["appMetadataOverlay"] as? [String: Any])
        overlay.removeValue(forKey: "filmShot")
        object["appMetadataOverlay"] = overlay
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let legacyRecord = try JSONDecoder().decode(LibraryFrameRecord.self, from: legacy)
        XCTAssertNil(legacyRecord.appMetadataOverlay?.filmShot)
        XCTAssertEqual(legacyRecord.appMetadataOverlay?.title, "Roll 12")
        XCTAssertTrue(try XCTUnwrap(legacyRecord.appMetadataOverlay).isValid)
    }

    func testExportWritesShotToEXIFAndPrefersTheShootingCameraOverTheScanner() throws {
        let frame = try makeFrame(index: 1)
        frame.setAppMetadataOverlay(AppMetadataOverlay(
            filmShot: FilmShotMetadata(
                cameraMake: "Nikon",
                cameraModel: "FM2",
                lensModel: "Nikkor 50mm f/1.4",
                filmStock: "Kodak Portra 400",
                isoSpeed: 400,
                exposureTimeSeconds: 1.0 / 250,
                fNumber: 2.8,
                focalLengthMM: 50
            ),
            sourceMetadataSHA256: frame.sourceMetadata?.appMetadataIdentitySHA256(),
            revision: 1
        ))
        let output = directory.appendingPathComponent("shot.tif")
        _ = try ExportFrameWriter.write(try buildSnapshot(frame: frame, output: output))

        let properties = try imageProperties(of: output)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [String: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [String: Any]
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFMake as String] as? String, "Nikon")
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFModel as String] as? String, "FM2")
        XCTAssertEqual(
            exif?[kCGImagePropertyExifLensModel as String] as? String,
            "Nikkor 50mm f/1.4"
        )
        XCTAssertEqual(
            (exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.intValue,
            400
        )
        XCTAssertEqual(
            (exif?[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue ?? 0,
            1.0 / 250,
            accuracy: 1e-6
        )
        XCTAssertEqual(
            (exif?[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue ?? 0,
            2.8,
            accuracy: 1e-6
        )
        XCTAssertEqual(
            (exif?[kCGImagePropertyExifFocalLength as String] as? NSNumber)?.doubleValue ?? 0,
            50,
            accuracy: 1e-6
        )
        let comment = try XCTUnwrap(exif?["UserComment"] as? String)
        XCTAssertTrue(comment.contains("FilmStock: Kodak Portra 400"), comment)
        XCTAssertTrue(comment.contains("FilmType:"), comment)

        let xmp = try String(
            contentsOf: output.deletingPathExtension().appendingPathExtension("xmp"),
            encoding: .utf8
        )
        XCTAssertTrue(xmp.contains("tiff:Make=\"Nikon\""), xmp)
        XCTAssertTrue(xmp.contains("aux:Lens=\"Nikkor 50mm f/1.4\""), xmp)
    }

    func testScannerIdentityStaysWhenNoShootingCameraIsRecorded() throws {
        let frame = try makeFrame(index: 2)
        let output = directory.appendingPathComponent("scanner.tif")
        _ = try ExportFrameWriter.write(try buildSnapshot(frame: frame, output: output))

        let tiff = try imageProperties(of: output)[kCGImagePropertyTIFFDictionary] as? [String: Any]
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFMake as String] as? String, "Test Scanners")
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFModel as String] as? String, "Bench 1000")
    }

    func testMinimalMetadataPolicyKeepsTheRecordedFilmOutOfTheFile() throws {
        let frame = try makeFrame(index: 3)
        frame.setAppMetadataOverlay(AppMetadataOverlay(
            filmShot: FilmShotMetadata(cameraMake: "Nikon", filmStock: "Kodak Portra 400"),
            sourceMetadataSHA256: frame.sourceMetadata?.appMetadataIdentitySHA256(),
            revision: 1
        ))
        let output = directory.appendingPathComponent("minimal.tif")
        _ = try ExportFrameWriter.write(
            try buildSnapshot(frame: frame, output: output, metadataPolicy: .minimal)
        )

        let properties = try imageProperties(of: output)
        let exif = properties[kCGImagePropertyExifDictionary] as? [String: Any]
        let comment = exif?["UserComment"] as? String ?? ""
        XCTAssertFalse(comment.contains("Kodak Portra 400"), comment)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [String: Any]
        XCTAssertNil(tiff?[kCGImagePropertyTIFFMake as String] as? String)
    }

    private func imageProperties(of url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
    }

    private func makeFrame(index: Int) throws -> ScanFrame {
        let source = directory.appendingPathComponent("source-\(index).tif")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: source)
        return ScanFrame(
            scanIndex: index,
            rawScanURL: source,
            filmType: .colorNegative,
            sourceMetadata: SourceMetadataReader.read(from: source)
        )
    }

    private func buildSnapshot(
        frame: ScanFrame,
        output: URL,
        metadataPolicy: ExportMetadataPolicy = .all
    ) throws -> ExportFrameSnapshot {
        ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: output,
            format: .tiff16,
            writeSidecar: true,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: ExportOptions(metadataPolicy: metadataPolicy),
            scannerModel: "Bench 1000",
            backendUsed: nil,
            scannerMake: "Test Scanners",
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
