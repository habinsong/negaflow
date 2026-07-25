import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

final class PrintPackageRendererTests: XCTestCase {
    private let context = CIContext(options: [.useSoftwareRenderer: true])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    func testRendererPlacesDifferentSourcesInTheirAssignedContactSheetCells() throws {
        let composition = PrintCompositionSettings(
            paperSize: .fourBySix,
            orientation: .landscape,
            marginMM: 5,
            dpi: 72
        )
        let package = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 1,
            contactColumns: 2,
            horizontalSpacingMM: 5,
            verticalSpacingMM: 0,
            contentMode: .fill
        )
        let layout = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [CGSize(width: 30, height: 20), CGSize(width: 20, height: 30)],
            composition: composition,
            package: package
        )).first!
        let rendered = try XCTUnwrap(PrintPackageRenderer.renderPage(
            sources: [
                PrintPackageRenderSource(image: solid(.red, size: CGSize(width: 30, height: 20))),
                PrintPackageRenderSource(image: solid(.blue, size: CGSize(width: 20, height: 30))),
            ],
            layout: layout,
            dpi: 72
        ))

        XCTAssertEqual(rendered.extent.size.width, 432, accuracy: 1)
        XCTAssertEqual(rendered.extent.size.height, 288, accuracy: 1)
        assertPixel(at: layout.items[0].destinationRectPoints.center, in: rendered, isNear: [255, 0, 0])
        assertPixel(at: layout.items[1].destinationRectPoints.center, in: rendered, isNear: [0, 0, 255])
        assertPixel(at: CGPoint(x: 2, y: 2), in: rendered, isNear: [255, 255, 255])
    }

    func testRendererHonorsCenteredFillCropInsteadOfSquashingImage() throws {
        let composition = PrintCompositionSettings(
            paperSize: .fourBySix,
            orientation: .portrait,
            marginMM: 5,
            dpi: 72
        )
        let custom = PrintCustomPackageItem(
            sourceIndex: 0,
            normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            contentMode: .fill
        )
        let package = PrintPackageSettings(mode: .customPackage, customItems: [custom])
        let source = threeVerticalBands()
        let layout = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [source.extent.size],
            composition: composition,
            package: package
        )).first!
        let rendered = try XCTUnwrap(PrintPackageRenderer.renderPage(
            sources: [PrintPackageRenderSource(image: source)],
            layout: layout,
            dpi: 72
        ))

        XCTAssertLessThan(layout.items[0].sourceUnitCropRect.width, 0.5)
        assertPixel(at: layout.items[0].destinationRectPoints.center, in: rendered, isNear: [0, 255, 0])
        assertPixel(
            at: CGPoint(
                x: layout.items[0].destinationRectPoints.minX + 2,
                y: layout.items[0].destinationRectPoints.midY
            ),
            in: rendered,
            isNear: [0, 255, 0]
        )
    }

    func testRendererDrawsCaptionAndCropMarksWithoutChangingPageExtent() throws {
        let composition = PrintCompositionSettings(
            paperSize: .fourBySix,
            orientation: .landscape,
            marginMM: 8,
            dpi: 72
        )
        let package = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 1,
            contactColumns: 2,
            horizontalSpacingMM: 8,
            verticalSpacingMM: 0,
            captionMode: .fileName,
            captionHeightMM: 8,
            showsCropMarks: true,
            cropMarkLengthMM: 3
        )
        let layout = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [CGSize(width: 30, height: 20), CGSize(width: 30, height: 20)],
            composition: composition,
            package: package
        )).first!
        let rendered = try XCTUnwrap(PrintPackageRenderer.renderPage(
            sources: [
                PrintPackageRenderSource(
                    image: solid(.red, size: CGSize(width: 30, height: 20)),
                    caption: "frame-001.tiff"
                ),
                PrintPackageRenderSource(
                    image: solid(.blue, size: CGSize(width: 30, height: 20)),
                    caption: "frame-002.tiff"
                ),
            ],
            layout: layout,
            dpi: 72
        ))

        XCTAssertEqual(rendered.extent.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(rendered.extent.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(rendered.extent.width, layout.canvasSizePoints.width, accuracy: 1)
        XCTAssertEqual(rendered.extent.height, layout.canvasSizePoints.height, accuracy: 1)
        let caption = try XCTUnwrap(layout.items[0].captionRectPoints)
        XCTAssertTrue(hasNonWhitePixel(in: caption, image: rendered, stride: 2))
        let segment = try XCTUnwrap(layout.cropMarkSegments.first)
        assertPixel(at: segment.midpoint, in: rendered, maximumChannel: 220)
    }

    func testRendererConvertsPointLayoutToRequestedDPI() throws {
        let composition = PrintCompositionSettings(
            paperSize: .a4,
            orientation: .portrait,
            marginMM: 10,
            dpi: 300
        )
        let package = PrintPackageSettings(mode: .picturePackage, pictureTemplate: .fourUp)
        let layout = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [CGSize(width: 3, height: 2)],
            composition: composition,
            package: package
        )).first!
        let rendered = try XCTUnwrap(PrintPackageRenderer.renderPage(
            sources: [PrintPackageRenderSource(image: solid(.red, size: CGSize(width: 3, height: 2)))],
            layout: layout,
            dpi: 300
        ))

        XCTAssertEqual(rendered.extent.width, 2480, accuracy: 1)
        XCTAssertEqual(rendered.extent.height, 3508, accuracy: 1)
    }

    func testRendererRotatesAsymmetricSourceCounterclockwiseInQuartzCoordinates() throws {
        let source = fourQuadrants()
        let package = PrintPackageSettings(
            mode: .customPackage,
            customItems: [
                PrintCustomPackageItem(
                    sourceIndex: 0,
                    normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    rotateToFit: true
                ),
            ]
        )
        let layout = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [source.extent.size],
            composition: PrintCompositionSettings(
                paperSize: .fourBySix,
                orientation: .portrait,
                marginMM: 5,
                dpi: 72
            ),
            package: package
        )).first!
        let item = layout.items[0]
        XCTAssertEqual(item.quarterTurns, 1)
        let rendered = try XCTUnwrap(PrintPackageRenderer.renderPage(
            sources: [PrintPackageRenderSource(image: source)],
            layout: layout,
            dpi: 72
        ))
        let destination = item.destinationRectPoints

        assertPixel(
            at: CGPoint(x: destination.minX + destination.width * 0.25,
                        y: destination.minY + destination.height * 0.25),
            in: rendered,
            isNear: [0, 0, 255]
        )
        assertPixel(
            at: CGPoint(x: destination.maxX - destination.width * 0.25,
                        y: destination.minY + destination.height * 0.25),
            in: rendered,
            isNear: [255, 0, 0]
        )
        assertPixel(
            at: CGPoint(x: destination.minX + destination.width * 0.25,
                        y: destination.maxY - destination.height * 0.25),
            in: rendered,
            isNear: [255, 255, 0]
        )
        assertPixel(
            at: CGPoint(x: destination.maxX - destination.width * 0.25,
                        y: destination.maxY - destination.height * 0.25),
            in: rendered,
            isNear: [0, 255, 0]
        )
    }

    func testRendererRejectsInvalidSourceContract() throws {
        let layout = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [CGSize(width: 3, height: 2)],
            composition: PrintCompositionSettings(dpi: 72),
            package: PrintPackageSettings(mode: .picturePackage)
        )).first!
        XCTAssertNil(PrintPackageRenderer.renderPage(sources: [], layout: layout, dpi: 72))
        XCTAssertNil(PrintPackageRenderer.renderPage(
            sources: [
                PrintPackageRenderSource(
                    image: solid(.red, size: CGSize(width: 3, height: 2)),
                    caption: String(repeating: "x", count: 513)
                ),
            ],
            layout: layout,
            dpi: 72
        ))
        XCTAssertNil(PrintPackageRenderer.renderPage(
            sources: [PrintPackageRenderSource(image: solid(.red, size: CGSize(width: 3, height: 2)))],
            layout: layout,
            dpi: 1_200
        ))
        let item = layout.items[0]
        let invalidCaptionItem = PrintPackageItemLayout(
            sourceIndex: item.sourceIndex,
            cellRectPoints: item.cellRectPoints,
            destinationRectPoints: item.destinationRectPoints,
            sourceUnitCropRect: item.sourceUnitCropRect,
            quarterTurns: item.quarterTurns,
            captionRectPoints: CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10),
            zIndex: item.zIndex
        )
        XCTAssertNil(PrintPackageRenderer.renderPage(
            sources: [PrintPackageRenderSource(image: solid(.red, size: CGSize(width: 3, height: 2)))],
            layout: PrintPackagePageLayout(
                pageIndex: layout.pageIndex,
                canvasSizePoints: layout.canvasSizePoints,
                contentRectPoints: layout.contentRectPoints,
                items: [invalidCaptionItem],
                cropMarkSegments: layout.cropMarkSegments
            ),
            dpi: 72
        ))
    }

    private func solid(_ color: CIColor, size: CGSize) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(origin: CGPoint(x: 11, y: 17), size: size))
    }

    private func threeVerticalBands() -> CIImage {
        let red = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let green = CIImage(color: .green).cropped(to: CGRect(x: 100, y: 0, width: 100, height: 100))
        let blue = CIImage(color: .blue).cropped(to: CGRect(x: 200, y: 0, width: 100, height: 100))
        return red.composited(over: green).composited(over: blue)
            .cropped(to: CGRect(x: 0, y: 0, width: 300, height: 100))
    }

    private func fourQuadrants() -> CIImage {
        let red = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 10))
        let green = CIImage(color: .green).cropped(to: CGRect(x: 20, y: 0, width: 20, height: 10))
        let blue = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 10, width: 20, height: 10))
        let yellow = CIImage(color: CIColor(red: 1, green: 1, blue: 0))
            .cropped(to: CGRect(x: 20, y: 10, width: 20, height: 10))
        return red
            .composited(over: green)
            .composited(over: blue)
            .composited(over: yellow)
            .cropped(to: CGRect(x: 0, y: 0, width: 40, height: 20))
    }

    private func pixel(at point: CGPoint, in image: CIImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(x: floor(point.x), y: floor(point.y), width: 1, height: 1),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        return bytes
    }

    private func assertPixel(
        at point: CGPoint,
        in image: CIImage,
        isNear expected: [UInt8],
        tolerance: Int = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = pixel(at: point, in: image)
        for channel in 0..<3 {
            XCTAssertLessThanOrEqual(
                abs(Int(actual[channel]) - Int(expected[channel])),
                tolerance,
                "channel \(channel): \(actual)",
                file: file,
                line: line
            )
        }
    }

    private func assertPixel(
        at point: CGPoint,
        in image: CIImage,
        maximumChannel: UInt8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = pixel(at: point, in: image)
        XCTAssertLessThanOrEqual(actual[0], maximumChannel, file: file, line: line)
        XCTAssertLessThanOrEqual(actual[1], maximumChannel, file: file, line: line)
        XCTAssertLessThanOrEqual(actual[2], maximumChannel, file: file, line: line)
    }

    private func hasNonWhitePixel(in rect: CGRect, image: CIImage, stride: Int) -> Bool {
        var y = Int(rect.minY)
        while y < Int(rect.maxY) {
            var x = Int(rect.minX)
            while x < Int(rect.maxX) {
                let value = pixel(at: CGPoint(x: x, y: y), in: image)
                if value[0] < 240 || value[1] < 240 || value[2] < 240 { return true }
                x += stride
            }
            y += stride
        }
        return false
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

private extension PrintPackageLineSegment {
    var midpoint: CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }
}
