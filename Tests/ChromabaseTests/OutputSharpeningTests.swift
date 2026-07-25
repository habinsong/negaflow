import XCTest
import CoreImage
@testable import Chromabase

final class OutputSharpeningTests: XCTestCase {
    func testZeroStrengthIsPixelExactNoOp() throws {
        let image = edgeFixture()
        let output = OutputSharpening.apply(
            to: image,
            strength: 0,
            medium: .mattePaper,
            dpi: 600
        )

        XCTAssertNil(OutputSharpening.parameters(strength: 0, medium: .mattePaper, dpi: 600))
        XCTAssertEqual(try renderBytes(output), try renderBytes(image))
    }

    func testMediumAndResolutionProduceDeterministicParameters() throws {
        let first = try XCTUnwrap(
            OutputSharpening.parameters(strength: 0.7, medium: .glossyPaper, dpi: 300)
        )
        let repeated = try XCTUnwrap(
            OutputSharpening.parameters(strength: 0.7, medium: .glossyPaper, dpi: 300)
        )
        let highResolution = try XCTUnwrap(
            OutputSharpening.parameters(strength: 0.7, medium: .glossyPaper, dpi: 600)
        )
        let matte = try XCTUnwrap(
            OutputSharpening.parameters(strength: 0.7, medium: .mattePaper, dpi: 300)
        )

        XCTAssertEqual(first, repeated)
        XCTAssertGreaterThan(highResolution.radius, first.radius)
        XCTAssertEqual(highResolution.intensity, first.intensity, accuracy: 1e-12)
        XCTAssertGreaterThan(matte.radius, first.radius)
        XCTAssertGreaterThan(matte.intensity, first.intensity)
    }

    func testNonZeroOutputSharpeningChangesFinalSizedPixelsDeterministically() throws {
        let image = edgeFixture()
        let first = OutputSharpening.apply(
            to: image,
            strength: 0.8,
            medium: .screen,
            dpi: 144
        )
        let second = OutputSharpening.apply(
            to: image,
            strength: 0.8,
            medium: .screen,
            dpi: 144
        )
        let inputBytes = try renderBytes(image)
        let firstBytes = try renderBytes(first)

        XCTAssertNotEqual(firstBytes, inputBytes)
        XCTAssertEqual(firstBytes, try renderBytes(second))
    }

    func testRawTIFFRejectsOutputSharpening() {
        XCTAssertThrowsError(
            try ExportOptions(outputSharpening: 0.1).validate(for: .rawScanTIFF)
        )
    }

    private func edgeFixture() -> CIImage {
        let gradient = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 28, y: 0),
            "inputPoint1": CIVector(x: 36, y: 0),
            "inputColor0": CIColor(red: 0.2, green: 0.2, blue: 0.2),
            "inputColor1": CIColor(red: 0.8, green: 0.8, blue: 0.8),
        ])!.outputImage!
        return gradient.cropped(to: CGRect(x: 0, y: 0, width: 64, height: 16))
    }

    private func renderBytes(_ image: CIImage) throws -> Data {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = Data(count: 64 * 16 * 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                image,
                toBitmap: buffer.baseAddress!,
                rowBytes: 64 * 4,
                bounds: image.extent,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return bytes
    }
}
