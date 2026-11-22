import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

final class PrintCompositionTests: XCTestCase {
    func testA4At300DPIGeneratesExpectedPortraitAndLandscapePixelSizes() throws {
        let portrait = try XCTUnwrap(PrintCompositionLayout.make(
            sourceSize: CGSize(width: 2, height: 3),
            settings: PrintCompositionSettings(paperSize: .a4, orientation: .portrait, dpi: 300)
        ))
        XCTAssertEqual(portrait.canvasSize.width, 2480, accuracy: 1)
        XCTAssertEqual(portrait.canvasSize.height, 3508, accuracy: 1)

        let landscape = try XCTUnwrap(PrintCompositionLayout.make(
            sourceSize: CGSize(width: 3, height: 2),
            settings: PrintCompositionSettings(paperSize: .a4, orientation: .landscape, dpi: 300)
        ))
        XCTAssertEqual(landscape.canvasSize.width, portrait.canvasSize.height)
        XCTAssertEqual(landscape.canvasSize.height, portrait.canvasSize.width)
    }

    func testImageUsesAspectFitInsidePhysicalMarginsWithoutCropping() throws {
        let layout = try XCTUnwrap(PrintCompositionLayout.make(
            sourceSize: CGSize(width: 3, height: 2),
            settings: PrintCompositionSettings(
                paperSize: .eightByTen,
                orientation: .landscape,
                marginMM: 12,
                dpi: 300
            )
        ))

        XCTAssertTrue(layout.contentRect.contains(layout.imageRect))
        XCTAssertEqual(layout.imageRect.width / layout.imageRect.height, 1.5, accuracy: 1e-9)
        XCTAssertNil(layout.filmRect)
        XCTAssertTrue(layout.perforationRects.isEmpty)
    }

    func testThirtyFiveMillimeterPerforationsStayInTwoFilmRails() throws {
        let layout = try XCTUnwrap(PrintCompositionLayout.make(
            sourceSize: CGSize(width: 3, height: 2),
            settings: PrintCompositionSettings(
                paperSize: .fourBySix,
                orientation: .landscape,
                marginMM: 5,
                dpi: 300,
                perforationStyle: .thirtyFiveMillimeter
            )
        ))
        let filmRect = try XCTUnwrap(layout.filmRect)

        XCTAssertFalse(layout.perforationRects.isEmpty)
        XCTAssertEqual(layout.perforationRects.count, 16)
        XCTAssertTrue(layout.perforationRects.allSatisfy(filmRect.contains))
        XCTAssertTrue(layout.perforationRects.allSatisfy { !$0.intersects(layout.imageRect) })
        XCTAssertEqual(layout.imageRect.width / layout.imageRect.height, 1.5, accuracy: 1e-9)
        XCTAssertEqual(filmRect.width / filmRect.height, 38.0 / 35.0, accuracy: 1e-9)
        XCTAssertGreaterThan(layout.perforationCornerRadius, 0)
        let firstHole = try XCTUnwrap(layout.perforationRects.first)
        XCTAssertEqual(firstHole.width / firstHole.height, 2.79 / 1.98, accuracy: 1e-9)
    }

    func testPortraitThirtyFiveMillimeterFrameRotatesFilmAndPerforationRails() throws {
        let layout = try XCTUnwrap(PrintCompositionLayout.make(
            sourceSize: CGSize(width: 2, height: 3),
            settings: PrintCompositionSettings(
                paperSize: .fourBySix,
                orientation: .portrait,
                marginMM: 5,
                dpi: 300,
                perforationStyle: .thirtyFiveMillimeter
            )
        ))
        let filmRect = try XCTUnwrap(layout.filmRect)
        let firstHole = try XCTUnwrap(layout.perforationRects.first)

        XCTAssertEqual(layout.perforationRects.count, 16)
        XCTAssertEqual(filmRect.width / filmRect.height, 35.0 / 38.0, accuracy: 1e-9)
        XCTAssertEqual(firstHole.height / firstHole.width, 2.79 / 1.98, accuracy: 1e-9)
        XCTAssertTrue(layout.perforationRects.allSatisfy(filmRect.contains))
        XCTAssertTrue(layout.perforationRects.allSatisfy { !$0.intersects(layout.imageRect) })
    }

    func testFilmStripAppearanceTracksAllFourFilmTypes() {
        let colorNegative = PrintFilmStripAppearance(filmType: .colorNegative).baseRGBA
        let bwNegative = PrintFilmStripAppearance(filmType: .bwNegative).baseRGBA
        let colorPositive = PrintFilmStripAppearance(filmType: .colorPositive).baseRGBA
        let bwPositive = PrintFilmStripAppearance(filmType: .bwPositive).baseRGBA

        XCTAssertGreaterThan(colorNegative.x, colorNegative.z)
        XCTAssertEqual(bwNegative.x, bwNegative.y)
        XCTAssertEqual(bwNegative.y, bwNegative.z)
        XCTAssertNotEqual(colorPositive, bwPositive)
        XCTAssertEqual(Set([colorNegative, bwNegative, colorPositive, bwPositive]).count, 4)
    }

