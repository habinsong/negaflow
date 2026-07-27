import CoreGraphics
import CoreImage
import CryptoKit
import ImageIO
import XCTest
@testable import Chromabase

final class FlatbedFrameDetectorTests: XCTestCase {
    func testAnalysisPixelsUseDocumentedTopLeftOrigin() throws {
        let width = 4
        let height = 4
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                bytes[offset] = y < height / 2 ? 240 : 0
                bytes[offset + 2] = y < height / 2 ? 0 : 240
                bytes[offset + 3] = 255
            }
        }
        let source = try makeRGBAImage(width: width, height: height, pixels: bytes)
        let analysis = try XCTUnwrap(AnalysisImage(image: source, maxDimension: 4))

        XCTAssertGreaterThan(analysis.pixels[0], analysis.pixels[2])
        let lastPixel = (width * height - 1) * 4
        XCTAssertGreaterThan(analysis.pixels[lastPixel + 2], analysis.pixels[lastPixel])
    }

    func testSpecifiedScannerSimulatorFixturesHaveStableIdentityAndTopology() throws {
        let fixtures = [
            Fixture(
                name: "Roll.tiff",
                sha256: "768767b5a1306c82e370bbbaea0e26175d8f6790b8d1deb9743f9997ff5221ff",
                rows: 1,
                columns: 6,
                expectedStraightenAngles: [0.087]
            ),
            Fixture(
                name: "Roll_Perforation.tiff",
                sha256: "ae17ea9079a0f3921525e314dae24e444b085cd4f67fd7b2ac689382bb461ef4",
                rows: 3,
                columns: 6,
                expectedStraightenAngles: [-0.092, 0.120, 0.084]
            ),
        ]

        for fixture in fixtures {
            let url = fixtureURL(fixture.name)
            let data = try Data(contentsOf: url)
            XCTAssertEqual(sha256(data), fixture.sha256, fixture.name)

            let detections = try FlatbedFrameDetector.detect(url: url)

            assertTopology(detections, fixture: fixture)
            assertValidGeometry(detections, fixture: fixture)
            if fixture.name == "Roll_Perforation.tiff" {
                let expectedApertures = [
                    (minY: 93.0 / 1_898.0, maxY: 487.0 / 1_898.0),
                    (minY: 762.0 / 1_898.0, maxY: 1_160.0 / 1_898.0),
                    (minY: 1_411.0 / 1_898.0, maxY: 1_805.0 / 1_898.0),
                ]
                for (row, expected) in expectedApertures.enumerated() {
                    let rowRects = detections.filter { $0.row == row }.map(\.normalizedRect)
                    XCTAssertTrue(rowRects.allSatisfy {
                        abs($0.minY - expected.minY) <= 0.008
                            && abs($0.maxY - expected.maxY) <= 0.008
                    }, "\(fixture.name), row=\(row), rects=\(rowRects)")
                }
            }
            for (row, expectedAngle) in fixture.expectedStraightenAngles.enumerated() {
                let rowAngles = detections.filter { $0.row == row }.map(\.straightenAngle)
                XCTAssertTrue(rowAngles.allSatisfy {
                    abs($0 - expectedAngle) <= 0.35
                }, "\(fixture.name), row=\(row), angles=\(rowAngles)")
            }
        }
    }

    func testSpecifiedRollFixtureDetectsWhenTheWholeStripIsRotated() throws {
        let source = try loadImage(fixtureURL("Roll.tiff"))
        let analysis = try XCTUnwrap(
            AnalysisImage(image: source, maxDimension: max(source.width, source.height))
        )
        let rotatedPixels = analysis.rotatedCounterClockwise()
        let rotatedImage = try makeRGBAImage(
            width: rotatedPixels.width,
            height: rotatedPixels.height,
            pixels: rotatedPixels.pixels
        )

        let detections = FlatbedFrameDetector.detect(image: rotatedImage)

        XCTAssertEqual(detections.count, 6)
        XCTAssertEqual(detections.map(\.row), Array(0..<6))
        XCTAssertTrue(detections.allSatisfy { $0.column == 0 })
        XCTAssertTrue(detections.allSatisfy {
            let pixelAspect = Double($0.normalizedRect.width) * Double(rotatedImage.width)
                / (Double($0.normalizedRect.height) * Double(rotatedImage.height))
            return abs(pixelAspect / FilmFrameOrientation.portrait.aspect(for: .fullFrame35mm) - 1)
                <= 0.12
        })
    }

    func testSpecifiedRollFixtureToleratesHolderOffsetAndSmallSkew() throws {
        let source = try loadImage(fixtureURL("Roll.tiff"))
        let skewed = try rotatedOnWhiteCanvas(source, degrees: 2)
        let shifted = try placedOnWhiteCanvas(
            skewed,
            left: 37,
            top: 83,
            right: 211,
            bottom: 29
        )

        let detections = FlatbedFrameDetector.detect(image: shifted)

        XCTAssertEqual(detections.count, 6)
        XCTAssertEqual(detections.map(\.column), Array(0..<6))
        XCTAssertTrue(detections.allSatisfy { abs($0.straightenAngle) >= 0.5 })
        XCTAssertTrue(detections.allSatisfy {
            $0.normalizedRect.minX >= 0
                && $0.normalizedRect.minY >= 0
                && $0.normalizedRect.maxX <= 1
                && $0.normalizedRect.maxY <= 1
        })
    }

    func testSelectedFilmFrameFormatsDetectTheirPhysicalStripTopology() throws {
        let cases: [(format: FilmFrameFormat, columns: Int)] = [
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
            let image = try makeFormatOverview(
                frameFormat: testCase.format,
                columns: testCase.columns
            )
            let detections = FlatbedFrameDetector.detect(
                image: image,
                frameFormat: testCase.format
            )

            XCTAssertEqual(detections.count, testCase.columns, testCase.format.displayName)
            XCTAssertEqual(detections.map(\.column), Array(0..<testCase.columns))
            XCTAssertTrue(detections.allSatisfy { $0.row == 0 })
            for detection in detections {
                let rect = detection.normalizedRect
                let detectedAspect = Double(rect.width) * Double(image.width)
                    / (Double(rect.height) * Double(image.height))
                XCTAssertEqual(
                    detectedAspect,
                    testCase.format.stripFrameAspect,
                    accuracy: 0.04,
                    testCase.format.displayName
                )
            }
        }
    }

    func testEveryFilmFormatDetectsLandscapeAndPortraitFrames() throws {
        for (formatIndex, frameFormat) in FilmFrameFormat.allCases.enumerated() {
            for orientation in FilmFrameOrientation.allCases {
                let frameCount = [1, 4, 6][formatIndex % 3]
                let image = try makeFlexibleOverview(
                    frameFormat: frameFormat,
                    rows: [Array(repeating: orientation, count: frameCount)]
                )
                let detections = FlatbedFrameDetector.detect(
                    image: image,
                    frameFormat: frameFormat,
                    maxAnalysisDimension: 1_024
                )

                XCTAssertEqual(
                    detections.count,
                    frameCount,
                    "\(frameFormat.displayName), \(orientation.rawValue)"
                )
                for detection in detections {
                    let pixelAspect = Double(detection.normalizedRect.width) * Double(image.width)
                        / (Double(detection.normalizedRect.height) * Double(image.height))
                    XCTAssertEqual(
                        pixelAspect,
                        orientation.aspect(for: frameFormat),
                        accuracy: orientation.aspect(for: frameFormat) * 0.12,
                        "\(frameFormat.displayName), \(orientation.rawValue)"
                    )
                }
            }
        }
    }

    func test35mmAnd120FrameCountsComeFromPixelsInsteadOfFormatDefaults() throws {
        for frameFormat in [FilmFrameFormat.fullFrame35mm, .medium67] {
            for frameCount in [1, 4, 6] {
                let image = try makeFlexibleOverview(
                    frameFormat: frameFormat,
                    rows: [Array(repeating: .landscape, count: frameCount)]
                )

                XCTAssertEqual(
                    FlatbedFrameDetector.detect(
                        image: image,
                        frameFormat: frameFormat,
                        maxAnalysisDimension: 1_024
                    ).count,
                    frameCount,
                    "\(frameFormat.displayName), count=\(frameCount)"
                )
            }
        }
    }

    func testMixedOrientationsMissingSlotsAndUnevenRowsKeepOnlyPresentFrames() throws {
        let rows: [[FilmFrameOrientation?]] = [
            [.landscape, nil, .portrait, .landscape, nil, .portrait],
            [.portrait, .landscape, nil],
        ]
        let image = try makeFlexibleOverview(frameFormat: .medium67, rows: rows)

        let detections = FlatbedFrameDetector.detect(
            image: image,
            frameFormat: .medium67,
            maxAnalysisDimension: 1_024
        )

        XCTAssertEqual(detections.count, 6)
        XCTAssertEqual(
            Dictionary(grouping: detections, by: \.row)
                .sorted { $0.key < $1.key }
                .map { $0.value.count },
            [4, 2]
        )
        let aspects = detections.map {
            Double($0.normalizedRect.width) * Double(image.width)
                / (Double($0.normalizedRect.height) * Double(image.height))
        }
        XCTAssertTrue(aspects.contains {
            abs($0 / FilmFrameOrientation.landscape.aspect(for: .medium67) - 1) <= 0.12
        })
        XCTAssertTrue(aspects.contains {
            abs($0 / FilmFrameOrientation.portrait.aspect(for: .medium67) - 1) <= 0.12
        })
    }

    func testUniformOrientationMissingSlotsDoNotCreatePhantomFrames() throws {
        let image = try makeFlexibleOverview(
            frameFormat: .fullFrame35mm,
            rows: [[.landscape, nil, .landscape, .landscape, nil, .landscape]]
        )

        let detections = FlatbedFrameDetector.detect(
            image: image,
            frameFormat: .fullFrame35mm,
            maxAnalysisDimension: 1_024
        )

        XCTAssertEqual(detections.count, 4)
        XCTAssertEqual(detections.map(\.row), [0, 0, 0, 0])
        XCTAssertEqual(detections.map(\.column), [0, 1, 2, 3])
    }

    func testSelectedFormatPrevents645FramesFromMergingInto35mmPairs() throws {
        let image = try makeFormatOverview(frameFormat: .medium645, columns: 4)

        XCTAssertEqual(
            FlatbedFrameDetector.detect(image: image, frameFormat: .medium645).count,
            4
        )
        XCTAssertNotEqual(
            FlatbedFrameDetector.detect(image: image, frameFormat: .fullFrame35mm).count,
            4
        )
    }

    func testSpecifiedFixturesKeepGeometryAcrossPolarityAndMonochromeVariants() throws {
        for fixture in [
            Fixture(
                name: "Roll.tiff",
                sha256: "",
                rows: 1,
                columns: 6,
                expectedStraightenAngles: []
            ),
            Fixture(
                name: "Roll_Perforation.tiff",
                sha256: "",
                rows: 3,
                columns: 6,
                expectedStraightenAngles: []
            ),
        ] {
            let source = try loadImage(fixtureURL(fixture.name))
            let baseline = FlatbedFrameDetector.detect(image: source)
            assertTopology(baseline, fixture: fixture)

            for options in [(false, true), (true, false), (true, true)] {
                let variant = try transformed(
                    source,
                    monochrome: options.0,
                    inverted: options.1
                )
                let detections = FlatbedFrameDetector.detect(image: variant)
                assertTopology(detections, fixture: fixture)
                XCTAssertEqual(detections.count, baseline.count)
                let verticalTolerance = fixture.rows == 1 ? 0.020 : 0.012
                for (actual, expected) in zip(detections, baseline) {
                    XCTAssertEqual(actual.normalizedRect.minX, expected.normalizedRect.minX, accuracy: 0.012)
                    XCTAssertEqual(
                        actual.normalizedRect.minY,
                        expected.normalizedRect.minY,
                        accuracy: verticalTolerance
                    )
                    XCTAssertEqual(actual.normalizedRect.width, expected.normalizedRect.width, accuracy: 0.018)
                    XCTAssertEqual(actual.normalizedRect.height, expected.normalizedRect.height, accuracy: 0.018)
                    XCTAssertEqual(actual.straightenAngle, expected.straightenAngle, accuracy: 0.5)
                }
            }
        }
    }

    func testSpecifiedPerforatedFixtureKeepsTopologyAfterColorManagedToneTransforms() throws {
        let fixture = Fixture(
            name: "Roll_Perforation.tiff",
            sha256: "",
            rows: 3,
            columns: 6,
            expectedStraightenAngles: []
        )
        let source = try loadImage(fixtureURL(fixture.name))
        let baseline = FlatbedFrameDetector.detect(image: source)
        for options in [(false, true), (true, false), (true, true)] {
            let variant = try colorManagedTransformed(
                source,
                monochrome: options.0,
                inverted: options.1
            )
            let detections = FlatbedFrameDetector.detect(image: variant)
            assertTopology(detections, fixture: fixture)
            for (actual, expected) in zip(detections, baseline) {
                XCTAssertEqual(actual.normalizedRect.minY, expected.normalizedRect.minY, accuracy: 0.012)
                XCTAssertEqual(actual.normalizedRect.maxY, expected.normalizedRect.maxY, accuracy: 0.012)
                XCTAssertEqual(actual.normalizedRect.height, expected.normalizedRect.height, accuracy: 0.012)
            }
        }
    }

    func testSpecifiedPerforatedFixtureKeepsFramesWithAsymmetricVerticalPadding() throws {
        let fixture = Fixture(
            name: "Roll_Perforation.tiff",
            sha256: "",
            rows: 3,
            columns: 6,
            expectedStraightenAngles: []
        )
        let source = try loadImage(fixtureURL(fixture.name))
        let baseline = FlatbedFrameDetector.detect(image: source)
        assertTopology(baseline, fixture: fixture)

        for (topFraction, bottomFraction) in [(0.02, 0.06), (0.06, 0.02)] {
            let topPadding = Int((Double(source.height) * topFraction).rounded())
            let bottomPadding = Int((Double(source.height) * bottomFraction).rounded())
            let padded = try verticallyPadded(
                source,
                top: topPadding,
                bottom: bottomPadding
            )
            let detections = FlatbedFrameDetector.detect(image: padded)
            assertTopology(detections, fixture: fixture)

            let paddedHeight = Double(source.height + topPadding + bottomPadding)
            for (actual, sourceDetection) in zip(detections, baseline) {
                let expectedMinY = (
                    sourceDetection.normalizedRect.minY * Double(source.height)
                        + Double(topPadding)
                ) / paddedHeight
                let expectedHeight = sourceDetection.normalizedRect.height
                    * Double(source.height) / paddedHeight
                XCTAssertEqual(actual.normalizedRect.minX, sourceDetection.normalizedRect.minX, accuracy: 0.006)
                XCTAssertEqual(actual.normalizedRect.width, sourceDetection.normalizedRect.width, accuracy: 0.006)
                XCTAssertEqual(actual.normalizedRect.minY, expectedMinY, accuracy: 0.012)
                XCTAssertEqual(actual.normalizedRect.height, expectedHeight, accuracy: 0.012)
            }
        }
    }

    func testAmbiguousUniformImageFailsClosed() throws {
        let width = 1_200
        let height = 800
        let bytes = [UInt8](repeating: 127, count: width * height * 4)
        let image = try makeRGBAImage(width: width, height: height, pixels: bytes)

        XCTAssertTrue(FlatbedFrameDetector.detect(image: image).isEmpty)
    }

    func testSingleOrdinaryImageDoesNotMasqueradeAsRepeatedFilmStrip() throws {
        let width = 1_200
        let height = 800
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let value: UInt8 = x < width / 2 ? 40 : 220
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
                bytes[offset + 3] = 255
            }
        }
        let image = try makeRGBAImage(width: width, height: height, pixels: bytes)

        XCTAssertTrue(FlatbedFrameDetector.detect(image: image).isEmpty)
    }

    private func assertTopology(
        _ detections: [FlatbedFrameDetection],
        fixture: Fixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            detections.count,
            fixture.rows * fixture.columns,
            fixture.name,
            file: file,
            line: line
        )
        for row in 0..<fixture.rows {
            let rowDetections = detections.filter { $0.row == row }
            XCTAssertEqual(rowDetections.count, fixture.columns, fixture.name, file: file, line: line)
            XCTAssertEqual(rowDetections.map(\.column), Array(0..<fixture.columns), fixture.name, file: file, line: line)
        }
        XCTAssertEqual(
            detections.map { "(\($0.row), \($0.column))" },
            expectedOrder(fixture)
        )
    }

    private func assertValidGeometry(
        _ detections: [FlatbedFrameDetection],
        fixture: Fixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for detection in detections {
            let rect = detection.normalizedRect
            XCTAssertGreaterThan(rect.width, 0.12, fixture.name, file: file, line: line)
            XCTAssertLessThan(rect.width, 0.20, fixture.name, file: file, line: line)
            XCTAssertGreaterThan(rect.height, 0.18, fixture.name, file: file, line: line)
            XCTAssertLessThanOrEqual(rect.maxX, 1, fixture.name, file: file, line: line)
            XCTAssertLessThanOrEqual(rect.maxY, 1, fixture.name, file: file, line: line)
            XCTAssertGreaterThanOrEqual(rect.minX, 0, fixture.name, file: file, line: line)
            XCTAssertGreaterThanOrEqual(rect.minY, 0, fixture.name, file: file, line: line)
            XCTAssertTrue((-5...5).contains(detection.straightenAngle), fixture.name, file: file, line: line)
            XCTAssertTrue((0...1).contains(detection.confidence), fixture.name, file: file, line: line)
        }
        for row in 0..<fixture.rows {
            let rowDetections = detections.filter { $0.row == row }
            for (left, right) in zip(rowDetections, rowDetections.dropFirst()) {
                XCTAssertLessThanOrEqual(
                    left.normalizedRect.maxX,
                    right.normalizedRect.minX,
                    fixture.name,
                    file: file,
                    line: line
                )
            }
        }
    }

    private func expectedOrder(_ fixture: Fixture) -> [String] {
        (0..<fixture.rows).flatMap { row in
            (0..<fixture.columns).map { column in "(\(row), \(column))" }
        }
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ScannerKit/Resources", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func makeRGBAImage(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    private func makeFormatOverview(
        frameFormat: FilmFrameFormat,
        columns: Int
    ) throws -> CGImage {
        let frameHeight = 240
        let frameWidth = Int(
            (Double(frameHeight) * frameFormat.stripFrameAspect).rounded()
        )
        let margin = 10
        let width = frameWidth * columns
        let height = frameHeight + margin * 2
        var pixels = [UInt8](repeating: 246, count: width * height * 4)
        for y in margin..<(margin + frameHeight) {
            for x in 0..<width {
                let column = x / frameWidth
                let localX = x % frameWidth
                let offset = (y * width + x) * 4
                let boundary = column > 0 && localX < 4
                let texture = (x * 7 + y * 11 + column * 37) % 92
                if boundary {
                    pixels[offset] = 242
                    pixels[offset + 1] = 242
                    pixels[offset + 2] = 242
                } else {
                    pixels[offset] = UInt8(34 + texture)
                    pixels[offset + 1] = UInt8(50 + texture / 2)
                    pixels[offset + 2] = UInt8(72 + texture / 3)
                }
                pixels[offset + 3] = 255
            }
        }
        return try makeRGBAImage(width: width, height: height, pixels: pixels)
    }

    private func makeFlexibleOverview(
        frameFormat: FilmFrameFormat,
        rows: [[FilmFrameOrientation?]]
    ) throws -> CGImage {
        let frameHeight = 240
        let horizontalMargin = 80
        let verticalMargin = 40
        let rowGap = 56
        let rowWidths = rows.map { row in
            row.reduce(0) { width, orientation in
                let effectiveOrientation = orientation ?? .landscape
                return width + max(
                    64,
                    Int(
                        (Double(frameHeight) * effectiveOrientation.aspect(for: frameFormat))
                            .rounded()
                    )
                )
            }
        }
        let width = max(256, (rowWidths.max() ?? 0) + horizontalMargin * 2)
        let height = verticalMargin * 2
            + rows.count * frameHeight
            + max(0, rows.count - 1) * rowGap
        var pixels = [UInt8](repeating: 246, count: width * height * 4)

        for (rowIndex, row) in rows.enumerated() {
            let rowWidth = rowWidths[rowIndex]
            var frameStart = (width - rowWidth) / 2
            let frameTop = verticalMargin + rowIndex * (frameHeight + rowGap)
            for (column, orientation) in row.enumerated() {
                let effectiveOrientation = orientation ?? .landscape
                let frameWidth = max(
                    64,
                    Int(
                        (Double(frameHeight) * effectiveOrientation.aspect(for: frameFormat))
                            .rounded()
                    )
                )
                defer { frameStart += frameWidth }
                guard orientation != nil else { continue }
                for y in frameTop..<(frameTop + frameHeight) {
                    for x in frameStart..<(frameStart + frameWidth) {
                        let offset = (y * width + x) * 4
                        let border = x - frameStart < 8
                            || frameStart + frameWidth - x <= 8
                            || y - frameTop < 8
                            || frameTop + frameHeight - y <= 8
                        let texture = (x * 7 + y * 11 + rowIndex * 29 + column * 37) % 92
                        if border {
                            pixels[offset] = 246
                            pixels[offset + 1] = 246
                            pixels[offset + 2] = 246
                        } else {
                            pixels[offset] = UInt8(34 + texture)
                            pixels[offset + 1] = UInt8(50 + texture / 2)
                            pixels[offset + 2] = UInt8(72 + texture / 3)
                        }
                        pixels[offset + 3] = 255
                    }
                }
            }
        }
        return try makeRGBAImage(width: width, height: height, pixels: pixels)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func loadImage(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func transformed(
        _ source: CGImage,
        monochrome: Bool,
        inverted: Bool
    ) throws -> CGImage {
        let width = source.width
        let height = source.height
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let address = bytes.baseAddress,
                  let context = CGContext(
                      data: address,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                          | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(rendered)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            if monochrome {
                let red = 77 * Int(pixels[offset])
                let green = 150 * Int(pixels[offset + 1])
                let blue = 29 * Int(pixels[offset + 2])
                let gray = UInt8((red + green + blue + 128) >> 8)
                pixels[offset] = gray
                pixels[offset + 1] = gray
                pixels[offset + 2] = gray
            }
            if inverted {
                pixels[offset] = 255 - pixels[offset]
                pixels[offset + 1] = 255 - pixels[offset + 1]
                pixels[offset + 2] = 255 - pixels[offset + 2]
            }
            pixels[offset + 3] = 255
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    private func colorManagedTransformed(
        _ source: CGImage,
        monochrome: Bool,
        inverted: Bool
    ) throws -> CGImage {
        var image = CIImage(cgImage: source)
        if monochrome {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0,
            ])
        }
        if inverted {
            image = image.applyingFilter("CIColorInvert")
        }
        return try XCTUnwrap(CIContext().createCGImage(image, from: image.extent))
    }

    private func verticallyPadded(_ source: CGImage, top: Int, bottom: Int) throws -> CGImage {
        let sourceImage = CIImage(cgImage: source)
        let outputExtent = CGRect(
            x: 0,
            y: 0,
            width: source.width,
            height: source.height + top + bottom
        )
        let background = CIImage(color: CIColor.white).cropped(to: outputExtent)
        let translated = sourceImage.transformed(
            by: CGAffineTransform(translationX: 0, y: CGFloat(bottom))
        )
        return try XCTUnwrap(
            CIContext().createCGImage(translated.composited(over: background), from: outputExtent)
        )
    }

    private func rotatedOnWhiteCanvas(_ source: CGImage, degrees: Double) throws -> CGImage {
        let rotated = CIImage(cgImage: source).transformed(
            by: CGAffineTransform(rotationAngle: CGFloat(degrees * .pi / 180))
        )
        let extent = rotated.extent.integral
        let outputExtent = CGRect(origin: .zero, size: extent.size)
        let translated = rotated.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        )
        let background = CIImage(color: CIColor.white).cropped(to: outputExtent)
        return try XCTUnwrap(
            CIContext().createCGImage(translated.composited(over: background), from: outputExtent)
        )
    }

    private func placedOnWhiteCanvas(
        _ source: CGImage,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int
    ) throws -> CGImage {
        let outputExtent = CGRect(
            x: 0,
            y: 0,
            width: source.width + left + right,
            height: source.height + top + bottom
        )
        let background = CIImage(color: CIColor.white).cropped(to: outputExtent)
        let translated = CIImage(cgImage: source).transformed(
            by: CGAffineTransform(translationX: CGFloat(left), y: CGFloat(bottom))
        )
        return try XCTUnwrap(
            CIContext().createCGImage(translated.composited(over: background), from: outputExtent)
        )
    }
}

private struct Fixture {
    let name: String
    let sha256: String
    let rows: Int
    let columns: Int
    let expectedStraightenAngles: [Double]
}
