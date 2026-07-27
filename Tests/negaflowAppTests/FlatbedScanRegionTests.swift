import CoreGraphics
import ImageIO
import XCTest
@testable import Chromabase
@testable import ScannerKit
@testable import negaflowApp

final class FlatbedScanRegionTests: XCTestCase {
    func testCreationCannotBeginInsideExistingRegionOrResizeHandleHitArea() {
        let region = CGRect(x: 40, y: 30, width: 80, height: 50)

        XCTAssertFalse(FlatbedScanAreaOverlayGeometry.canBeginCreation(
            at: CGPoint(x: 70, y: 55),
            existingRects: [region]
        ))
        XCTAssertFalse(FlatbedScanAreaOverlayGeometry.canBeginCreation(
            at: CGPoint(x: 126, y: 80),
            existingRects: [region]
        ))
        XCTAssertTrue(FlatbedScanAreaOverlayGeometry.canBeginCreation(
            at: CGPoint(x: 150, y: 100),
            existingRects: [region]
        ))
    }

    func testResizeHandlesPreserveOppositeEdgesAndResizeRequestedAxes() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 120)
        let start = CGRect(x: 40, y: 30, width: 80, height: 50)

        let top = FlatbedScanAreaOverlayGeometry.resizedRect(
            from: start,
            toward: CGPoint(x: 0, y: 10),
            handle: .top,
            within: bounds
        )
        XCTAssertEqual(top.minX, start.minX)
        XCTAssertEqual(top.maxX, start.maxX)
        XCTAssertEqual(top.minY, 10)
        XCTAssertEqual(top.maxY, start.maxY)

        let right = FlatbedScanAreaOverlayGeometry.resizedRect(
            from: start,
            toward: CGPoint(x: 170, y: 0),
            handle: .right,
            within: bounds
        )
        XCTAssertEqual(right.minX, start.minX)
        XCTAssertEqual(right.maxX, 170)
        XCTAssertEqual(right.minY, start.minY)
        XCTAssertEqual(right.maxY, start.maxY)

        let bottomLeft = FlatbedScanAreaOverlayGeometry.resizedRect(
            from: start,
            toward: CGPoint(x: 15, y: 105),
            handle: .bottomLeft,
            within: bounds
        )
        XCTAssertEqual(bottomLeft.minX, 15)
        XCTAssertEqual(bottomLeft.maxX, start.maxX)
        XCTAssertEqual(bottomLeft.minY, start.minY)
        XCTAssertEqual(bottomLeft.maxY, 105)

        let crossedTopLeft = FlatbedScanAreaOverlayGeometry.resizedRect(
            from: start,
            toward: CGPoint(x: 180, y: 110),
            handle: .topLeft,
            within: bounds
        )
        XCTAssertEqual(crossedTopLeft.maxX, start.maxX)
        XCTAssertEqual(crossedTopLeft.maxY, start.maxY)
        XCTAssertEqual(crossedTopLeft.width, 12)
        XCTAssertEqual(crossedTopLeft.height, 12)

        let boundedBottomRight = FlatbedScanAreaOverlayGeometry.resizedRect(
            from: start,
            toward: CGPoint(x: 300, y: 200),
            handle: .bottomRight,
            within: bounds
        )
        XCTAssertEqual(boundedBottomRight.maxX, bounds.maxX)
        XCTAssertEqual(boundedBottomRight.maxY, bounds.maxY)
    }

    func testHandlePointsRespectTheRegionCoordinateSpace() {
        let size = CGSize(width: 80, height: 50)

        XCTAssertEqual(
            FlatbedScanAreaOverlayGeometry.handlePoint(.topLeft, in: size),
            .zero
        )
        XCTAssertEqual(
            FlatbedScanAreaOverlayGeometry.handlePoint(.right, in: size),
            CGPoint(x: 80, y: 25)
        )
        XCTAssertEqual(
            FlatbedScanAreaOverlayGeometry.handlePoint(.bottom, in: size),
            CGPoint(x: 40, y: 50)
        )
    }

    func testMockFlatbedPreviewUsesPhysicalBedCanvas() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-flatbed-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("preview.tiff")
        let backend = MockScannerBackend()
        backend.sampleNegativesDir = nil
        var options = ScanOptions.preview(scannerID: MockScannerBackend.flatbedScannerID)
        options.scanArea = ScanArea(widthMM: 210, heightMM: 297)
        options.temporaryOutputURL = output

        let result = try await backend.startPreviewScan(options) { _ in }

        XCTAssertEqual(result.width, 1_400)
        XCTAssertEqual(result.height, 1_980)
        XCTAssertGreaterThan(try Data(contentsOf: result.rawFileURL).count, 8_000_000)
    }

    func testVirtualFlatbedFullScanMatchesExactSelectedPreviewROI() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-flatbed-roi-content-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = MockScannerBackend()
        backend.setSimulatorIncludesPerforation(true)
        let capabilities = try await backend.getCapabilities(scannerID: MockScannerBackend.flatbedScannerID)
        let previewArea = try XCTUnwrap(capabilities.physicalScanAreaBounds?.maximum)
        var previewOptions = ScanOptions.preview(scannerID: MockScannerBackend.flatbedScannerID)
        previewOptions.scanArea = previewArea
        previewOptions.temporaryOutputURL = directory.appendingPathComponent("preview.tiff")
        let previewResult = try await backend.startPreviewScan(previewOptions) { _ in }

        let unitROI = CGRect(x: 0.18, y: 0.36, width: 0.24, height: 0.18)
        let physicalROI = try XCTUnwrap(FlatbedScanRegionGeometry.physicalArea(
            for: FlatbedScanRegion(unitRect: unitROI),
            previewScanArea: previewArea,
            capabilities: capabilities
        ))
        XCTAssertEqual(physicalROI.originXMM, 37.7, accuracy: 0.000_001)
        XCTAssertEqual(physicalROI.originYMM, 106.9, accuracy: 0.000_001)
        XCTAssertEqual(physicalROI.widthMM, 50.5, accuracy: 0.000_001)
        XCTAssertEqual(physicalROI.heightMM, 53.5, accuracy: 0.000_001)
        var fullOptions = ScanOptions.strongDefault(scannerID: MockScannerBackend.flatbedScannerID)
        fullOptions.scanArea = physicalROI
        fullOptions.temporaryOutputURL = directory.appendingPathComponent("full.tiff")
        let fullResult = try await backend.startFullScan(fullOptions) { _ in }

        let previewPixels = try TestRGBAImage(url: previewResult.rawFileURL)
        let fullPixels = try TestRGBAImage(url: fullResult.rawFileURL)
        let exactError = meanROIMappingError(
            preview: previewPixels,
            full: fullPixels,
            unitROI: unitROI,
            mapping: { $0 }
        )
        let horizontalMirrorError = meanROIMappingError(
            preview: previewPixels,
            full: fullPixels,
            unitROI: unitROI,
            mapping: { CGPoint(x: 1 - $0.x, y: $0.y) }
        )
        let verticalMirrorError = meanROIMappingError(
            preview: previewPixels,
            full: fullPixels,
            unitROI: unitROI,
            mapping: { CGPoint(x: $0.x, y: 1 - $0.y) }
        )
        let bothMirrorError = meanROIMappingError(
            preview: previewPixels,
            full: fullPixels,
            unitROI: unitROI,
            mapping: { CGPoint(x: 1 - $0.x, y: 1 - $0.y) }
        )
        let bedYFlippedROI = CGRect(
            x: unitROI.minX,
            y: 1 - unitROI.maxY,
            width: unitROI.width,
            height: unitROI.height
        )
        let bedYOriginError = meanROIMappingError(
            preview: previewPixels,
            full: fullPixels,
            unitROI: bedYFlippedROI,
            mapping: { $0 }
        )
        let bedYOriginAndContentError = meanROIMappingError(
            preview: previewPixels,
            full: fullPixels,
            unitROI: bedYFlippedROI,
            mapping: { CGPoint(x: $0.x, y: 1 - $0.y) }
        )
        let ignoredOriginError = meanROIMappingError(
            preview: previewPixels,
            full: fullPixels,
            unitROI: CGRect(x: 0, y: 0, width: unitROI.width, height: unitROI.height),
            mapping: { $0 }
        )

        let measurements = "exact=\(exactError), h=\(horizontalMirrorError), v=\(verticalMirrorError), hv=\(bothMirrorError), bedY=\(bedYOriginError), bedYV=\(bedYOriginAndContentError), origin=\(ignoredOriginError)"
        XCTAssertLessThan(exactError, 8, measurements)
        XCTAssertGreaterThan(horizontalMirrorError, exactError + 4, measurements)
        XCTAssertGreaterThan(verticalMirrorError, exactError + 8, measurements)
        XCTAssertGreaterThan(bothMirrorError, exactError + 8, measurements)
        XCTAssertGreaterThan(bedYOriginError, exactError + 8, measurements)
        XCTAssertGreaterThan(bedYOriginAndContentError, exactError + 8, measurements)
        XCTAssertGreaterThan(ignoredOriginError, exactError + 8, measurements)
    }

    func testVirtualFlatbedAppliedROICornersEdgesSizesAndPositionsMatchPreview() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-flatbed-roi-boundaries-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = MockScannerBackend()
        backend.setSimulatorIncludesPerforation(true)
        let capabilities = try await backend.getCapabilities(scannerID: MockScannerBackend.flatbedScannerID)
        let previewArea = try XCTUnwrap(capabilities.physicalScanAreaBounds?.maximum)
        var previewOptions = ScanOptions.preview(scannerID: MockScannerBackend.flatbedScannerID)
        previewOptions.scanArea = previewArea
        previewOptions.temporaryOutputURL = directory.appendingPathComponent("preview.tiff")
        let previewResult = try await backend.startPreviewScan(previewOptions) { _ in }
        let previewPixels = try TestRGBAImage(url: previewResult.rawFileURL)
        let cases = virtualFlatbedROICases()

        for (index, testCase) in cases.enumerated() {
            let region = FlatbedScanRegion(unitRect: testCase.unitROI)
            let physicalROI = try XCTUnwrap(FlatbedScanRegionGeometry.physicalArea(
                for: region,
                previewScanArea: previewArea,
                capabilities: capabilities
            ), testCase.name)
            let cropUnitROI = try XCTUnwrap(
                mockPreviewCropUnitRect(for: physicalROI, preview: previewPixels),
                testCase.name
            )
            var fullOptions = ScanOptions.strongDefault(scannerID: MockScannerBackend.flatbedScannerID)
            fullOptions.scanArea = physicalROI
            fullOptions.temporaryOutputURL = directory.appendingPathComponent("full-\(index).tiff")
            let fullResult = try await backend.startFullScan(fullOptions) { _ in }
            let fullPixels = try TestRGBAImage(url: fullResult.rawFileURL)
            let measurements = roiBoundaryMeasurements(
                preview: previewPixels,
                full: fullPixels,
                cropUnitROI: cropUnitROI
            )
            let diagnostic = "\(testCase.name): mean=\(measurements.meanError), max=\(measurements.maximumError), corners=\(measurements.cornerErrors)"

            XCTAssertLessThan(measurements.meanError, 8, diagnostic)
            XCTAssertLessThan(measurements.maximumError, 32, diagnostic)
            for (corner, error) in measurements.cornerErrors {
                XCTAssertLessThan(error, 24, "\(diagnostic), failedCorner=\(corner)")
            }
        }
    }

    func testEveryFilmFormatAutoDetectedFramesMatchFullScanPreviewROIs() async throws {
        let cases: [(format: FilmFrameFormat, expectedCount: Int)] = [
            (.fullFrame35mm, 6),
            (.square35mm, 8),
            (.halfFrame35mm, 11),
            (.medium645, 4),
            (.medium66, 3),
            (.medium67, 2),
            (.medium68, 2),
            (.medium69, 2),
            (.medium612, 1),
            (.medium617, 1),
        ]

        for testCase in cases {
            let directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(
                    "negaflow-flatbed-format-roi-\(testCase.format.rawValue)-\(UUID().uuidString)",
                    isDirectory: true
                )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: directory) }
            let backend = MockScannerBackend()
            backend.setSimulatorIncludesPerforation(false)
            backend.setSimulatorFrameFormat(testCase.format)
            backend.setSimulatorFrameCount(testCase.expectedCount)
            let capabilities = try await backend.getCapabilities(
                scannerID: MockScannerBackend.flatbedScannerID
            )
            let previewArea = try XCTUnwrap(
                capabilities.physicalScanAreaBounds?.maximum,
                testCase.format.displayName
            )
            var previewOptions = ScanOptions.preview(
                scannerID: MockScannerBackend.flatbedScannerID
            )
            previewOptions.scanArea = previewArea
            previewOptions.temporaryOutputURL = directory.appendingPathComponent("preview.tiff")
            let previewResult = try await backend.startPreviewScan(previewOptions) { _ in }
            let detections = try FlatbedFrameDetector.detect(
                url: previewResult.rawFileURL,
                frameFormat: testCase.format
            )

            XCTAssertEqual(
                detections.count,
                testCase.expectedCount,
                testCase.format.displayName
            )
            XCTAssertEqual(
                detections.map(\.column),
                Array(0..<testCase.expectedCount),
                testCase.format.displayName
            )
            XCTAssertTrue(
                detections.allSatisfy { $0.row == 0 },
                testCase.format.displayName
            )

            let previewPixels = try TestRGBAImage(url: previewResult.rawFileURL)
            for detection in detections {
                let context = "\(testCase.format.displayName), frame=\(detection.column)"
                let physicalROI = try XCTUnwrap(
                    FlatbedScanRegionGeometry.physicalArea(
                        for: FlatbedScanRegion(
                            unitRect: detection.normalizedRect,
                            straightenAngle: detection.straightenAngle
                        ),
                        previewScanArea: previewArea,
                        capabilities: capabilities
                    ),
                    context
                )
                let cropUnitROI = try XCTUnwrap(
                    mockPreviewCropUnitRect(for: physicalROI, preview: previewPixels),
                    context
                )
                var fullOptions = ScanOptions.strongDefault(
                    scannerID: MockScannerBackend.flatbedScannerID
                )
                fullOptions.scanArea = physicalROI
                fullOptions.temporaryOutputURL = directory.appendingPathComponent(
                    "full-\(detection.column).tiff"
                )
                let fullResult = try await backend.startFullScan(fullOptions) { _ in }
                guard case .verified(let appliedOptions) = fullResult.appliedOptionsEvidence else {
                    XCTFail("\(context): 본 스캔 적용 영역 증명 누락")
                    continue
                }
                XCTAssertEqual(appliedOptions.scanArea, physicalROI, context)

                let fullPixels = try TestRGBAImage(url: fullResult.rawFileURL)
                let measurements = lowPassROIBoundaryMeasurements(
                    preview: previewPixels,
                    full: fullPixels,
                    cropUnitROI: cropUnitROI
                )
                let diagnostic = "\(context): mean=\(measurements.meanError), max=\(measurements.maximumError), corners=\(measurements.cornerErrors)"
                XCTAssertLessThan(measurements.meanError, 13, diagnostic)
                XCTAssertLessThan(measurements.maximumError, 52, diagnostic)
                for (corner, error) in measurements.cornerErrors {
                    XCTAssertLessThan(error, 14, "\(diagnostic), failedCorner=\(corner)")
                }
            }
        }
    }

    func testFlatbedPhysicalROIStaysWithinOneHardwareStepOfSelectedCornersAndEdges() async throws {
        let capabilities = try await MockScannerBackend().getCapabilities(
            scannerID: MockScannerBackend.flatbedScannerID
        )
        let previewArea = try XCTUnwrap(capabilities.physicalScanAreaBounds?.maximum)

        for testCase in virtualFlatbedROICases() {
            let region = FlatbedScanRegion(unitRect: testCase.unitROI)
            if testCase.name == "very-small" {
                XCTAssertEqual(region.unitRect.width, 0.035, accuracy: 0.000_001)
                XCTAssertEqual(region.unitRect.height, 0.035, accuracy: 0.000_001)
            }
            let requestedArea = ScanArea(
                originXMM: previewArea.originXMM + Double(region.unitRect.minX) * previewArea.widthMM,
                originYMM: previewArea.originYMM + Double(region.unitRect.minY) * previewArea.heightMM,
                widthMM: Double(region.unitRect.width) * previewArea.widthMM,
                heightMM: Double(region.unitRect.height) * previewArea.heightMM
            )
            let physicalROI = try XCTUnwrap(FlatbedScanRegionGeometry.physicalArea(
                for: region,
                previewScanArea: previewArea,
                capabilities: capabilities
            ), testCase.name)

            assertAppliedAreaStaysWithinHardwareStep(
                physicalROI,
                requested: requestedArea,
                maximumStepMM: 0.1,
                context: testCase.name,
                file: #filePath,
                line: #line
            )
        }
    }

    func testNormalizedRegionMapsToPositionedPhysicalArea() throws {
        let capabilities = ScannerCapabilities(
            supportsScanArea: true,
            supportsPositionedScanArea: true,
            maxScanArea: ScanArea(originXMM: 5, originYMM: 10, widthMM: 200, heightMM: 100),
            minScanArea: ScanArea(originXMM: 5, originYMM: 10, widthMM: 1, heightMM: 1)
        )
        let region = FlatbedScanRegion(
            unitRect: CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.4)
        )

        XCTAssertEqual(
            try XCTUnwrap(FlatbedScanRegionGeometry.physicalArea(
                for: region,
                capabilities: capabilities
            )),
            ScanArea(originXMM: 55, originYMM: 30, widthMM: 60, heightMM: 40)
        )
    }

    func testNormalizedRegionMapsWithinTheAreaActuallyUsedForPreview() throws {
        let capabilities = ScannerCapabilities(
            supportsScanArea: true,
            supportsPositionedScanArea: true,
            maxScanArea: ScanArea(originXMM: 5, originYMM: 10, widthMM: 200, heightMM: 100),
            minScanArea: ScanArea(originXMM: 5, originYMM: 10, widthMM: 1, heightMM: 1)
        )
        let previewScanArea = ScanArea(originXMM: 25, originYMM: 20, widthMM: 100, heightMM: 50)
        let region = FlatbedScanRegion(
            unitRect: CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.4)
        )

        XCTAssertEqual(
            try XCTUnwrap(FlatbedScanRegionGeometry.physicalArea(
                for: region,
                previewScanArea: previewScanArea,
                capabilities: capabilities
            )),
            ScanArea(originXMM: 50, originYMM: 30, widthMM: 30, heightMM: 20)
        )
    }

    func testPhysicalScanResultAspectMustMatchRequestedArea() {
        let area = ScanArea(originXMM: 20, originYMM: 30, widthMM: 60, heightMM: 30)

        XCTAssertTrue(FlatbedScanRegionGeometry.outputMatchesPhysicalAspect(
            width: 2_400,
            height: 1_200,
            scanArea: area
        ))
        XCTAssertTrue(FlatbedScanRegionGeometry.outputMatchesPhysicalAspect(
            width: 2_401,
            height: 1_200,
            scanArea: area
        ))
        XCTAssertFalse(FlatbedScanRegionGeometry.outputMatchesPhysicalAspect(
            width: 1_200,
            height: 2_400,
            scanArea: area
        ))
        XCTAssertTrue(FlatbedScanRegionGeometry.outputMatchesPhysicalAspect(
            width: 2_440,
            height: 1_200,
            scanArea: area,
            relativeTolerance: 0.02,
            minimumPixelTolerance: 3
        ))
        XCTAssertFalse(FlatbedScanRegionGeometry.outputMatchesPhysicalAspect(
            width: 2_449,
            height: 1_200,
            scanArea: area,
            relativeTolerance: 0.02,
            minimumPixelTolerance: 3
        ))
    }
}

