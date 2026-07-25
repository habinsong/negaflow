import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

final class ChannelClippingOverlayTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    func testMarksExactChannelBoundariesAndLeavesInRangePixelsTransparent() throws {
        let input = image([
            SIMD4<Float>(0.25, 0.50, 0.75, 1),
            SIMD4<Float>(0.00, 0.40, 0.60, 1),
            SIMD4<Float>(0.20, 1.00, 0.40, 1),
            SIMD4<Float>(-0.10, 0.50, 1.10, 1),
        ])

        let overlay = try XCTUnwrap(ChannelClippingOverlay.makeOverlay(for: input))
        let pixels = render(overlay, width: 4)

        assertPixel(pixels, at: 0, equals: SIMD4<Float>(0, 0, 0, 0))
        assertOverlay(pixels, at: 1, color: ChannelClippingOverlay.shadowColor)
        assertOverlay(pixels, at: 2, color: ChannelClippingOverlay.highlightColor)
        assertOverlay(pixels, at: 3, color: ChannelClippingOverlay.mixedColor)
    }

    func testDetectsAnySingleClippedRGBChannel() throws {
        let input = image([
            SIMD4<Float>(0.50, -0.01, 0.50, 1),
            SIMD4<Float>(0.50, 0.50, 1.01, 1),
        ])

        let pixels = render(try XCTUnwrap(ChannelClippingOverlay.makeOverlay(for: input)), width: 2)

        assertOverlay(pixels, at: 0, color: ChannelClippingOverlay.shadowColor)
        assertOverlay(pixels, at: 1, color: ChannelClippingOverlay.highlightColor)
    }

    private func image(_ pixels: [SIMD4<Float>]) -> CIImage {
        let values = pixels.flatMap { [$0.x, $0.y, $0.z, $0.w] }
        return CIImage(
            bitmapData: Data(bytes: values, count: values.count * MemoryLayout<Float>.size),
            bytesPerRow: pixels.count * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: pixels.count, height: 1),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func render(_ image: CIImage, width: Int) -> [Float] {
        let context = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var output = [Float](repeating: 0, count: width * 4)
        context.render(
            image,
            toBitmap: &output,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: 1),
            format: .RGBAf,
            colorSpace: linear
        )
        return output
    }

    private func assertOverlay(
        _ pixels: [Float],
        at index: Int,
        color: SIMD3<Float>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let opacity = ChannelClippingOverlay.opacity
        assertPixel(
            pixels,
            at: index,
            equals: SIMD4<Float>(color.x * opacity, color.y * opacity, color.z * opacity, opacity),
            file: file,
            line: line
        )
    }

    private func assertPixel(
        _ pixels: [Float],
        at index: Int,
        equals expected: SIMD4<Float>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let offset = index * 4
        for channel in 0..<4 {
            XCTAssertEqual(pixels[offset + channel], expected[channel], accuracy: 1e-5, file: file, line: line)
        }
    }
}
