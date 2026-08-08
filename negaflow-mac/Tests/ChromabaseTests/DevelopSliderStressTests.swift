import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

final class DevelopSliderStressTests: XCTestCase {
    private let width = 64
    private let height = 16
    private let targets: [DevelopTarget] = [.main, .noritsu, .sp3000, .f135, .hr, .rescue]

    func testAutoToneAndMaxExposureStayMonotonicForEveryFilmTypeAndTarget() throws {
        let engine = ChromabaseEngine()

        for fixture in filmFixtures() {
            for target in targets {
                var params = DevelopParameters()
                params.filmType = fixture.filmType
                params.developTarget = target
                let neutral = engine.develop(image: fixture.image, base: fixture.base, params: params)
                let neutralCG = try XCTUnwrap(makeSRGBCGImage(neutral))
                let stats = try XCTUnwrap(AutoAdjust.imageStats(neutralCG))
                let automatic = AutoAdjust.autoTone(stats)

                params.exposure = 2
                params.contrast = automatic.contrast
                params.highlight = automatic.highlight
                params.shadow = automatic.shadow
                params.whites = automatic.whites
                params.blacks = automatic.blacks
                params.vibrance = automatic.vibrance
                params.saturation = automatic.saturation

                let output = renderLinearRGBAf(
                    engine.develop(image: fixture.image, base: fixture.base, params: params)
                )
                let samples = stride(from: 6, through: width - 7, by: 6).map {
                    meanLuma(output, x: $0)
                }
                let label = "\(fixture.filmType.displayName) / \(target.displayName)"

                XCTAssertTrue(output.allSatisfy(\.isFinite), "\(label) 출력에 NaN/Inf가 있습니다.")
                for (previous, current) in zip(samples, samples.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(
                        current,
                        previous - 0.10,
                        "\(label)에서 밝은 입력이 다시 어두워지는 솔라리제이션이 발생했습니다."
                    )
                }
                XCTAssertGreaterThanOrEqual(
                    samples.last ?? 0,
                    samples[samples.count / 2] - 0.05,
                    "\(label) 최고 명부가 중간톤보다 어두워졌습니다."
                )
            }
        }
    }

    func testEveryInspectorSliderExtremeKeepsPipelineFinite() {
        let engine = ChromabaseEngine()
        let fixtures = filmFixtures().filter {
            $0.filmType == .colorNegative || $0.filmType == .bwPositive
        }

        for slider in inspectorSliderExtremes() {
            for fixture in fixtures {
                var params = DevelopParameters()
                params.filmType = fixture.filmType
                slider.mutate(&params)

                let output = renderLinearRGBAf(
                    engine.develop(image: fixture.image, base: fixture.base, params: params)
                )
                let label = "\(slider.name) / \(fixture.filmType.displayName)"
                XCTAssertTrue(output.allSatisfy(\.isFinite), "\(label) 출력에 NaN/Inf가 있습니다.")
                XCTAssertTrue(
                    output.allSatisfy { abs($0) < 8 },
                    "\(label) 출력값이 비정상적으로 발산했습니다."
                )
            }
        }
    }

    private typealias SliderExtreme = (name: String, mutate: (inout DevelopParameters) -> Void)