private struct TestRGBAImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScannerError(.ioFailure, "test image decode")
        }
        let imageWidth = image.width
        let imageHeight = image.height
        var storage = [UInt8](repeating: 0, count: imageWidth * imageHeight * 4)
        let rendered = storage.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: imageWidth,
                height: imageHeight,
                bitsPerComponent: 8,
                bytesPerRow: imageWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.translateBy(x: 0, y: CGFloat(imageHeight))
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            return true
        }
        guard rendered else { throw ScannerError(.ioFailure, "test image render") }
        width = imageWidth
        height = imageHeight
        pixels = storage
    }

    func rgb(at unitPoint: CGPoint) -> SIMD3<Double> {
        let x = min(max(Int((unitPoint.x * CGFloat(width)).rounded(.down)), 0), width - 1)
        let y = min(max(Int((unitPoint.y * CGFloat(height)).rounded(.down)), 0), height - 1)
        let offset = (y * width + x) * 4
        return SIMD3(
            Double(pixels[offset]),
            Double(pixels[offset + 1]),
            Double(pixels[offset + 2])
        )
    }

    func interpolatedRGB(at unitPoint: CGPoint) -> SIMD3<Double> {
        let pixelX = unitPoint.x * CGFloat(width) - 0.5
        let pixelY = unitPoint.y * CGFloat(height) - 0.5
        let x0 = min(max(Int(floor(pixelX)), 0), width - 1)
        let y0 = min(max(Int(floor(pixelY)), 0), height - 1)
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let xFraction = min(max(Double(pixelX - CGFloat(x0)), 0), 1)
        let yFraction = min(max(Double(pixelY - CGFloat(y0)), 0), 1)
        let top = pixelRGB(x: x0, y: y0) * (1 - xFraction)
            + pixelRGB(x: x1, y: y0) * xFraction
        let bottom = pixelRGB(x: x0, y: y1) * (1 - xFraction)
            + pixelRGB(x: x1, y: y1) * xFraction
        return top * (1 - yFraction) + bottom * yFraction
    }

    private func pixelRGB(x: Int, y: Int) -> SIMD3<Double> {
        let offset = (y * width + x) * 4
        return SIMD3(
            Double(pixels[offset]),
            Double(pixels[offset + 1]),
            Double(pixels[offset + 2])
        )
    }
}

