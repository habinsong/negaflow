import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class BWToningTests: XCTestCase {
    func testSeleniumAndSepiaTintGeneratedRampWhilePreservingLumaOrder() {
        let ramp = makeRamp(width: 96, height: 16)

        var selenium = BWToning(mode: .selenium)
        selenium.strength = 0.85
        selenium.shadowHue = 285
        selenium.highlightHue = 34
        let seleniumPixels = render(BWToningStage.apply(to: ramp, toning: selenium, filmType: .bwNegative))

        XCTAssertGreaterThan(channelSpread(seleniumPixels, x: 12, y: 8), 0.010)
        XCTAssertGreaterThan(channelSpread(seleniumPixels, x: 84, y: 8), 0.004)
        XCTAssertTrue(luma(seleniumPixels, x: 10, y: 8) < luma(seleniumPixels, x: 48, y: 8))
        XCTAssertTrue(luma(seleniumPixels, x: 48, y: 8) < luma(seleniumPixels, x: 86, y: 8))

        var sepia = BWToning(mode: .sepia)
        sepia.strength = 0.90
        sepia.shadowHue = 32
        sepia.highlightHue = 48
        let sepiaPixels = render(BWToningStage.apply(to: ramp, toning: sepia, filmType: .bwPositive))

        XCTAssertGreaterThan(channelSpread(sepiaPixels, x: 20, y: 8), 0.008)
        XCTAssertGreaterThan(channelSpread(sepiaPixels, x: 84, y: 8), 0.014)
        XCTAssertGreaterThan(sepiaPixels[pixelIndex(x: 84, y: 8) + 0], sepiaPixels[pixelIndex(x: 84, y: 8) + 2] + 0.010)
        XCTAssertTrue(luma(sepiaPixels, x: 10, y: 8) < luma(sepiaPixels, x: 48, y: 8))
        XCTAssertTrue(luma(sepiaPixels, x: 48, y: 8) < luma(sepiaPixels, x: 86, y: 8))
    }

    func testDefaultsDecodeNoopAndClampedStrengthStaySafe() throws {
        let decoded = try JSONDecoder().decode(DevelopParameters.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.bwToning.mode, .none)
        XCTAssertEqual(decoded.bwToning.strength, 0, accuracy: 1e-12)

        let ramp = makeRamp(width: 96, height: 16)
        let baseline = render(ramp)
        let off = render(BWToningStage.apply(to: ramp, toning: .none, filmType: .bwNegative))
        XCTAssertLessThan(maxAbsoluteDifference(baseline, off), 0.0001)

        var zero = BWToning(mode: .sepia)
        zero.strength = 0
        let zeroPixels = render(BWToningStage.apply(to: ramp, toning: zero, filmType: .bwPositive))
        XCTAssertLessThan(maxAbsoluteDifference(baseline, zeroPixels), 0.0001)

        var clamped = BWToning(mode: .selenium)
        clamped.strength = 4
        let clampedPixels = render(BWToningStage.apply(to: ramp, toning: clamped, filmType: .bwNegative))
        XCTAssertFalse(clampedPixels.contains { !$0.isFinite })
        XCTAssertTrue(clampedPixels.allSatisfy { $0 >= -0.001 && $0 <= 1.001 })
    }

    func testColorFilmInputsRemainUnchangedWhenToningIsSet() {
        let color = makeColorPatch(width: 64, height: 16)
        var toning = BWToning(mode: .sepia)
        toning.strength = 1

        let baseline = render(color, width: 64, height: 16)
        let negativeColor = render(BWToningStage.apply(to: color, toning: toning, filmType: .colorNegative), width: 64, height: 16)
        let positiveColor = render(BWToningStage.apply(to: color, toning: toning, filmType: .colorPositive), width: 64, height: 16)

        XCTAssertLessThan(maxAbsoluteDifference(baseline, negativeColor), 0.0001)
        XCTAssertLessThan(maxAbsoluteDifference(baseline, positiveColor), 0.0001)
    }

    private func makeRamp(width: Int, height: Int) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = Float(x) / Float(max(1, width - 1)) * 0.82 + 0.08
                let offset = (y * width + x) * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
                pixels[offset + 3] = 1
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func makeColorPatch(width: Int, height: Int) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let t = Float(x) / Float(max(1, width - 1))
                let offset = (y * width + x) * 4
                pixels[offset] = 0.20 + t * 0.50
                pixels[offset + 1] = 0.34 + t * 0.20
                pixels[offset + 2] = 0.56 - t * 0.24
                pixels[offset + 3] = 1
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func render(_ image: CIImage, width: Int = 96, height: Int = 16) -> [Float] {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var out = [Float](repeating: 0, count: width * height * 4)
        CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear]).render(
            image,
            toBitmap: &out,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        return out
    }

    private func pixelIndex(x: Int, y: Int, width: Int = 96) -> Int {
        (y * width + x) * 4
    }

    private func luma(_ pixels: [Float], x: Int, y: Int, width: Int = 96) -> Double {
        let offset = pixelIndex(x: x, y: y, width: width)
        return Double(pixels[offset]) * 0.2126 + Double(pixels[offset + 1]) * 0.7152 + Double(pixels[offset + 2]) * 0.0722
    }

    private func channelSpread(_ pixels: [Float], x: Int, y: Int, width: Int = 96) -> Double {
        let offset = pixelIndex(x: x, y: y, width: width)
        let r = Double(pixels[offset])
        let g = Double(pixels[offset + 1])
        let b = Double(pixels[offset + 2])
        return max(r, g, b) - min(r, g, b)
    }

    private func maxAbsoluteDifference(_ a: [Float], _ b: [Float]) -> Double {
        zip(a, b).map { abs(Double($0 - $1)) }.max() ?? 0
    }
}
