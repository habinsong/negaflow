import XCTest
import CoreGraphics
@testable import Chromabase

final class PixelSamplerTests: XCTestCase {
    func testKnownPatchesReportCorrectCursorRGBAndLab() throws {
        let image = try makeImage(
            width: 2,
            height: 2,
            pixels: [
                255, 0, 0, 255,      0, 255, 0, 255,
                0, 0, 255, 255,      255, 255, 255, 255,
            ]
        )

        XCTAssertEqual(
            PixelSampler.sourceCoordinate(at: CGPoint(x: 0.25, y: 0.25), width: 2, height: 2),
            PixelCoordinate(x: 0, y: 0)
        )
        let red = try XCTUnwrap(PixelSampler.sample(image, at: CGPoint(x: 0.25, y: 0.25)))
        XCTAssertEqual(red.rgb.x, 1, accuracy: 0.002)
        XCTAssertEqual(red.rgb.y, 0, accuracy: 0.002)
        XCTAssertEqual(red.rgb.z, 0, accuracy: 0.002)
        XCTAssertEqual(red.lab.x, 54.3, accuracy: 0.7)
        XCTAssertEqual(red.lab.y, 81.1, accuracy: 0.9)
        XCTAssertEqual(red.lab.z, 70.2, accuracy: 0.9)

        let white = try XCTUnwrap(PixelSampler.sample(image, at: CGPoint(x: 0.75, y: 0.75)))
        XCTAssertEqual(white.rgb.x, 1, accuracy: 0.002)
        XCTAssertEqual(white.rgb.y, 1, accuracy: 0.002)
        XCTAssertEqual(white.rgb.z, 1, accuracy: 0.002)
        XCTAssertEqual(white.lab.x, 100, accuracy: 0.8)
    }

    func testWorkingLinearRGBIsDistinctFromEncodedSRGB() throws {
        let image = try makeImage(width: 1, height: 1, pixels: [128, 128, 128, 255])
        let encoded = try XCTUnwrap(PixelSampler.sample(
            image,
            at: CGPoint(x: 0.5, y: 0.5),
            rgbColorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        ))
        let working = try XCTUnwrap(PixelSampler.sample(
            image,
            at: CGPoint(x: 0.5, y: 0.5),
            rgbColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)
        ))

        XCTAssertEqual(encoded.rgb.x, Double(128) / Double(255), accuracy: 0.004)
        XCTAssertEqual(working.rgb.x, 0.216, accuracy: 0.01)
        XCTAssertEqual(encoded.lab.x, working.lab.x, accuracy: 0.8)
        XCTAssertNotEqual(encoded.colorSpaceName, working.colorSpaceName)
    }

    func testCoordinatesClampAtImageEdges() {
        XCTAssertEqual(
            PixelSampler.sourceCoordinate(at: CGPoint(x: -1, y: 2), width: 40, height: 20),
            PixelCoordinate(x: 0, y: 19)
        )
        XCTAssertEqual(
            PixelSampler.sourceCoordinate(at: CGPoint(x: 1, y: 1), width: 40, height: 20),
            PixelCoordinate(x: 39, y: 19)
        )
    }

    private func makeImage(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
        var pixels = pixels
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }
}