private struct ROIBoundaryMeasurements {
    var meanError: Double
    var maximumError: Double
    var cornerErrors: [String: Double]
}

private func virtualFlatbedROICases() -> [(name: String, unitROI: CGRect)] {
    [
        ("full-bed", CGRect(x: 0, y: 0, width: 1, height: 1)),
        ("top-left", CGRect(x: 0, y: 0, width: 0.2, height: 0.2)),
        ("top-right", CGRect(x: 0.8, y: 0, width: 0.2, height: 0.2)),
        ("bottom-left", CGRect(x: 0, y: 0.8, width: 0.2, height: 0.2)),
        ("bottom-right", CGRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2)),
        ("top-edge", CGRect(x: 0.3, y: 0, width: 0.4, height: 0.18)),
        ("right-edge", CGRect(x: 0.82, y: 0.3, width: 0.18, height: 0.4)),
        ("bottom-edge", CGRect(x: 0.3, y: 0.82, width: 0.4, height: 0.18)),
        ("left-edge", CGRect(x: 0, y: 0.3, width: 0.18, height: 0.4)),
        (
            "very-small",
            CGRect(
                x: 102.5 / 210,
                y: 146 / 297,
                width: 5 / 210,
                height: 5 / 297
            )
        ),
        ("very-wide", CGRect(x: 0.05, y: 0.46, width: 0.9, height: 0.08)),
        ("very-tall", CGRect(x: 0.46, y: 0.05, width: 0.08, height: 0.9)),
        ("center", CGRect(x: 0.27, y: 0.23, width: 0.46, height: 0.54)),
    ]
}

