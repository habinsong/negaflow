import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class ColorModelControlsTests: XCTestCase {
    func testWarmthControlMovesRedBlueAxisAtMinusOneAndPlusOne() {
        let baseline = renderLinearRGBA8(applyColor(DevelopParameters()))

        var cooler = DevelopParameters()
        cooler.warmth = -1
        var warmer = DevelopParameters()
        warmer.warmth = 1

        XCTAssertLessThan(
            redBlueRatio(renderLinearRGBA8(applyColor(cooler))),
            redBlueRatio(baseline) - 0.18,
            "Warmth -1은 red/blue 비율을 낮춰야 합니다."
        )
        XCTAssertGreaterThan(
            redBlueRatio(renderLinearRGBA8(applyColor(warmer))),
            redBlueRatio(baseline) + 0.18,
            "Warmth +1은 red/blue 비율을 높여야 합니다."
        )
    }

    func testTintControlMovesGreenMagentaAxisAtMinusOneAndPlusOne() {
        let baseline = renderLinearRGBA8(applyColor(DevelopParameters()))

        var magenta = DevelopParameters()
        magenta.tint = -1
        var green = DevelopParameters()
        green.tint = 1

        XCTAssertLessThan(
            greenMagentaRatio(renderLinearRGBA8(applyColor(magenta))),
            greenMagentaRatio(baseline) - 0.16,
            "Tint -1은 green/magenta 비율을 낮춰야 합니다."
        )
        XCTAssertGreaterThan(
            greenMagentaRatio(renderLinearRGBA8(applyColor(green))),
            greenMagentaRatio(baseline) + 0.16,
            "Tint +1은 green/magenta 비율을 높여야 합니다."
        )
    }

    func testVibranceSaturationAndColorDepthMoveChromaAtMinusOneAndPlusOne() {
        let baseline = renderLinearRGBA8(applyColor(DevelopParameters()))
        let controls: [(String, WritableKeyPath<DevelopParameters, Double>, Double)] = [
            ("Vibrance", \.vibrance, 0.010),
            ("Saturation", \.saturation, 0.018),
            ("Color Depth", \.colorDepth, 0.010),
        ]

        for (name, keyPath, threshold) in controls {
            var lower = DevelopParameters()
            lower[keyPath: keyPath] = -1
            var higher = DevelopParameters()
            higher[keyPath: keyPath] = 1

            XCTAssertLessThan(
                meanChroma(renderLinearRGBA8(applyColor(lower))),
                meanChroma(baseline) - threshold,
                "\(name) -1은 chroma를 낮춰야 합니다."
            )
            XCTAssertGreaterThan(
                meanChroma(renderLinearRGBA8(applyColor(higher))),
                meanChroma(baseline) + threshold,
                "\(name) +1은 chroma를 높여야 합니다."
            )
        }
    }

    private func applyColor(_ params: DevelopParameters) -> CIImage {
        ColorModel.apply(to: makeColorPatch(), params: params)
    }

    private func makeColorPatch(width: Int = 32, height: Int = 24) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let t = Float(x) / Float(width - 1)
                let v = Float(y) / Float(height - 1)
                let offset = (y * width + x) * 4
                pixels[offset] = 0.20 + t * 0.42
                pixels[offset + 1] = 0.18 + v * 0.34
                pixels[offset + 2] = 0.16 + (1 - t) * 0.22
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

    private func renderLinearRGBA8(_ image: CIImage, width: Int = 32, height: Int = 24) -> [UInt8] {
        let ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
        var rendered = [UInt8](repeating: 0, count: width * height * 4)
        ctx.render(
            image,
            toBitmap: &rendered,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return rendered
    }

    private func redBlueRatio(_ rgba: [UInt8]) -> Double {
        channelMean(rgba, channel: 0) / max(channelMean(rgba, channel: 2), 1)
    }

    private func greenMagentaRatio(_ rgba: [UInt8]) -> Double {
        let magenta = (channelMean(rgba, channel: 0) + channelMean(rgba, channel: 2)) * 0.5
        return channelMean(rgba, channel: 1) / max(magenta, 1)
    }

    private func channelMean(_ rgba: [UInt8], channel: Int) -> Double {
        var sum = 0.0
        var count = 0
        for i in stride(from: channel, to: rgba.count, by: 4) {
            sum += Double(rgba[i])
            count += 1
        }
        return sum / Double(count)
    }

    private func meanChroma(_ rgba: [UInt8]) -> Double {
        var sum = 0.0
        var count = 0
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let r = Double(rgba[i]) / 255.0
            let g = Double(rgba[i + 1]) / 255.0
            let b = Double(rgba[i + 2]) / 255.0
            let y = r * 0.2126 + g * 0.7152 + b * 0.0722
            sum += sqrt(pow(r - y, 2) + pow(g - y, 2) + pow(b - y, 2))
            count += 1
        }
        return sum / Double(count)
    }
}