    private func inspectorSliderExtremes() -> [SliderExtreme] {
        var cases: [SliderExtreme] = [
            ("Exposure -2", { $0.exposure = -2 }),
            ("Exposure +2", { $0.exposure = 2 }),
            ("Contrast -1", { $0.contrast = -1 }),
            ("Contrast +1", { $0.contrast = 1 }),
            ("Highlights -1", { $0.highlight = -1 }),
            ("Highlights +1", { $0.highlight = 1 }),
            ("Shadows -1", { $0.shadow = -1 }),
            ("Shadows +1", { $0.shadow = 1 }),
            ("Whites -1", { $0.whites = -1 }),
            ("Whites +1", { $0.whites = 1 }),
            ("Blacks -1", { $0.blacks = -1 }),
            ("Blacks +1", { $0.blacks = 1 }),
            ("Density -1", { $0.density = -1 }),
            ("Density +1", { $0.density = 1 }),
            ("Curve Highlights -1", { $0.curveHighlights = -1 }),
            ("Curve Highlights +1", { $0.curveHighlights = 1 }),
            ("Curve Lights -1", { $0.curveLights = -1 }),
            ("Curve Lights +1", { $0.curveLights = 1 }),
            ("Curve Darks -1", { $0.curveDarks = -1 }),
            ("Curve Darks +1", { $0.curveDarks = 1 }),
            ("Curve Shadows -1", { $0.curveShadows = -1 }),
            ("Curve Shadows +1", { $0.curveShadows = 1 }),
            ("Warmth -1", { $0.warmth = -1 }),
            ("Warmth +1", { $0.warmth = 1 }),
            ("Tint -1", { $0.tint = -1 }),
            ("Tint +1", { $0.tint = 1 }),
            ("Vibrance -1", { $0.vibrance = -1 }),
            ("Vibrance +1", { $0.vibrance = 1 }),
            ("Saturation -1", { $0.saturation = -1 }),
            ("Saturation +1", { $0.saturation = 1 }),
            ("Color Depth -1", { $0.colorDepth = -1 }),
            ("Color Depth +1", { $0.colorDepth = 1 }),
            ("Manual Base Red 0", { $0.baseEstimationMode = .manual; $0.manualBaseRGB = SIMD3(0, 0.65, 0.45) }),
            ("Manual Base Red 1", { $0.baseEstimationMode = .manual; $0.manualBaseRGB = SIMD3(1, 0.65, 0.45) }),
            ("Manual Base Green 0", { $0.baseEstimationMode = .manual; $0.manualBaseRGB = SIMD3(0.90, 0, 0.45) }),
            ("Manual Base Green 1", { $0.baseEstimationMode = .manual; $0.manualBaseRGB = SIMD3(0.90, 1, 0.45) }),
            ("Manual Base Blue 0", { $0.baseEstimationMode = .manual; $0.manualBaseRGB = SIMD3(0.90, 0.65, 0) }),
            ("Manual Base Blue 1", { $0.baseEstimationMode = .manual; $0.manualBaseRGB = SIMD3(0.90, 0.65, 1) }),
            ("Mixer Hue -1", { $0.colorMixer.hue = Array(repeating: -1, count: 8) }),
            ("Mixer Hue +1", { $0.colorMixer.hue = Array(repeating: 1, count: 8) }),
            ("Mixer Saturation -1", { $0.colorMixer.saturation = Array(repeating: -1, count: 8) }),
            ("Mixer Saturation +1", { $0.colorMixer.saturation = Array(repeating: 1, count: 8) }),
            ("Mixer Luminance -1", { $0.colorMixer.luminance = Array(repeating: -1, count: 8) }),
            ("Mixer Luminance +1", { $0.colorMixer.luminance = Array(repeating: 1, count: 8) }),
            ("Calibration -1", {
                $0.calibration.redHue = -1; $0.calibration.redSat = -1
                $0.calibration.greenHue = -1; $0.calibration.greenSat = -1
                $0.calibration.blueHue = -1; $0.calibration.blueSat = -1
            }),
            ("Calibration +1", {
                $0.calibration.redHue = 1; $0.calibration.redSat = 1
                $0.calibration.greenHue = 1; $0.calibration.greenSat = 1
                $0.calibration.blueHue = 1; $0.calibration.blueSat = 1
            }),
            ("Noise Reduction +1", { $0.noiseReduction = 1 }),
            ("Noise Reduction Luma 0", { $0.noiseReduction = 1; $0.noiseReductionLuma = 0 }),
            ("Noise Reduction Luma 1", { $0.noiseReduction = 1; $0.noiseReductionLuma = 1 }),
            ("Noise Reduction Chroma 0", { $0.noiseReduction = 1; $0.noiseReductionChroma = 0 }),
            ("Noise Reduction Chroma 1", { $0.noiseReduction = 1; $0.noiseReductionChroma = 1 }),
            ("Noise Reduction Dark Tone 0", { $0.noiseReduction = 1; $0.noiseReductionDarkTone = 0 }),
            ("Noise Reduction Dark Tone 1", { $0.noiseReduction = 1; $0.noiseReductionDarkTone = 1 }),
            ("Noise Reduction Detail 0", { $0.noiseReduction = 1; $0.noiseReductionDetail = 0 }),
            ("Noise Reduction Detail 1", { $0.noiseReduction = 1; $0.noiseReductionDetail = 1 }),
            ("Noise Reduction Grain Protect 0", { $0.noiseReduction = 1; $0.noiseReductionGrainProtect = 0 }),
            ("Noise Reduction Grain Protect 1", { $0.noiseReduction = 1; $0.noiseReductionGrainProtect = 1 }),
            ("Grain +1", { $0.grain = 1 }),
            ("Sharpness +1", { $0.sharpness = 1 }),
            ("Clarity -1", { $0.clarity = -1 }),
            ("Clarity +1", { $0.clarity = 1 }),
            ("Halation +1", { $0.halation = 1 }),
            ("Vignette -1", { $0.vignette = -1 }),
            ("Vignette +1", { $0.vignette = 1 }),
            ("Defect Removal +1", { $0.defectRemoval = 1 }),
        ]

        for region in [\ColorGrading.shadows, \ColorGrading.midtones, \ColorGrading.highlights] {
            cases.append(("Color Grading Region", {
                $0.colorGrading[keyPath: region].hue = 315
                $0.colorGrading[keyPath: region].saturation = 1
                $0.colorGrading[keyPath: region].luminance = 1
            }))
        }
        cases.append(("Color Grading Blending 0", {
            $0.colorGrading.shadows.saturation = 1; $0.colorGrading.blending = 0
        }))
        cases.append(("Color Grading Blending 1", {
            $0.colorGrading.shadows.saturation = 1; $0.colorGrading.blending = 1
        }))
        cases.append(("Color Grading Balance -1", {
            $0.colorGrading.highlights.saturation = 1; $0.colorGrading.balance = -1
        }))
        cases.append(("Color Grading Balance +1", {
            $0.colorGrading.highlights.saturation = 1; $0.colorGrading.balance = 1
        }))
        cases.append(("B&W Toning Strength +1", {
            $0.bwToning = BWToning(mode: .selenium, shadowHue: 0, highlightHue: 360, strength: 1)
        }))
        return cases
    }