private func assertAppliedAreaStaysWithinHardwareStep(
    _ applied: ScanArea,
    requested: ScanArea,
    maximumStepMM: Double,
    context: String,
    file: StaticString,
    line: UInt
) {
    let epsilon = 0.000_001
    XCTAssertLessThanOrEqual(
        abs(requested.originXMM - applied.originXMM),
        maximumStepMM + epsilon,
        "\(context): left edge differs by more than one hardware step",
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        abs(requested.originYMM - applied.originYMM),
        maximumStepMM + epsilon,
        "\(context): top edge differs by more than one hardware step",
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        abs(
            applied.originXMM + applied.widthMM
                - requested.originXMM - requested.widthMM
        ),
        maximumStepMM + epsilon,
        "\(context): right edge differs by more than one hardware step",
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        abs(
            applied.originYMM + applied.heightMM
                - requested.originYMM - requested.heightMM
        ),
        maximumStepMM + epsilon,
        "\(context): bottom edge differs by more than one hardware step",
        file: file,
        line: line
    )
}

private func mockPreviewCropUnitRect(
    for area: ScanArea,
    preview: TestRGBAImage
) -> CGRect? {
    guard let cropRect = MockScannerBackend.flatbedPreviewCropRect(
        for: area,
        imageSize: CGSize(width: preview.width, height: preview.height)
    ) else { return nil }
    return CGRect(
        x: cropRect.minX / CGFloat(preview.width),
        y: 1 - cropRect.maxY / CGFloat(preview.height),
        width: cropRect.width / CGFloat(preview.width),
        height: cropRect.height / CGFloat(preview.height)
    )
}

