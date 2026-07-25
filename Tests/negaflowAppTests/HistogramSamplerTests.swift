import AppKit
import CoreGraphics
import XCTest
@testable import negaflowApp

final class HistogramSamplerTests: XCTestCase {
    private struct Pixel {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    private struct SampleCase {
        let name: String
        let pixel: Pixel
        let expectedBins: (red: Int, green: Int, blue: Int)?
        let expectedClippedChannels: [HistogramChannel]
    }

    func testGraphBinsAndExactClippingUseSeparateValues() throws {
        let cases = [
            SampleCase(
                name: "near black",
                pixel: Pixel(red: 1, green: 2, blue: 3, alpha: 255),
                expectedBins: (red: 0, green: 0, blue: 0),
                expectedClippedChannels: []
            ),
            SampleCase(
                name: "near white",
                pixel: Pixel(red: 252, green: 253, blue: 254, alpha: 255),
                expectedBins: (red: 63, green: 63, blue: 63),
                expectedClippedChannels: []
            ),
            SampleCase(
                name: "opaque extrema",
                pixel: Pixel(red: 0, green: 128, blue: 255, alpha: 255),
                expectedBins: (red: 0, green: 32, blue: 63),
                expectedClippedChannels: [.red, .blue]
            ),
            SampleCase(
                name: "half alpha extrema",
                pixel: Pixel(red: 128, green: 64, blue: 0, alpha: 128),
                expectedBins: (red: 63, green: 32, blue: 0),
                expectedClippedChannels: [.red, .blue]
            ),
            SampleCase(
                name: "half alpha near white",
                pixel: Pixel(red: 127, green: 127, blue: 127, alpha: 128),
                expectedBins: (red: 63, green: 63, blue: 63),
                expectedClippedChannels: []
            ),
            SampleCase(
                name: "transparent",
                pixel: Pixel(red: 0, green: 0, blue: 0, alpha: 0),
                expectedBins: nil,
                expectedClippedChannels: []
            ),
        ]

        for sample in cases {
            let image = try makeImage(pixels: Array(repeating: sample.pixel, count: 256))
            let bins = try XCTUnwrap(HistogramSampler.compute(image), sample.name)
            let expectedTotal = sample.expectedBins == nil ? 0 : 256

            XCTAssertEqual(bins.totalPixels, expectedTotal, sample.name)
            XCTAssertEqual(bins.clippedChannels, sample.expectedClippedChannels, sample.name)
            XCTAssertEqual(bins.r.reduce(0, +), expectedTotal, sample.name)
            XCTAssertEqual(bins.g.reduce(0, +), expectedTotal, sample.name)
            XCTAssertEqual(bins.b.reduce(0, +), expectedTotal, sample.name)
            XCTAssertEqual(bins.luma.reduce(0, +), expectedTotal, sample.name)

            if let expectedBins = sample.expectedBins {
                XCTAssertEqual(bins.r[expectedBins.red], 256, sample.name)
                XCTAssertEqual(bins.g[expectedBins.green], 256, sample.name)
                XCTAssertEqual(bins.b[expectedBins.blue], 256, sample.name)
            }
        }
    }

    func testTransparentPixelsDoNotAffectTotalOrClippingThreshold() throws {
        let transparent = Pixel(red: 0, green: 0, blue: 0, alpha: 0)
        let black = Pixel(red: 0, green: 0, blue: 0, alpha: 255)
        let pixels = Array(repeating: transparent, count: 254) + Array(repeating: black, count: 2)

        let bins = try XCTUnwrap(HistogramSampler.compute(try makeImage(pixels: pixels)))

        XCTAssertEqual(bins.totalPixels, 2)
        XCTAssertEqual(bins.r.reduce(0, +), 2)
        XCTAssertEqual(bins.g.reduce(0, +), 2)
        XCTAssertEqual(bins.b.reduce(0, +), 2)
        XCTAssertEqual(bins.luma.reduce(0, +), 2)
        XCTAssertEqual(bins.clippedChannels, [.red, .green, .blue])
    }

    private func makeImage(pixels: [Pixel]) throws -> NSImage {
        let width = 256
        XCTAssertEqual(pixels.count, width)
        let data = Data(pixels.flatMap { [$0.red, $0.green, $0.blue, $0.alpha] })
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.byteOrder32Big)
        let cgImage = try XCTUnwrap(CGImage(
            width: width,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: 1))
    }
}
