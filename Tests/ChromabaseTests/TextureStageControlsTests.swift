import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class TextureStageControlsTests: XCTestCase {
    func testGrainIncreasesLocalNoiseWithoutLargeMeanShift() {
        let input = makeTexturePatch()
        var params = DevelopParameters()
        params.grain = 1

        let baseline = renderLinearRGBAf(TextureStage.apply(to: input, params: DevelopParameters()))
        let adjusted = renderLinearRGBAf(TextureStage.apply(to: input, params: params))

        XCTAssertGreaterThan(localNoise(adjusted), localNoise(baseline) + 0.006)
        XCTAssertLessThan(abs(meanLuma(adjusted) - meanLuma(baseline)), 0.025)
    }

    func testSharpnessAndPositiveClarityIncreaseEdgeContrast() {
        let input = makeTexturePatch()
        let baseline = renderLinearRGBAf(TextureStage.apply(to: input, params: DevelopParameters()))

        var sharp = DevelopParameters()
        sharp.sharpness = 1
        XCTAssertGreaterThan(
            meanEdge(renderLinearRGBAf(TextureStage.apply(to: input, params: sharp))),
            meanEdge(baseline) + 0.020
        )

        var clarity = DevelopParameters()
        clarity.clarity = 1
        XCTAssertGreaterThan(
            meanEdge(renderLinearRGBAf(TextureStage.apply(to: input, params: clarity))),
            meanEdge(baseline) + 0.010
        )
    }

    func testNegativeClaritySoftensContrast() {
        let input = makeTexturePatch()
        let baseline = renderLinearRGBAf(TextureStage.apply(to: input, params: DevelopParameters()))

        var params = DevelopParameters()
        params.clarity = -1
        let adjusted = renderLinearRGBAf(TextureStage.apply(to: input, params: params))

        XCTAssertLessThan(meanEdge(adjusted), meanEdge(baseline) - 0.010)
        XCTAssertLessThan(meanChroma(adjusted), meanChroma(baseline) + 0.001)
    }

    func testHalationWarmsBrightDetailWithoutLiftingDarkFrame() {
        let brightInput = makeHalationPatch()
        var params = DevelopParameters()
        params.halation = 1

        let baseline = renderLinearRGBAf(TextureStage.apply(to: brightInput, params: DevelopParameters()))
        let adjusted = renderLinearRGBAf(TextureStage.apply(to: brightInput, params: params))
        XCTAssertGreaterThan(meanChroma(adjusted), meanChroma(baseline) + 0.002)
        XCTAssertGreaterThan(meanLuma(adjusted), meanLuma(baseline) + 0.001)

        let dark = CIImage(color: CIColor(red: 0.02, green: 0.02, blue: 0.02))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let darkRendered = renderLinearRGBAf(TextureStage.apply(to: dark, params: params), width: 16, height: 16)
        XCTAssertLessThan(meanLuma(darkRendered), 0.04)
    }

    func testVignetteDarkensOrLiftsEdgesWithoutChangingCenterMuch() {
        let input = makeTexturePatch()
        let baseline = renderLinearRGBAf(TextureStage.apply(to: input, params: DevelopParameters()))

        var darken = DevelopParameters()
        darken.vignette = 1
        let darkened = renderLinearRGBAf(TextureStage.apply(to: input, params: darken))
        XCTAssertLessThan(cornerMean(darkened), cornerMean(baseline) - 0.015)
        XCTAssertLessThan(abs(centerMean(darkened) - centerMean(baseline)), 0.010)

        var lift = DevelopParameters()
        lift.vignette = -1
        let lifted = renderLinearRGBAf(TextureStage.apply(to: input, params: lift))
        XCTAssertGreaterThan(cornerMean(lifted), cornerMean(baseline) + 0.025)
        XCTAssertLessThan(abs(centerMean(lifted) - centerMean(baseline)), 0.010)
    }

    private func makeTexturePatch(width: Int = 64, height: Int = 48) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let stripe: Float = (x / 4).isMultiple(of: 2) ? 0.10 : -0.08
                let gradient = Float(x) / Float(width - 1) * 0.22 + Float(y) / Float(height - 1) * 0.18
                let value = max(0.05, min(0.92, 0.32 + gradient + stripe))
                let offset = (y * width + x) * 4
                pixels[offset] = value + 0.04
                pixels[offset + 1] = value
                pixels[offset + 2] = value - 0.03
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

    private func makeHalationPatch(width: Int = 64, height: Int = 48) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x - width / 2)
                let dy = Float(y - height / 2)
                let distance = sqrt(dx * dx + dy * dy)
                let value: Float = distance < 10 ? 0.82 : 0.30
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

    private func renderLinearRGBAf(_ image: CIImage, width: Int = 64, height: Int = 48) -> [Float] {
        let ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        ])
        var rendered = [Float](repeating: 0, count: width * height * 4)
        ctx.render(
            image,
            toBitmap: &rendered,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        return rendered
    }

    private func meanLuma(_ rgba: [Float]) -> Double {
        var sum = 0.0
        var count = 0
        for i in stride(from: 0, to: rgba.count, by: 4) {
            sum += luma(rgba, offset: i)
            count += 1
        }
        return sum / Double(count)
    }

    private func localNoise(_ rgba: [Float], width: Int = 64, height: Int = 48) -> Double {
        var sum = 0.0
        var count = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = luma(rgba, x: x, y: y, width: width)
                let around = (
                    luma(rgba, x: x - 1, y: y, width: width) +
                    luma(rgba, x: x + 1, y: y, width: width) +
                    luma(rgba, x: x, y: y - 1, width: width) +
                    luma(rgba, x: x, y: y + 1, width: width)
                ) * 0.25
                sum += abs(center - around)
                count += 1
            }
        }
        return sum / Double(count)
    }

    private func meanEdge(_ rgba: [Float], width: Int = 64, height: Int = 48) -> Double {
        var sum = 0.0
        var count = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let dx = luma(rgba, x: x + 1, y: y, width: width) - luma(rgba, x: x - 1, y: y, width: width)
                let dy = luma(rgba, x: x, y: y + 1, width: width) - luma(rgba, x: x, y: y - 1, width: width)
                sum += sqrt(dx * dx + dy * dy)
                count += 1
            }
        }
        return sum / Double(count)
    }

    private func meanChroma(_ rgba: [Float]) -> Double {
        var sum = 0.0
        var count = 0
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let y = luma(rgba, offset: i)
            sum += sqrt(pow(Double(rgba[i]) - y, 2) + pow(Double(rgba[i + 1]) - y, 2) + pow(Double(rgba[i + 2]) - y, 2))
            count += 1
        }
        return sum / Double(count)
    }

    private func cornerMean(_ rgba: [Float], width: Int = 64) -> Double {
        sampleMean(rgba, width: width, xRange: 0..<12, yRange: 0..<12)
    }

    private func centerMean(_ rgba: [Float], width: Int = 64) -> Double {
        sampleMean(rgba, width: width, xRange: 26..<38, yRange: 18..<30)
    }

    private func sampleMean(_ rgba: [Float], width: Int, xRange: Range<Int>, yRange: Range<Int>) -> Double {
        var sum = 0.0
        var count = 0
        for y in yRange {
            for x in xRange {
                sum += luma(rgba, x: x, y: y, width: width)
                count += 1
            }
        }
        return sum / Double(count)
    }

    private func luma(_ rgba: [Float], x: Int, y: Int, width: Int) -> Double {
        luma(rgba, offset: (y * width + x) * 4)
    }

    private func luma(_ rgba: [Float], offset: Int) -> Double {
        Double(rgba[offset]) * 0.2126 + Double(rgba[offset + 1]) * 0.7152 + Double(rgba[offset + 2]) * 0.0722
    }
}