private func roiBoundaryMeasurements(
    preview: TestRGBAImage,
    full: TestRGBAImage,
    cropUnitROI: CGRect
) -> ROIBoundaryMeasurements {
    let samples = boundarySamplePoints(width: full.width, height: full.height)
    var errors: [Double] = []
    var cornerErrors: [String: Double] = [:]
    for sample in samples {
        let previewPoint = CGPoint(
            x: cropUnitROI.minX + sample.point.x * cropUnitROI.width,
            y: cropUnitROI.minY + sample.point.y * cropUnitROI.height
        )
        let expected = preview.interpolatedRGB(at: previewPoint)
        let actual = full.interpolatedRGB(at: sample.point)
        let error = meanRGBError(expected, actual)
        errors.append(error)
        if sample.isCorner {
            cornerErrors[sample.name] = error
        }
    }
    return ROIBoundaryMeasurements(
        meanError: errors.reduce(0, +) / Double(errors.count),
        maximumError: errors.max() ?? 0,
        cornerErrors: cornerErrors
    )
}

private func lowPassROIBoundaryMeasurements(
    preview: TestRGBAImage,
    full: TestRGBAImage,
    cropUnitROI: CGRect
) -> ROIBoundaryMeasurements {
    let samples = boundarySamplePoints(width: full.width, height: full.height)
    var errors: [Double] = []
    var cornerErrors: [String: Double] = [:]
    for sample in samples {
        let error = meanMappedPatchError(
            preview: preview,
            full: full,
            cropUnitROI: cropUnitROI,
            fullUnitPoint: sample.point
        )
        errors.append(error)
        if sample.isCorner {
            cornerErrors[sample.name] = error
        }
    }
    return ROIBoundaryMeasurements(
        meanError: errors.reduce(0, +) / Double(errors.count),
        maximumError: errors.max() ?? 0,
        cornerErrors: cornerErrors
    )
}

