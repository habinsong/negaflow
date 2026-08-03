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
                "boundedRelativeGrade",
                "bwToning",
                "calibrationPrimaries",
                "channelClippingOverlay",
                "colorGrade",
                "colorMixerHSL",
                // 디지털 소스 전용 필름 경로. 필름 스캔은 이 커널들을 호출하지 않는다.
                "digitalFilmColor",
                "digitalFilmDensity",
                "digitalFilmGrainDensity",
                "digitalHalation",
                "digitalInterImage",
                "digitalPrintPaper",
                "digitalReversalTransmit",
                "digitalSceneReconstruct",
                "digitalToDisplayGamma",
                "digitalToLinearLight",
                "ditherAdd",
                "filmGrain",
                "gamutSoftClip",
                "gfApply",
                "gfCoeffA",
                "gfCoeffB",
                "gfProduct",
                "highlightDesaturate",
                "negativeInvert",
                "noritsuTexture",
                "parametricToneCurve",
                "filmScanShrink",
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

    func testExposureStopsUseExactLinearPowerOfTwoScaling() {
        let input = makeSolidLinear(value: 0.125)
        for stops in [-2.0, -1.0, 0.0, 1.0, 2.0] {
            let output = renderLinearRGBAf(
                ToneMapper.applyExposure(to: input, stops: stops),
                width: 4,
                height: 4
            )
            XCTAssertEqual(
                Double(output[0]),
                0.125 * pow(2.0, stops),
                accuracy: 0.0005,
                "\(stops) EV가 실제 2^EV 선형 배율과 일치해야 합니다."
            )
        }
    }

    func testMaxExposureAfterAutoToneDoesNotSolarizeHighlights() {
        let input = makeLinearRamp()
        var params = DevelopParameters()
        params.exposure = 2
        params.contrast = 0.42
        params.highlight = -0.04
        params.shadow = 0.02
        params.whites = 0.09
        params.blacks = -0.32

        let exposed = ToneMapper.applyExposure(to: input, stops: params.exposure)
        let output = renderLinearRGBA8(ToneMapper.applyToneCurves(to: exposed, params: params))
        let bandLuma = stride(from: 0, to: 128, by: 8).map {
            meanLuma(output, xRange: $0..<min($0 + 8, 128))
        }

        for (previous, current) in zip(bandLuma, bandLuma.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                current,
                previous - 2,
                "노출 +2와 자동 톤을 함께 써도 밝은 입력이 다시 어두워지는 솔라리제이션이 없어야 합니다."
            )
        }
        XCTAssertGreaterThanOrEqual(
            bandLuma.last ?? 0,
            bandLuma[bandLuma.count / 2] - 2,
            "최고 명부가 중간톤보다 어두워지면 안 됩니다."
        )
    }

    func testMaxExposureWithoutOtherToneControlsKeepsHighlightsInDisplayRange() {
        let input = makeLinearRamp()
        var params = DevelopParameters()
        params.exposure = 2

        let exposed = ToneMapper.applyExposure(to: input, stops: params.exposure)
        let output = renderLinearRGBA8(ToneMapper.applyToneCurves(to: exposed, params: params))
        let midtone = meanLuma(output, xRange: 48..<64)
        let highlight = meanLuma(output, xRange: 112..<128)

        XCTAssertGreaterThanOrEqual(highlight, midtone - 2)
        XCTAssertGreaterThan(highlight, 245, "노출 +2의 최고 명부는 정상적으로 밝아져야 합니다.")
    }

    // photometric 재캘리브레이션(2026-07-18) 기준 대역 — 지각 램프에서 x/127 ≈ sRGB:
    //   블랙 x1..15(0.03~0.13) · 섀도 x11..37(0.10~0.30) · 미드 x48..72(0.38~0.56)
    //   · 명부 x86..112(0.66~0.86) · 화이트 x117..126(0.90~0.96). 미드(0.46) 침범 금지가 핵심.
    func testContrastControlChangesSeparationWithoutReversingTone() {
        let baseline = renderLinearRGBA8(applyPerceptualTone(DevelopParameters()))
        var low = DevelopParameters()
        low.contrast = -1
        var high = DevelopParameters()
        high.contrast = 1

        let lowContrast = renderLinearRGBA8(applyPerceptualTone(low))
        let highContrast = renderLinearRGBA8(applyPerceptualTone(high))

        func spread(_ px: [UInt8]) -> Double {
            meanLuma(px, xRange: 86..<112) - meanLuma(px, xRange: 11..<37)
        }
        XCTAssertLessThan(
            spread(lowContrast),
            spread(baseline) - 15,
            "Contrast -1은 하이라이트와 암부 간격을 줄여야 합니다."
        )
        XCTAssertGreaterThan(
            spread(highContrast),
            spread(baseline) + 15,
            "Contrast +1은 하이라이트와 암부 간격을 넓혀야 합니다."
        )
        // 피벗 = photometric 미드(sRGB 0.46): 미드 대역은 대비 ±1 에도 거의 고정.
        for adjusted in [lowContrast, highContrast] {
            XCTAssertLessThan(
                abs(meanLuma(adjusted, xRange: 56..<64) - meanLuma(baseline, xRange: 56..<64)), 10,
                "Contrast 는 photometric 미드를 피벗으로 삼아야 한다(미드 대이동 금지)")
        }
    }

    func testHighlightShadowWhiteBlackControlsTargetTheirToneRanges() {
        let baseline = renderLinearRGBA8(applyPerceptualTone(DevelopParameters()))

        // Highlights는 Lightroom 규약을 따른다: +1은 명부를 밝게(올린다), 암부는 거의 불변.
        var brighterHighlights = DevelopParameters()
        brighterHighlights.highlight = 1
        let brightenedHi = renderLinearRGBA8(applyPerceptualTone(brighterHighlights))
        XCTAssertGreaterThan(meanLuma(brightenedHi, xRange: 86..<112), meanLuma(baseline, xRange: 86..<112) + 8)
        XCTAssertLessThan(abs(meanLuma(brightenedHi, xRange: 11..<37) - meanLuma(baseline, xRange: 11..<37)), 8)

        var openShadows = DevelopParameters()
        openShadows.shadow = 1
        let opened = renderLinearRGBA8(applyPerceptualTone(openShadows))
        XCTAssertGreaterThan(meanLuma(opened, xRange: 11..<37), meanLuma(baseline, xRange: 11..<37) + 4)
        XCTAssertLessThan(abs(meanLuma(opened, xRange: 86..<112) - meanLuma(baseline, xRange: 86..<112)), 8)
        // photometric 미드(sRGB 0.46) 침범 금지 — 과거 마스크는 미드에서 1.0 이었다.
        XCTAssertLessThan(abs(meanLuma(opened, xRange: 56..<64) - meanLuma(baseline, xRange: 56..<64)), 6,
            "Shadows 가 photometric 미드를 통째로 움직이면 안 된다")

        var brighterWhites = DevelopParameters()
        brighterWhites.whites = 1
        let whiteUp = renderLinearRGBA8(applyPerceptualTone(brighterWhites))
        XCTAssertGreaterThan(meanLuma(whiteUp, xRange: 117..<126), meanLuma(baseline, xRange: 117..<126) + 8)

        var softerBlacks = DevelopParameters()
        softerBlacks.blacks = 1
        let blackUp = renderLinearRGBA8(applyPerceptualTone(softerBlacks))
        XCTAssertGreaterThan(meanLuma(blackUp, xRange: 1..<15), meanLuma(baseline, xRange: 1..<15) + 4)
        XCTAssertLessThan(abs(meanLuma(blackUp, xRange: 56..<64) - meanLuma(baseline, xRange: 56..<64)), 6,
            "Blacks 가 photometric 미드를 침범하면 안 된다")
    }

    func testDensityControlChangesPrintWeightWithoutBleachingShadows() {
        let baseline = renderLinearRGBA8(applyPerceptualTone(DevelopParameters()))
        var lower = DevelopParameters()
        lower.density = -1
        var higher = DevelopParameters()
        higher.density = 1

        let lowDensity = renderLinearRGBA8(applyPerceptualTone(lower))
        let highDensity = renderLinearRGBA8(applyPerceptualTone(higher))

        XCTAssertGreaterThan(meanLuma(lowDensity, xRange: 48..<72), meanLuma(baseline, xRange: 48..<72) + 8)
        XCTAssertLessThan(meanLuma(highDensity, xRange: 48..<72), meanLuma(baseline, xRange: 48..<72) - 8)
        XCTAssertLessThan(meanLuma(lowDensity, xRange: 11..<37), 150, "Density -1이 암부를 흰색으로 밀면 안 됩니다.")
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

    /// photometric 재캘리브레이션(2026-07-18) 검증용 지각 균등 램프 — x/127 ≈ 출력 sRGB.
    /// linear 균등 램프는 sRGB 저역(블랙/섀도 대역)이 몇 픽셀로 압축돼 대역 측정이 불가능하다.
    private func makePerceptualRamp(width: Int = 128, height: Int = 32) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        func srgbDecode(_ v: Float) -> Float {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        for y in 0..<height {
            for x in 0..<width {
                let t = Float(x) / Float(width - 1)
                let value = srgbDecode(0.02 + t * 0.95)
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

    private func applyPerceptualTone(_ params: DevelopParameters) -> CIImage {
        ToneMapper.applyToneCurves(to: makePerceptualRamp(), params: params)
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

    private func makeSolidLinear(value: Float, width: Int = 4, height: Int = 4) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = value
            pixels[offset + 1] = value
            pixels[offset + 2] = value
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

    private func renderLinearRGBAf(_ image: CIImage, width: Int, height: Int) -> [Float] {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let context = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var rendered = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &rendered,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
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
