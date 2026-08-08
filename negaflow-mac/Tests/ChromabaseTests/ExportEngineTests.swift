import XCTest
import CoreImage
import ImageIO
@testable import Chromabase

final class ExportEngineTests: XCTestCase {
    func testExportKeepsFullPixelDimensionsAndWritesDPIWhenLongEdgeIsUnset() throws {
        let url = temporaryURL(fileExtension: "jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6))
            .cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180))

        try ExportEngine.write(
            image,
            to: url,
            format: .jpeg,
            using: renderContext(),
            metadata: ExportMeta(resolutionDPI: 7200),
            options: ExportOptions(dpi: 0, longEdge: nil)
        )

        let props = try imageProperties(at: url)
        XCTAssertEqual(positiveInt(props[kCGImagePropertyPixelWidth]), 320)
        XCTAssertEqual(positiveInt(props[kCGImagePropertyPixelHeight]), 180)
        XCTAssertEqual(positiveInt(props[kCGImagePropertyDPIWidth]), 7200)
        XCTAssertEqual(positiveInt(props[kCGImagePropertyDPIHeight]), 7200)
    }

    func testExportDownsizesOnlyWhenLongEdgeIsSet() throws {
        let url = temporaryURL(fileExtension: "png")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = CIImage(color: CIColor(red: 0.8, green: 0.3, blue: 0.1))
            .cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180))

        try ExportEngine.write(
            image,
            to: url,
            format: .png,
            using: renderContext(),
            metadata: nil,
            options: ExportOptions(longEdge: 120)
        )

        let props = try imageProperties(at: url)
        XCTAssertEqual(positiveInt(props[kCGImagePropertyPixelWidth]), 120)
        XCTAssertEqual(positiveInt(props[kCGImagePropertyPixelHeight]), 68)
    }

    func testResizePreservesNonZeroImageOrigin() {
        let image = CIImage(color: CIColor(red: 0.8, green: 0.3, blue: 0.1))
            .cropped(to: CGRect(x: 80, y: 40, width: 320, height: 160))

        let resized = ExportEngine.resized(image, longEdge: 160)

        XCTAssertEqual(resized.extent, CGRect(x: 40, y: 20, width: 160, height: 80))
    }

    func testExportKeepsSelectedColorSpaceProfile() throws {
        let url = temporaryURL(fileExtension: "png")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = CIImage(color: CIColor(red: 0.4, green: 0.5, blue: 0.6))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))

        try ExportEngine.write(
            image,
            to: url,
            format: .png,
            using: renderContext(),
            metadata: nil,
            options: ExportOptions(colorSpace: .displayP3)
        )

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        XCTAssertEqual(cg.colorSpace?.model, .rgb)
        XCTAssertEqual(cg.colorSpace?.name, ExportColorSpace.displayP3.cgColorSpace.name)
    }

    func testPrinterOutputProfileIsEmbeddedForEveryProcessedRasterFormat() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let image = CIImage(color: CIColor(red: 0.31, green: 0.52, blue: 0.73))
            .cropped(to: CGRect(x: 0, y: 0, width: 24, height: 16))

        for (format, filename) in [
            (ExportFormat.jpeg, "print.jpg"),
            (.png, "print.png"),
            (.tiff16, "print.tif"),
        ] {
            let url = directory.appendingPathComponent(filename)
            try ExportEngine.write(
                image,
                to: url,
                format: format,
                using: renderContext(),
                outputProfile: profile
            )

            XCTAssertEqual(try embeddedICCProfileSHA256(at: url), profile.profileSHA256)
        }
    }

    func testPrintDevelopFileRequiresOutputProfileBeforeCreatingOutput() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.tif")
        let outputURL = directory.appendingPathComponent("print.tif")
        let image = CIImage(color: CIColor(red: 0.31, green: 0.52, blue: 0.73))
            .cropped(to: CGRect(x: 0, y: 0, width: 24, height: 16))
        try ExportEngine.write(image, to: inputURL, format: .tiff16, using: renderContext())
        var params = DevelopParameters()
        params.filmType = .colorPositive
        params.developTarget = .print

        XCTAssertThrowsError(
            try ChromabaseEngine().developFile(
                input: inputURL,
                output: outputURL,
                format: .tiff16,
                base: nil,
                params: params
            )
        ) { error in
            guard case ChromabaseError.writeFailed(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(
                message,
                "PRINT export requires a valid RGB printer-class ICC profile"
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testPrintDevelopScannerFileEmbedsExactPrinterProfile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.tif")
        let outputURL = directory.appendingPathComponent("print.tif")
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let image = CIImage(color: CIColor(red: 0.61, green: 0.42, blue: 0.23))
            .cropped(to: CGRect(x: 0, y: 0, width: 24, height: 16))
        try ExportEngine.write(image, to: inputURL, format: .tiff16, using: renderContext())
        var params = DevelopParameters()
        params.filmType = .colorPositive
        params.developTarget = .print

        try ChromabaseEngine().developScannerFile(
            input: inputURL,
            output: outputURL,
            format: .tiff16,
            base: nil,
            params: params,
            outputProfile: profile
        )

        XCTAssertEqual(try embeddedICCProfileSHA256(at: outputURL), profile.profileSHA256)
    }

    func testPairedExportAppliesPrinterProfileOnlyToPrimary() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("print.tif")
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let image = CIImage(color: CIColor(red: 0.61, green: 0.42, blue: 0.23))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 12))

        let result = try ExportEngine.writePaired(
            image,
            mainFlatMaster: image,
            to: outputURL,
            format: .tiff16,
            using: renderContext(),
            primaryOutputProfile: profile,
            writeMainFlatMaster: true
        )

        XCTAssertEqual(try embeddedICCProfileSHA256(at: outputURL), profile.profileSHA256)
        let mainFlatURL = try XCTUnwrap(result.mainFlatMasterURL)
        XCTAssertNotEqual(try embeddedICCProfileSHA256(at: mainFlatURL), profile.profileSHA256)
    }

    func testRawExportRejectsPrinterProfileBeforeWriting() throws {
        let url = temporaryURL(fileExtension: "tif")
        defer { try? FileManager.default.removeItem(at: url) }
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let image = CIImage(color: .red).cropped(
            to: CGRect(x: 0, y: 0, width: 8, height: 8)
        )

        XCTAssertThrowsError(try ExportEngine.write(
            image,
            to: url,
            format: .rawScanTIFF,
            using: renderContext(),
            outputProfile: profile
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRawExportRejectsLongEdgeBeforeWriting() {
        let url = temporaryURL(fileExtension: "tif")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = CIImage(color: .red).cropped(
            to: CGRect(x: 0, y: 0, width: 16, height: 12)
        )

        XCTAssertThrowsError(try ExportEngine.write(
            image,
            to: url,
            format: .rawScanTIFF,
            using: renderContext(),
            options: ExportOptions(longEdge: 8)
        )) { error in
            XCTAssertEqual(error as? ExportOptionsError, .unsupportedRawTIFFOptions)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRawExportPreservesLoadedInputProfile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("profiled-input.tif")
        let outputURL = directory.appendingPathComponent("raw-output.tif")
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let image = CIImage(color: CIColor(red: 0.21, green: 0.43, blue: 0.65))
            .cropped(to: CGRect(x: 0, y: 0, width: 24, height: 16))
        try ExportEngine.write(
            image,
            to: inputURL,
            format: .tiff16,
            using: renderContext(),
            outputProfile: profile
        )
        let loaded = try XCTUnwrap(ImageLoader.loadScannerTIFF(inputURL))

        try ExportEngine.write(
            loaded,
            to: outputURL,
            format: .rawScanTIFF,
            using: renderContext()
        )

        XCTAssertEqual(try embeddedICCProfileSHA256(at: inputURL), profile.profileSHA256)
        XCTAssertEqual(try embeddedICCProfileSHA256(at: outputURL), profile.profileSHA256)
    }

    func testDevelopFileRawExportPreservesSourcePixelsAndProfileWithoutApplyingParameters() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("profiled-input.tif")
        let referenceURL = directory.appendingPathComponent("reference-raw.tif")
        let outputURL = directory.appendingPathComponent("develop-file-raw.tif")
        let profile = try writeProfiledPattern(to: inputURL)
        let engine = ChromabaseEngine()
        let loaded = try XCTUnwrap(engine.loadImage(inputURL))
        try ExportEngine.write(
            loaded,
            to: referenceURL,
            format: .rawScanTIFF,
            using: renderContext()
        )
        var params = DevelopParameters()
        params.filmType = .colorPositive
        params.developTarget = .print
        params.exposure = 2
        params.warmth = 1
        params.saturation = -1
        params.imageTransform = ImageTransform(rotation: .deg90)

        try engine.developFile(
            input: inputURL,
            output: outputURL,
            format: .rawScanTIFF,
            base: nil,
            params: params
        )

        XCTAssertEqual(try decodedPixelData(at: outputURL), try decodedPixelData(at: referenceURL))
        XCTAssertEqual(try embeddedICCProfileSHA256(at: outputURL), profile.profileSHA256)
    }

    func testDevelopScannerFileRawExportPreservesSourcePixelsAndProfileWithoutApplyingParameters() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("profiled-input.tif")
        let referenceURL = directory.appendingPathComponent("reference-raw.tif")
        let outputURL = directory.appendingPathComponent("develop-scanner-file-raw.tif")
        let profile = try writeProfiledPattern(to: inputURL)
        let engine = ChromabaseEngine()
        let loaded = try XCTUnwrap(engine.loadScannerImage(inputURL))
        try ExportEngine.write(
            loaded,
            to: referenceURL,
            format: .rawScanTIFF,
            using: renderContext()
        )
        var params = DevelopParameters()
        params.filmType = .colorPositive
        params.developTarget = .noritsu
        params.exposure = -2
        params.tint = 1
        params.saturation = -1
        params.imageTransform = ImageTransform(rotation: .deg180)

        try engine.developScannerFile(
            input: inputURL,
            output: outputURL,
            format: .rawScanTIFF,
            base: nil,
            params: params
        )

        XCTAssertEqual(try decodedPixelData(at: outputURL), try decodedPixelData(at: referenceURL))
        XCTAssertEqual(try embeddedICCProfileSHA256(at: outputURL), profile.profileSHA256)
    }

    func testRawDevelopEntryPointsRejectPrinterProfileBeforeWriting() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("profiled-input.tif")
        let developOutputURL = directory.appendingPathComponent("develop-file-raw.tif")
        let scannerOutputURL = directory.appendingPathComponent("develop-scanner-file-raw.tif")
        let profile = try writeProfiledPattern(to: inputURL)
        let engine = ChromabaseEngine()
        var params = DevelopParameters()
        params.filmType = .colorPositive

        let attempts: [(URL, () throws -> Void)] = [
            (developOutputURL, {
                try engine.developFile(
                    input: inputURL,
                    output: developOutputURL,
                    format: .rawScanTIFF,
                    base: nil,
                    params: params,
                    outputProfile: profile
                )
            }),
            (scannerOutputURL, {
                try engine.developScannerFile(
                    input: inputURL,
                    output: scannerOutputURL,
                    format: .rawScanTIFF,
                    base: nil,
                    params: params,
                    outputProfile: profile
                )
            }),
        ]

        for (outputURL, attempt) in attempts {
            XCTAssertThrowsError(try attempt()) { error in
                guard case ChromabaseError.writeFailed(let message) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(message, "invalid printer output ICC profile")
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testPairedMainFlatExportWritesReadableSiblingWithStableSuffix() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let correctedURL = directory.appendingPathComponent("frame42.jpg")
        let corrected = CIImage(color: CIColor(red: 0.65, green: 0.35, blue: 0.20))
            .cropped(to: CGRect(x: 0, y: 0, width: 48, height: 32))
        let mainFlat = CIImage(color: CIColor(red: 0.18, green: 0.28, blue: 0.38))
            .cropped(to: CGRect(x: 0, y: 0, width: 48, height: 32))

        let result = try ExportEngine.writePaired(
            corrected,
            mainFlatMaster: mainFlat,
            to: correctedURL,
            format: .jpeg,
            using: renderContext(),
            metadata: ExportMeta(resolutionDPI: 3200),
            options: ExportOptions(dpi: 0),
            writeMainFlatMaster: true
        )

        let mainFlatURL = try XCTUnwrap(result.mainFlatMasterURL)
        XCTAssertEqual(mainFlatURL.lastPathComponent, "frame42-main-flat.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: correctedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mainFlatURL.path))
        XCTAssertEqual(positiveInt(try imageProperties(at: correctedURL)[kCGImagePropertyPixelWidth]), 48)
        XCTAssertEqual(positiveInt(try imageProperties(at: mainFlatURL)[kCGImagePropertyPixelWidth]), 48)
    }

    func testOriginalRawPairingUsesSourceExtensionAndStableSuffix() {
        let outputURL = URL(fileURLWithPath: "/tmp/frame42.jpg")
        let rawURL = ExportPairing.originalRawURL(for: outputURL, sourceExtension: "tif")

        XCTAssertEqual(rawURL.lastPathComponent, "frame42-original.tif")
    }

    func testPairedMainFlatExportIsOptInAndSkipsUnsupportedInputs() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = CIImage(color: CIColor(red: 0.3, green: 0.4, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 24, height: 24))
        let mainFlat = CIImage(color: CIColor(red: 0.1, green: 0.2, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: 24, height: 24))

        let singleURL = directory.appendingPathComponent("single.png")
        let single = try ExportEngine.writePaired(
            image,
            mainFlatMaster: mainFlat,
            to: singleURL,
            format: .png,
            using: renderContext(),
            writeMainFlatMaster: false
        )
        XCTAssertNil(single.mainFlatMasterURL)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("single-main-flat.png").path
        ))

        let rawURL = directory.appendingPathComponent("raw.tif")
        let raw = try ExportEngine.writePaired(
            image,
            mainFlatMaster: mainFlat,
            to: rawURL,
            format: .rawScanTIFF,
            using: renderContext(),
            writeMainFlatMaster: true
        )
        XCTAssertNil(raw.mainFlatMasterURL)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("raw-main-flat.tif").path
        ))

        let missingURL = directory.appendingPathComponent("missing.png")
        let missing = try ExportEngine.writePaired(
            image,
            mainFlatMaster: nil,
            to: missingURL,
            format: .png,
            using: renderContext(),
            writeMainFlatMaster: true
        )
        XCTAssertNil(missing.mainFlatMasterURL)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("missing-main-flat.png").path
        ))
    }

    func testMainFlatMasterParametersKeepOnlySourceAndGeometryState() {
        var params = DevelopParameters()
        params.filmType = .bwNegative
        params.developTarget = .print
        params.baseEstimationMode = .manual
        params.manualBaseRGB = SIMD3(0.8, 0.7, 0.6)
        params.filmStockDminID = "example-stock"
        params.lightSourceProfileID = "example-light"
        params.scannerProfileID = "profile"
        params.exposure = 1.25
        params.contrast = 0.4
        params.noiseReduction = 0.8
        params.localDodgeBurn = [
            LocalDodgeBurnAdjustment(
                mode: .dodge,
                amount: 0.5,
                mask: .brush(strokes: [
                    LocalDodgeBurnStroke(
                        points: [LocalDodgeBurnPoint(x: 0.5, y: 0.5)],
                        thickness: 0.1,
                        feather: 0.2
                    ),
                ])
            ),
        ]
        params.imageTransform = ImageTransform(rotation: .deg90)

        let master = params.mainFlatMasterParameters()

        XCTAssertEqual(master.filmType, .bwNegative)
        XCTAssertEqual(master.developTarget, .main)
        XCTAssertEqual(master.baseEstimationMode, .manual)
        XCTAssertEqual(master.manualBaseRGB, SIMD3(0.8, 0.7, 0.6))
        XCTAssertEqual(master.filmStockDminID, "example-stock")
        XCTAssertEqual(master.lightSourceProfileID, "example-light")
        XCTAssertEqual(master.imageTransform, ImageTransform(rotation: .deg90))
        XCTAssertNil(master.scannerProfileID)
        XCTAssertEqual(master.exposure, 0)
        XCTAssertEqual(master.contrast, 0)
        XCTAssertEqual(master.noiseReduction, 0)
        XCTAssertTrue(master.localDodgeBurn.isEmpty)
    }

    func testExportPreservesSourceDateAndSeparatesMetadataDate() throws {
        let url = temporaryURL(fileExtension: "tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 12))
        let sourceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let metadataDate = Date(timeIntervalSince1970: 1_800_000_000)

        try ExportEngine.write(
            image,
            to: url,
            format: .tiff16,
            using: renderContext(),
            metadata: ExportMeta(sourceDate: sourceDate, metadataDate: metadataDate)
        )

        let properties = try imageProperties(at: url)
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary] as? [String: Any])
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary] as? [String: Any])
        XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String, "2023:11:14 22:13:20")
        XCTAssertEqual(exif[kCGImagePropertyExifDateTimeDigitized as String] as? String, "2023:11:14 22:13:20")
        XCTAssertEqual(tiff[kCGImagePropertyTIFFDateTime as String] as? String, "2027:01:15 08:00:00")
    }

    func testExportWithoutSourceDateDoesNotInventOriginalDates() {
        let properties = ExportEngine.metadataProperties(ExportMeta(metadataDate: Date(timeIntervalSince1970: 1_800_000_000)))
        let exif = properties[kCGImagePropertyExifDictionary] as? [String: Any]

        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal as String])
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeDigitized as String])
    }

    func testExportUsesExactScannerMakeAndModelWithoutDisplayNameGuessing() throws {
        let properties = ExportEngine.metadataProperties(ExportMeta(
            scannerMake: "Archive Imaging Systems",
            scannerModel: "Model A 9000",
            metadataDate: nil
        ))
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary] as? [String: Any])
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary] as? [String: Any])

        XCTAssertEqual(exif["Make"] as? String, "Archive Imaging Systems")
        XCTAssertEqual(exif["Model"] as? String, "Model A 9000")
        XCTAssertEqual(tiff["Make"] as? String, "Archive Imaging Systems")
        XCTAssertEqual(tiff["Model"] as? String, "Model A 9000")
    }

    func testRepeatedTIFFExportWithFixedProvenanceIsByteDeterministic() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("first.tiff")
        let secondURL = directory.appendingPathComponent("second.tiff")
        let image = CIImage(color: CIColor(red: 0.25, green: 0.5, blue: 0.75))
            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 24))
        let metadata = ExportMeta(
            scannerModel: "Test Scanner",
            resolutionDPI: 3600,
            filmType: FilmType.colorNegative.rawValue,
            software: "negaflow test",
            sourceDate: Date(timeIntervalSince1970: 1_700_000_000),
            metadataDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try ExportEngine.write(image, to: firstURL, format: .tiff16, using: renderContext(), metadata: metadata)
        try ExportEngine.write(image, to: secondURL, format: .tiff16, using: renderContext(), metadata: metadata)

        XCTAssertEqual(try Data(contentsOf: firstURL), try Data(contentsOf: secondURL))
    }

    func testDevelopScannerFileRejectsInputAsOutputWithoutChangingSourceBytes() throws {
        let url = temporaryURL(fileExtension: "tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 12))
        try ExportEngine.write(image, to: url, format: .tiff16, using: renderContext())
        let originalBytes = try Data(contentsOf: url)
        var params = DevelopParameters()
        params.filmType = .colorPositive

        XCTAssertThrowsError(
            try ChromabaseEngine().developScannerFile(
                input: url,
                output: url,
                format: .tiff16,
                base: nil,
                params: params
            )
        )

        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
    }

    func testDestinationSafetyDetectsExistingHardLinkToSource() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.bin")
        let hardLink = directory.appendingPathComponent("output.bin")
        try Data("source".utf8).write(to: source)
        try FileManager.default.linkItem(at: source, to: hardLink)

        XCTAssertTrue(ExportDestinationSafety.referencesSameFile(source, hardLink))
        XCTAssertThrowsError(
            try ExportDestinationSafety.validateDistinct(
                protectedSources: [source],
                outputURLs: [hardLink]
            )
        )
    }

    func testLegacyExportOptionsDecodeUsesEncodingDefaults() throws {
        let data = Data(#"{"colorSpace":"sRGB","dpi":300,"longEdge":2048}"#.utf8)

        let options = try JSONDecoder().decode(ExportOptions.self, from: data)

        XCTAssertEqual(options.jpegQuality, 1.0)
        XCTAssertEqual(options.tiffCompression, .none)
        XCTAssertEqual(options.tiffBitDepth, .sixteen)
        XCTAssertEqual(options.pngBitDepth, .sixteen)
        XCTAssertFalse(options.preserveAlpha)
    }

    func testInvalidFormatOptionsFailBeforePublishingFile() throws {
        let jpegURL = temporaryURL(fileExtension: "jpg")
        let rawURL = temporaryURL(fileExtension: "tif")
        defer {
            try? FileManager.default.removeItem(at: jpegURL)
            try? FileManager.default.removeItem(at: rawURL)
        }
        let image = CIImage(color: .red).cropped(
            to: CGRect(x: 0, y: 0, width: 16, height: 16)
        )

        XCTAssertThrowsError(try ExportEngine.write(
            image,
            to: jpegURL,
            format: .jpeg,
            using: renderContext(),
            options: ExportOptions(jpegQuality: 1.2)
        ))
        XCTAssertThrowsError(try ExportEngine.write(
            image,
            to: rawURL,
            format: .rawScanTIFF,
            using: renderContext(),
            options: ExportOptions(tiffCompression: .lzw)
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: jpegURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rawURL.path))
    }

    func testJPEGQualityChangesActualEncodedOutputAndDropsAlpha() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lowURL = directory.appendingPathComponent("low.jpg")
        let highURL = directory.appendingPathComponent("high.jpg")
        let image = try XCTUnwrap(CIFilter(name: "CIRandomGenerator")?.outputImage)
            .cropped(to: CGRect(x: 0, y: 0, width: 256, height: 256))

        try ExportEngine.write(
            image,
            to: lowURL,
            format: .jpeg,
            using: renderContext(),
            options: ExportOptions(jpegQuality: 0.1)
        )
        try ExportEngine.write(
            image,
            to: highURL,
            format: .jpeg,
            using: renderContext(),
            options: ExportOptions(jpegQuality: 1.0)
        )

        let lowSize = try XCTUnwrap(lowURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let highSize = try XCTUnwrap(highURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertLessThan(lowSize, highSize)
        XCTAssertFalse(
            try imageProperties(at: lowURL)[kCGImagePropertyHasAlpha] as? Bool ?? false
        )
    }

    func testTIFFBitDepthCompressionAndAlphaMatchDecodedFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 24))

        for (bitDepth, compression, preserveAlpha) in [
            (ExportTIFFBitDepth.eight, ExportTIFFCompression.lzw, false),
            (ExportTIFFBitDepth.sixteen, ExportTIFFCompression.deflate, true),
        ] {
            let url = directory.appendingPathComponent(
                "\(bitDepth.rawValue)-\(compression.rawValue).tif"
            )
            try ExportEngine.write(
                image,
                to: url,
                format: .tiff16,
                using: renderContext(),
                options: ExportOptions(
                    tiffCompression: compression,
                    tiffBitDepth: bitDepth,
                    preserveAlpha: preserveAlpha
                )
            )

            let properties = try imageProperties(at: url)
            let tiff = try XCTUnwrap(
                properties[kCGImagePropertyTIFFDictionary] as? [String: Any]
            )
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(decoded.bitsPerComponent, bitDepth.rawValue)
            XCTAssertEqual(
                (tiff[kCGImagePropertyTIFFCompression as String] as? NSNumber)?.intValue,
                compression.imageIOValue
            )
            XCTAssertEqual(
                properties[kCGImagePropertyHasAlpha] as? Bool ?? false,
                preserveAlpha
            )
        }
    }

    // MARK: 크로마 서브샘플링 / PNG 비트 심도

    func testHighJPEGQualityEncodesWithoutChromaSubsampling() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = colorEdgePattern()

        // 고품질 구간(0.95 이상)은 서브샘플링 없이 인코드된다. 그 아래는 사용자가 고른 값 그대로.
        for quality in [1.0, 0.95] {
            let url = directory.appendingPathComponent("q\(quality).jpg")
            try ExportEngine.write(
                image,
                to: url,
                format: .jpeg,
                using: renderContext(),
                options: ExportOptions(jpegQuality: quality)
            )
            XCTAssertEqual(try jpegLumaSamplingFactor(at: url), "1x1", "quality \(quality)")
        }
        let lowURL = directory.appendingPathComponent("low.jpg")
        try ExportEngine.write(
            image,
            to: lowURL,
            format: .jpeg,
            using: renderContext(),
            options: ExportOptions(jpegQuality: 0.8)
        )
        XCTAssertEqual(try jpegLumaSamplingFactor(at: lowURL), "2x2")
    }

    func testJPEGQualityMappingKeepsLowQualityUntouched() {
        XCTAssertEqual(ExportEngine.encodedJPEGQuality(1.0), 1.0)
        XCTAssertEqual(ExportEngine.encodedJPEGQuality(0.95), ExportEngine.chromaSubsamplingFreeQuality)
        XCTAssertEqual(ExportEngine.encodedJPEGQuality(0.9), 0.9)
        XCTAssertEqual(ExportEngine.encodedJPEGQuality(0.1), 0.1)
    }

    func testPNGBitDepthMatchesDecodedFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = colorEdgePattern()

        for depth in ExportBitDepth.allCases {
            let url = directory.appendingPathComponent("png\(depth.rawValue).png")
            try ExportEngine.write(
                image,
                to: url,
                format: .png,
                using: renderContext(),
                options: ExportOptions(pngBitDepth: depth)
            )
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(decoded.bitsPerComponent, depth.rawValue)
        }
    }

    /// JPEG SOF 마커의 첫(휘도) 컴포넌트 샘플링 팩터. "1x1"이면 4:4:4, "2x2"면 4:2:0이다.
    private func jpegLumaSamplingFactor(at url: URL) throws -> String {
        let bytes = [UInt8](try Data(contentsOf: url))
        var index = 2
        while index + 12 < bytes.count {
            guard bytes[index] == 0xFF else {
                index += 1
                continue
            }
            let marker = bytes[index + 1]
            let isStartOfFrame = (0xC0...0xCF).contains(marker)
                && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
            if isStartOfFrame {
                let factor = bytes[index + 11]
                return "\(factor >> 4)x\(factor & 0x0F)"
            }
            index += 2 + (Int(bytes[index + 2]) << 8 | Int(bytes[index + 3]))
        }
        XCTFail("JPEG SOF marker not found")
        return ""
    }

    /// 채도 높은 세로 경계 패턴. 크로마 해상도가 절반이 되면 눈에 띄게 무너지는 입력이다.
    private func colorEdgePattern() -> CIImage {
        let width = 64
        let height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let onStripe = x % 2 == 0
                pixels[index] = onStripe ? 230 : 20
                pixels[index + 1] = onStripe ? 20 : 210
                pixels[index + 2] = onStripe ? 20 : 210
                pixels[index + 3] = 255
            }
        }
        return CIImage(
            bitmapData: Data(pixels),
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
    }

    private func renderContext() -> CIContext {
        CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
    }

    private func temporaryURL(fileExtension ext: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow_export_\(UUID().uuidString).\(ext)")
    }

    private func temporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow_export_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func imageProperties(at url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func writeProfiledPattern(to url: URL) throws -> ICCOutputProfileSnapshot {
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let width = 4
        let height = 3
        let pixels: [UInt8] = [
            18, 52, 91, 255, 44, 103, 167, 255, 71, 149, 219, 255, 118, 203, 37, 255,
            32, 85, 142, 255, 61, 130, 202, 255, 97, 178, 24, 255, 149, 221, 76, 255,
            53, 116, 188, 255, 82, 161, 236, 255, 126, 207, 55, 255, 201, 239, 133, 255,
        ]
        let image = CIImage(
            bitmapData: Data(pixels),
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        try ExportEngine.write(
            image,
            to: url,
            format: .tiff16,
            using: renderContext(),
            outputProfile: profile
        )
        return profile
    }

    private func decodedPixelData(at url: URL) throws -> Data {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let provider = try XCTUnwrap(image.dataProvider)
        return try XCTUnwrap(provider.data) as Data
    }

    private func embeddedICCProfileSHA256(at url: URL) throws -> String {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let data = try XCTUnwrap(image.colorSpace?.copyICCData() as Data?)
        return ICCOutputProfileSnapshot.sha256(data)
    }

    private func positiveInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, number.doubleValue > 0 else { return nil }
        return Int(number.doubleValue.rounded())
    }
}