    private struct FilmFixture {
        let filmType: FilmType
        let image: CIImage
        let base: FilmBase?
    }

    private func filmFixtures() -> [FilmFixture] {
        let colorBase = SIMD3<Double>(0.82, 0.55, 0.34)
        let bwBase = SIMD3<Double>(repeating: 0.80)
        return [
            FilmFixture(
                filmType: .colorNegative,
                image: makeNegative(base: colorBase),
                base: FilmBase(rgb: colorBase, source: .border)
            ),
            FilmFixture(
                filmType: .colorPositive,
                image: makePositive(color: true),
                base: nil
            ),
            FilmFixture(
                filmType: .bwNegative,
                image: makeNegative(base: bwBase),
                base: FilmBase(rgb: bwBase, source: .border)
            ),
            FilmFixture(
                filmType: .bwPositive,
                image: makePositive(color: false),
                base: nil
            ),
        ]
    }

    private func makeNegative(base: SIMD3<Double>) -> CIImage {
        makeLinearImage { x, _ in
            let density = 0.04 + 1.50 * Double(x) / Double(width - 1)
            let transmission = pow(10.0, -density)
            return (base.x * transmission, base.y * transmission, base.z * transmission)
        }
    }

    private func makePositive(color: Bool) -> CIImage {
        makeLinearImage { x, _ in
            let value = 0.04 + 0.82 * Double(x) / Double(width - 1)
            guard color else { return (value, value, value) }
            return (min(value * 1.04, 1), value, value * 0.94)
        }
    }

    private func makeLinearImage(
        pixel: (Int, Int) -> (Double, Double, Double)
    ) -> CIImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var values = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let rgb = pixel(x, y)
                let offset = (y * width + x) * 4
                values[offset] = Float(rgb.0)
                values[offset + 1] = Float(rgb.1)
                values[offset + 2] = Float(rgb.2)
            }
        }
        return CIImage(
            bitmapData: Data(bytes: values, count: values.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: colorSpace
        )
    }

    private func renderLinearRGBAf(_ image: CIImage) -> [Float] {
        let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let context = CIContext(options: [.workingColorSpace: colorSpace, .outputColorSpace: colorSpace])
        var values = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &values,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: colorSpace
        )
        return values
    }

    private func makeSRGBCGImage(_ image: CIImage) -> CGImage? {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let output = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: output])
        return context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: output)
    }

    private func meanLuma(_ values: [Float], x: Int) -> Double {
        var total = 0.0
        var count = 0
        for y in 2..<(height - 2) {
            let offset = (y * width + x) * 4
            total += Double(values[offset]) * 0.2126
                + Double(values[offset + 1]) * 0.7152
                + Double(values[offset + 2]) * 0.0722
            count += 1
        }
        return total / Double(count)
    }
}