    func testRendererProducesPaperSizedFiniteOutput() throws {
        let input = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.7))
            .cropped(to: CGRect(x: 10, y: 20, width: 30, height: 20))
        let settings = PrintCompositionSettings(
            paperSize: .fourBySix,
            orientation: .landscape,
            marginMM: 5,
            dpi: 72,
            perforationStyle: .thirtyFiveMillimeter
        )
        let layout = try XCTUnwrap(PrintCompositionLayout.make(sourceSize: input.extent.size, settings: settings))
        let output = try XCTUnwrap(PrintCompositionRenderer.apply(
            to: input,
            settings: settings,
            filmType: .colorNegative
        ))

        XCTAssertEqual(output.extent, CGRect(origin: .zero, size: layout.canvasSize))
        XCTAssertFalse(output.extent.isInfinite)
        XCTAssertFalse(output.extent.isNull)
    }

    func testRendererBakesAllThreeSheetColorsIntoPaperPixels() throws {
        let input = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 3, height: 2))
        let expectations: [(PrintContactSheetBackground, Float)] = [
            (.black, 0),
            (.gray, 0.5),
            (.white, 1),
        ]

        for (sheetBackground, expectedChannel) in expectations {
            let output = try XCTUnwrap(PrintCompositionRenderer.apply(
                to: input,
                settings: PrintCompositionSettings(
                    paperSize: .fourBySix,
                    orientation: .landscape,
                    marginMM: 5,
                    dpi: 72,
                    sheetBackground: sheetBackground
                )
            ))
            let pixel = try rgba(output)
            XCTAssertEqual(pixel.x, expectedChannel, accuracy: 0.001)
            XCTAssertEqual(pixel.y, expectedChannel, accuracy: 0.001)
            XCTAssertEqual(pixel.z, expectedChannel, accuracy: 0.001)
            XCTAssertEqual(pixel.w, 1, accuracy: 0.001)
        }
    }

    func testPresentationStylesApplyExpectedMonochromeRelationships() throws {
        let source = CIImage(color: CIColor(red: 0.2, green: 0.45, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))

        let cyanotype = try rgba(
            PrintPresentationRenderer.apply(to: source, style: .cyanotype)
        )
        XCTAssertGreaterThan(cyanotype.z, cyanotype.y)
        XCTAssertGreaterThan(cyanotype.y, cyanotype.x)

        let gelatin = try rgba(
            PrintPresentationRenderer.apply(to: source, style: .gelatinSilver)
        )
        XCTAssertEqual(gelatin.x, gelatin.y, accuracy: 0.001)
        XCTAssertEqual(gelatin.y, gelatin.z, accuracy: 0.001)

        let black = CIImage(color: .black)
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let glassPlate = try rgba(
            PrintPresentationRenderer.apply(to: black, style: .glassPlate)
        )
        XCTAssertGreaterThan(glassPlate.x, 0.99)
        XCTAssertEqual(glassPlate.x, glassPlate.y, accuracy: 0.001)
        XCTAssertEqual(glassPlate.y, glassPlate.z, accuracy: 0.001)
    }

    /// 파일·워터마크 미리보기도 화면(SwiftUI `.grayscale(1).colorInvert()`)과 윈도우
    /// `PrintPresentationFilter` 처럼 **표시값**의 Rec.709 밝기로 계산해야 한다. 선형에서
    /// 반전하던 앞 판은 sRGB 118 을 234 로 냈다(화면 137).
    func testPresentationStylesComputeOnDisplayValuesLikeTheScreen() throws {
        let gray = CIImage(color: CIColor(red: 118 / 255, green: 118 / 255, blue: 118 / 255))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let glassPlate = try rgba(PrintPresentationRenderer.apply(to: gray, style: .glassPlate))
        XCTAssertEqual(glassPlate.x * 255, 137, accuracy: 0.5)

        let color = CIImage(color: CIColor(red: 0.2, green: 0.45, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let luminance: Float = 0.2126 * 0.2 + 0.7152 * 0.45 + 0.0722 * 0.8
        let gelatin = try rgba(PrintPresentationRenderer.apply(to: color, style: .gelatinSilver))
        XCTAssertEqual(gelatin.y, luminance, accuracy: 0.002)

        let palette = PrintPresentationAppearance(style: .cyanotype)
        let cyanotype = try rgba(PrintPresentationRenderer.apply(to: color, style: .cyanotype))
        let expectedBlue = Float(palette.shadowRGBA.z)
            + (Float(palette.highlightRGBA.z) - Float(palette.shadowRGBA.z)) * luminance
        XCTAssertEqual(cyanotype.z, expectedBlue, accuracy: 0.002)
    }

    func testLegacyCompositionWithoutPresentationStyleDecodesAsStandard() throws {
        let encoded = try JSONEncoder().encode(PrintCompositionSettings())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "presentationStyle")
        object.removeValue(forKey: "sheetBackground")

        let decoded = try JSONDecoder().decode(
            PrintCompositionSettings.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.presentationStyle, .standard)
        XCTAssertEqual(decoded.sheetBackground, .white)
    }

    func testInvalidLayoutSettingsAreRejected() {
        XCTAssertNil(PrintCompositionLayout.make(
            sourceSize: CGSize(width: 3, height: 2),
            settings: PrintCompositionSettings(marginMM: .nan, dpi: 300)
        ))
        XCTAssertNil(PrintCompositionLayout.make(
            sourceSize: CGSize(width: 3, height: 2),
            settings: PrintCompositionSettings(marginMM: 10, dpi: 2400)
        ))
    }

    private func rgba(_ image: CIImage) throws -> SIMD4<Float> {
        var pixels = [Float](repeating: 0, count: 4)
        let context = CIContext()
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        pixels.withUnsafeMutableBytes { bytes in
            context.render(
                image,
                toBitmap: bytes.baseAddress!,
                rowBytes: MemoryLayout<Float>.size * 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBAf,
                colorSpace: colorSpace
            )
        }
        return SIMD4(pixels[0], pixels[1], pixels[2], pixels[3])
    }
}
