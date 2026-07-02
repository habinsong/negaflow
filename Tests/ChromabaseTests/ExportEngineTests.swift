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
        XCTAssertEqual(master.imageTransform, ImageTransform(rotation: .deg90))
        XCTAssertNil(master.scannerProfileID)
        XCTAssertEqual(master.exposure, 0)
        XCTAssertEqual(master.contrast, 0)
        XCTAssertEqual(master.noiseReduction, 0)
        XCTAssertTrue(master.localDodgeBurn.isEmpty)
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

    private func positiveInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, number.doubleValue > 0 else { return nil }
        return Int(number.doubleValue.rounded())
    }
}