private func meanMappedPatchError(
    preview: TestRGBAImage,
    full: TestRGBAImage,
    cropUnitROI: CGRect,
    fullUnitPoint: CGPoint
) -> Double {
    let radius: CGFloat = 0.01
    let offsets = stride(from: -2, through: 2, by: 1).map {
        CGFloat($0) * radius / 2
    }
    var expected = SIMD3<Double>(repeating: 0)
    var actual = SIMD3<Double>(repeating: 0)
    var count = 0.0
    for yOffset in offsets {
        for xOffset in offsets {
            let localPoint = CGPoint(
                x: min(max(fullUnitPoint.x + xOffset, 0), 1),
                y: min(max(fullUnitPoint.y + yOffset, 0), 1)
            )
            let previewPoint = CGPoint(
                x: cropUnitROI.minX + localPoint.x * cropUnitROI.width,
                y: cropUnitROI.minY + localPoint.y * cropUnitROI.height
            )
            expected += preview.interpolatedRGB(at: previewPoint)
            actual += full.interpolatedRGB(at: localPoint)
            count += 1
        }
    }
    return meanRGBError(expected / count, actual / count)
}

private func boundarySamplePoints(
    width: Int,
    height: Int
) -> [(name: String, point: CGPoint, isCorner: Bool)] {
    func pixelCenteredUnit(_ fraction: Int, count: Int) -> CGFloat {
        let index = Int((Double(fraction) / 10 * Double(count - 1)).rounded())
        return (CGFloat(index) + 0.5) / CGFloat(count)
    }
    let minX = pixelCenteredUnit(0, count: width)
    let maxX = pixelCenteredUnit(10, count: width)
    let minY = pixelCenteredUnit(0, count: height)
    let maxY = pixelCenteredUnit(10, count: height)
    var samples: [(name: String, point: CGPoint, isCorner: Bool)] = []
    for position in 0...10 {
        let x = pixelCenteredUnit(position, count: width)
        samples.append(("top-\(position * 10)%", CGPoint(x: x, y: minY), position == 0 || position == 10))
        samples.append(("bottom-\(position * 10)%", CGPoint(x: x, y: maxY), position == 0 || position == 10))
    }
    for position in 1..<10 {
        let y = pixelCenteredUnit(position, count: height)
        samples.append(("left-\(position * 10)%", CGPoint(x: minX, y: y), false))
        samples.append(("right-\(position * 10)%", CGPoint(x: maxX, y: y), false))
    }
    return samples
}

private func meanRGBError(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
    (abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y) + abs(lhs.z - rhs.z)) / 3
}

private func meanROIMappingError(
    preview: TestRGBAImage,
    full: TestRGBAImage,
    unitROI: CGRect,
    mapping: (CGPoint) -> CGPoint
) -> Double {
    var total = 0.0
    var count = 0
    for row in 1...8 {
        for column in 1...8 {
            let local = CGPoint(x: CGFloat(column) / 9, y: CGFloat(row) / 9)
            let mapped = mapping(local)
            let previewPoint = CGPoint(
                x: unitROI.minX + mapped.x * unitROI.width,
                y: unitROI.minY + mapped.y * unitROI.height
            )
            let expected = preview.rgb(at: previewPoint)
            let actual = full.rgb(at: local)
            total += (abs(expected.x - actual.x)
                + abs(expected.y - actual.y)
                + abs(expected.z - actual.z)) / 3
            count += 1
        }
    }
    return total / Double(count)
}
