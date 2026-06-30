import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class ToneMapperControlsTests: XCTestCase {
    func testChromabaseMetalKernelsCompileAllToneAndScannerKernels() {
        XCTAssertEqual(
            ChromabaseMetalKernels.availableKernelNames,
            [
                "basicTone",
                "calibrationPrimaries",
                "colorGrade",
                "colorMixerHSL",
                "ditherAdd",
                "filmGrain",
                "gamutSoftClip",
                "highlightDesaturate",
                "mainTargetGrade",
                "parametricToneCurve",
                "despeckle",
                "scannerLowSatChroma",
                "scannerMidtoneChroma",
            ]
        )
    }

    func testExposureControlMovesWholeRampInStopDirection() {
        let input = makeLinearRamp()
        let baseline = renderLinearRGBA8(input)
        let darker = renderLinearRGBA8(ToneMapper.applyExposure(to: input, stops: -1))
        let brighter = renderLinearRGBA8(ToneMapper.applyExposure(to: input, stops: 1))

        XCTAssertLessThan(meanLuma(darker, xRange: 48..<80), meanLuma(baseline, xRange: 48..<80) - 25)
        XCTAssertGreaterThan(meanLuma(brighter, xRange: 48..<80), meanLuma(baseline, xRange: 48..<80) + 25)
    }

    func testContrastControlChangesSeparationWithoutReversingTone() {
        let baseline = renderLinearRGBA8(applyTone(DevelopParameters()))
        var low = DevelopParameters()
        low.contrast = -1
        var high = DevelopParameters()
        high.contrast = 1

        let lowContrast = renderLinearRGBA8(applyTone(low))
        let highContrast = renderLinearRGBA8(applyTone(high))

        XCTAssertLessThan(
            tonalSpread(lowContrast),
            tonalSpread(baseline) - 15,
            "Contrast -1은 하이라이트와 암부 간격을 줄여야 합니다."
        )
        XCTAssertGreaterThan(
            tonalSpread(highContrast),
            tonalSpread(baseline) + 15,
            "Contrast +1은 하이라이트와 암부 간격을 넓혀야 합니다."
        )
    }

    func testHighlightShadowWhiteBlackControlsTargetTheirToneRanges() {
        let baseline = renderLinearRGBA8(applyTone(DevelopParameters()))

        // Highlights는 Lightroom 규약을 따른다: +1은 명부를 밝게(올린다), 암부는 거의 불변.
        var brighterHighlights = DevelopParameters()
        brighterHighlights.highlight = 1
        let brightenedHi = renderLinearRGBA8(applyTone(brighterHighlights))
        XCTAssertGreaterThan(meanLuma(brightenedHi, xRange: 104..<124), meanLuma(baseline, xRange: 104..<124) + 8)
        XCTAssertLessThan(abs(meanLuma(brightenedHi, xRange: 8..<28) - meanLuma(baseline, xRange: 8..<28)), 8)

        var openShadows = DevelopParameters()
        openShadows.shadow = 1
        let opened = renderLinearRGBA8(applyTone(openShadows))
        XCTAssertGreaterThan(meanLuma(opened, xRange: 8..<28), meanLuma(baseline, xRange: 8..<28) + 4)
        XCTAssertLessThan(abs(meanLuma(opened, xRange: 104..<124) - meanLuma(baseline, xRange: 104..<124)), 8)

        var brighterWhites = DevelopParameters()
        brighterWhites.whites = 1
        let whiteUp = renderLinearRGBA8(applyTone(brighterWhites))
        XCTAssertGreaterThan(meanLuma(whiteUp, xRange: 104..<124), meanLuma(baseline, xRange: 104..<124) + 8)

        var softerBlacks = DevelopParameters()
        softerBlacks.blacks = 1
        let blackUp = renderLinearRGBA8(applyTone(softerBlacks))
        XCTAssertGreaterThan(meanLuma(blackUp, xRange: 8..<28), meanLuma(baseline, xRange: 8..<28) + 4)
    }

    func testDensityControlChangesPrintWeightWithoutBleachingShadows() {
        let baseline = renderLinearRGBA8(applyTone(DevelopParameters()))
        var lower = DevelopParameters()
        lower.density = -1
        var higher = DevelopParameters()
        higher.density = 1

        let lowDensity = renderLinearRGBA8(applyTone(lower))
        let highDensity = renderLinearRGBA8(applyTone(higher))

        XCTAssertGreaterThan(meanLuma(lowDensity, xRange: 48..<80), meanLuma(baseline, xRange: 48..<80) + 8)
        XCTAssertLessThan(meanLuma(highDensity, xRange: 48..<80), meanLuma(baseline, xRange: 48..<80) - 8)
        XCTAssertLessThan(meanLuma(lowDensity, xRange: 8..<28), 180, "Density -1이 암부를 흰색으로 밀면 안 됩니다.")
    }

    func testToneCurveControlsMoveSeparateLumaBandsAtMinusOneAndPlusOne() {
        let baseline = renderLinearRGBA8(applyTone(DevelopParameters()))
        let masks = lumaBandMasks(baseline)
        let bands: [(String, WritableKeyPath<DevelopParameters, Double>, String, String)] = [
            ("Curve Highlights", \.curveHighlights, "highlights", "shadows"),
            ("Curve Lights", \.curveLights, "lights", "shadows"),
            ("Curve Darks", \.curveDarks, "darks", "highlights"),
            ("Curve Shadows", \.curveShadows, "shadows", "highlights"),
        ]

        for (name, keyPath, targetBand, guardBand) in bands {
            var lower = DevelopParameters()
            lower[keyPath: keyPath] = -1
            var higher = DevelopParameters()
            higher[keyPath: keyPath] = 1

            let lowered = renderLinearRGBA8(applyTone(lower))
            let raised = renderLinearRGBA8(applyTone(higher))
            let targetBase = meanLuma(baseline, indexes: masks[targetBand] ?? [])
            let guardBase = meanLuma(baseline, indexes: masks[guardBand] ?? [])

            XCTAssertLessThan(
                meanLuma(lowered, indexes: masks[targetBand] ?? []),
                targetBase - 12,
                "\(name) -1은 자기 톤 밴드를 확실히 내려야 합니다."
            )
            XCTAssertGreaterThan(
                meanLuma(raised, indexes: masks[targetBand] ?? []),
                targetBase + 12,
                "\(name) +1은 자기 톤 밴드를 확실히 올려야 합니다."
            )
            XCTAssertLessThan(
                abs(meanLuma(lowered, indexes: masks[guardBand] ?? []) - guardBase),
                10,
                "\(name) -1이 반대편 톤 밴드까지 크게 흔들면 안 됩니다."
            )
            XCTAssertLessThan(
                abs(meanLuma(raised, indexes: masks[guardBand] ?? []) - guardBase),
                10,
                "\(name) +1이 반대편 톤 밴드까지 크게 흔들면 안 됩니다."
            )
        }
    }

    func testToneCurveControlsRemainEffectiveOnCompressedScannerToneRange() {
        let input = makeLinearRamp(lower: 0.025, upper: 0.46)
        let baseline = renderLinearRGBA8(ToneMapper.applyToneCurves(to: input, params: DevelopParameters()))
        let bands: [(String, WritableKeyPath<DevelopParameters, Double>, Range<Int>)] = [
            ("Curve Highlights", \.curveHighlights, 104..<124),
            ("Curve Lights", \.curveLights, 76..<96),
            ("Curve Darks", \.curveDarks, 32..<52),
            ("Curve Shadows", \.curveShadows, 8..<28),
        ]

        for (name, keyPath, targetRange) in bands {
            var lower = DevelopParameters()
            lower[keyPath: keyPath] = -1
            var higher = DevelopParameters()
            higher[keyPath: keyPath] = 1

            XCTAssertLessThan(
                meanLuma(renderLinearRGBA8(ToneMapper.applyToneCurves(to: input, params: lower)), xRange: targetRange),
                meanLuma(baseline, xRange: targetRange) - 8,
                "\(name) -1은 압축된 스캐너 톤 범위에서도 보여야 합니다."
            )
            XCTAssertGreaterThan(
                meanLuma(renderLinearRGBA8(ToneMapper.applyToneCurves(to: input, params: higher)), xRange: targetRange),
                meanLuma(baseline, xRange: targetRange) + 8,
                "\(name) +1은 압축된 스캐너 톤 범위에서도 보여야 합니다."
            )
        }
    }

    private func applyTone(_ params: DevelopParameters) -> CIImage {
        ToneMapper.applyToneCurves(to: makeLinearRamp(), params: params)
    }

    private func makeLinearRamp(
        width: Int = 128,
        height: Int = 32,
        lower: Float = 0.035,
        upper: Float = 0.895
    ) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let t = Float(x) / Float(width - 1)
                let value = lower + t * (upper - lower)
                let offset = (y * width + x) * 4
                pixels[offset] = value * 1.04
                pixels[offset + 1] = value
                pixels[offset + 2] = value * 0.94
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

    private func renderLinearRGBA8(
        _ image: CIImage,
        width: Int = 128,
        height: Int = 32
    ) -> [UInt8] {
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

    private func meanLuma(_ rgba: [UInt8], xRange: Range<Int>, width: Int = 128, height: Int = 32) -> Double {
        var sum = 0.0
        var count = 0
        for y in 4..<(height - 4) {
            for x in xRange {
                let i = (y * width + x) * 4
                sum += Double(rgba[i]) * 0.2126
                    + Double(rgba[i + 1]) * 0.7152
                    + Double(rgba[i + 2]) * 0.0722
                count += 1
            }
        }
        return sum / Double(count)
    }

    private func meanLuma(_ rgba: [UInt8], indexes: [Int]) -> Double {
        guard !indexes.isEmpty else { return 0 }
        return indexes.reduce(0.0) { sum, i in
            sum + Double(rgba[i]) * 0.2126
                + Double(rgba[i + 1]) * 0.7152
                + Double(rgba[i + 2]) * 0.0722
        } / Double(indexes.count)
    }

    private func lumaBandMasks(_ rgba: [UInt8], width: Int = 128, height: Int = 32) -> [String: [Int]] {
        var samples: [(offset: Int, luma: Double)] = []
        samples.reserveCapacity(width * height)
        for y in 4..<(height - 4) {
            for x in 0..<width {
                let i = (y * width + x) * 4
                samples.append((i, Double(rgba[i]) * 0.2126 + Double(rgba[i + 1]) * 0.7152 + Double(rgba[i + 2]) * 0.0722))
            }
        }
        samples.sort { $0.luma < $1.luma }
        func slice(_ lower: Double, _ upper: Double) -> [Int] {
            let start = Int(Double(samples.count) * lower)
            let end = max(start + 1, Int(Double(samples.count) * upper))
            return samples[start..<min(end, samples.count)].map(\.offset)
        }
        return [
            "shadows": slice(0.05, 0.20),
            "darks": slice(0.22, 0.40),
            "lights": slice(0.60, 0.78),
            "highlights": slice(0.82, 0.97),
        ]
    }

    private func tonalSpread(_ rgba: [UInt8]) -> Double {
        meanLuma(rgba, xRange: 104..<124) - meanLuma(rgba, xRange: 8..<28)
    }
}
