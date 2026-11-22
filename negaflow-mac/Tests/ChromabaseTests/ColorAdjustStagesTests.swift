import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class ColorAdjustStagesTests: XCTestCase {
    // MARK: Point curves

    func testEmptyPointCurvesAreIdentity() {
        XCTAssertTrue(PointCurves().isIdentity)
        let lut = CurveLUT.build([], size: 32)
        for i in 0..<lut.count {
            XCTAssertEqual(Double(lut[i]), Double(i) / 31, accuracy: 1e-3)
        }
    }

    func testRGBCurveLiftBrightensMidtone() {
        let gray = solid(0.5)
        var curves = PointCurves()
        curves.rgb = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.72), CurvePoint(x: 1, y: 1)]
        let baseline = meanLuma(render(gray))
        let lifted = meanLuma(render(PointCurveStage.apply(to: gray, curves: curves)))
        XCTAssertGreaterThan(lifted, baseline + 0.05, "중간톤을 올린 RGB 커브는 회색을 밝게 만들어야 합니다.")
    }

    func testRedChannelCurveShiftsTowardRed() {
        let gray = solid(0.5)
        var curves = PointCurves()
        curves.red = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.72), CurvePoint(x: 1, y: 1)]
        let out = render(PointCurveStage.apply(to: gray, curves: curves))
        XCTAssertGreaterThan(out.r, out.g + 0.04, "Red 커브 상승은 R 채널만 올려야 합니다.")
    }

    /// 마스터 커브만 건드리면 채널 합성은 항등이어야 한다. 가장 가까운 칸으로 반올림하던 앞
    /// 판은 값을 1/63 단위로 계단지게 만들었다(±2 레벨 띠).
    func testChannelCompositionInterpolatesInsteadOfSnappingToCells() {
        let rgb = CurveLUT.build(
            [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.18), CurvePoint(x: 0.5, y: 0.72),
             CurvePoint(x: 0.75, y: 0.86), CurvePoint(x: 1, y: 1)],
            size: 64
        )
        let composed = PointCurveStage.compose(rgb, CurveLUT.build([], size: 64))
        for index in rgb.indices {
            XCTAssertEqual(composed[index], rgb[index], accuracy: 1e-6)
        }
    }

    // MARK: Color mixer (HSL)

    func testColorMixerRedSaturationIncreasesRedChroma() {
        let red = solidRGB(0.62, 0.30, 0.30)
        var mixer = ColorMixer()
        mixer.saturation[MixerBand.red.rawValue] = 1.0
        let baseChroma = meanChroma(render(red))
        let boosted = meanChroma(render(ColorMixerStage.apply(to: red, mixer: mixer)))
        XCTAssertGreaterThan(boosted, baseChroma + 0.01, "빨강 채도 +1은 빨강 패치의 채도를 올려야 합니다.")
    }

    func testColorMixerIdentityIsNoOp() {
        let red = solidRGB(0.62, 0.30, 0.30)
        let base = render(red)
        let out = render(ColorMixerStage.apply(to: red, mixer: ColorMixer()))
        XCTAssertEqual(out.r, base.r, accuracy: 1e-3)
        XCTAssertEqual(out.g, base.g, accuracy: 1e-3)
    }

    func testColorMixerDecodeNormalizesMalformedBandCounts() throws {
        let data = #"{"hue":[0.25],"saturation":[],"luminance":[0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9]}"#
            .data(using: .utf8)!

        let mixer = try JSONDecoder().decode(ColorMixer.self, from: data)

        XCTAssertEqual(mixer.hue, [0.25, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(mixer.saturation, Array(repeating: 0, count: 8))
        XCTAssertEqual(mixer.luminance, [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8])
    }

    // MARK: Color grading

    func testColorGradingShadowTintAddsChroma() {
        let darkGray = solid(0.18)
        var grading = ColorGrading()
        grading.shadows.hue = 30      // 주황
        grading.shadows.saturation = 0.8
        let baseChroma = meanChroma(render(darkGray))
        let graded = meanChroma(render(ColorGradingStage.apply(to: darkGray, grading: grading)))
        XCTAssertGreaterThan(graded, baseChroma + 0.01, "어두운 영역에 색을 넣으면 채도가 생겨야 합니다.")
    }

    /// 사용자 슬라이더는 영역을 sRGB 인코딩 휘도로 가른다. 중간 회색(선형 0.18, sRGB 118)은
    /// Midtones 에 걸려야 한다. 선형으로 가르던 앞 판은 Shadows 100%·Midtones 0% 였다.
    /// 프리셋 경로(perceptual false, 이미 감마로 바꾼 값)는 그대로다. 윈도우
    /// `test_perceptual_midtone_range` 와 같은 수치다.
    func testColorGradingMidtonesReachMiddleGrayOnTheSliderPath() {
        let gray = solid(0.18)
        var grading = ColorGrading()
        grading.midtones.hue = 30
        grading.midtones.saturation = 0.6
        let graded = render(ColorGradingStage.apply(to: gray, grading: grading))
        XCTAssertGreaterThan(graded.r - graded.b, 0.05)

        let preset = render(ColorGradingStage.apply(to: gray, grading: grading, perceptual: false))
        XCTAssertEqual(preset.r, 0.18, accuracy: 1e-3)
        XCTAssertEqual(preset.b, 0.18, accuracy: 1e-3)
    }

    /// sRGB 주황(1, 0.5, 0)은 표시 색상환 30° 다. Orange 색상 +1 은 이웃 밴드와의 가중 평균만큼
    /// (약 16.6°) 민다. 선형 HSL 은 같은 화소를 12.8° 로 읽어 빨강 쪽에 걸었다.
    func testColorMixerUsesTheDisplayHueWheelOnTheSliderPath() {
        let orange = solidRGB(1.0, 0.21404114, 0.0)
        var mixer = ColorMixer()
        mixer.hue[MixerBand.orange.rawValue] = 1.0
        let hue = encodedHueDegrees(render(ColorMixerStage.apply(to: orange, mixer: mixer)))
        XCTAssertEqual(hue, 46.6, accuracy: 1.0)

        let preset = encodedHueDegrees(render(ColorMixerStage.apply(to: orange, mixer: mixer, perceptual: false)))
        XCTAssertGreaterThan(abs(preset - hue), 2)
    }

    // MARK: Calibration

    func testCalibrationRedSaturationBoostsRedChroma() {
        let red = solidRGB(0.62, 0.30, 0.30)
        var calib = CalibrationAdjust()
        calib.redSat = 1.0
        let baseChroma = meanChroma(render(red))
        let out = meanChroma(render(CalibrationStage.apply(to: red, calibration: calib)))
        XCTAssertGreaterThan(out, baseChroma + 0.01)
    }

    /// 사용자 Calibration 은 Color Mixer 와 같이 sRGB 인코딩 값에서 색상환을 계산한다. 프리셋 경로(이미
    /// 감마로 바꾼 값을 넘김)는 그대로다.
    func testCalibrationUsesTheDisplayHueWheelOnTheSliderPath() {
        let orange = solidRGB(1.0, 0.21404114, 0.0)   // sRGB (255, 128, 0), 표시 색상 30°
        var calib = CalibrationAdjust()
        calib.redHue = 1.0
        let slider = encodedHueDegrees(render(CalibrationStage.apply(to: orange, calibration: calib)))
        let preset = encodedHueDegrees(render(CalibrationStage.apply(to: orange, calibration: calib, perceptual: false)))
        XCTAssertGreaterThan(slider, 30.5, "the slider path rotates the display hue")
        XCTAssertGreaterThan(abs(preset - slider), 1, "the preset path keeps its own (encoded-input) wheel")
    }

    /// 사용자 슬라이더 단계와 포인트 커브는 [0,1] 밖 값을 잘라 버리지 않는다. 범위 안 화소는 앞 판과 같고,
    /// 1.0 넘는 하이라이트와 광색역 음수 채널은 보정 뒤에도 남는다(2026-11-22).
    func testSliderStagesKeepValuesOutsideTheUnitCube() {
        let highlight = solidRGB(1.4, 1.4, 1.4)
        let wide = solidRGB(0.6, 0.3, -0.05)
        var mixer = ColorMixer()
        mixer.saturation[MixerBand.blue.rawValue] = 0.5
        var grading = ColorGrading()
        grading.shadows.hue = 30
        grading.shadows.saturation = 0.8
        var calib = CalibrationAdjust()
        calib.blueSat = 0.5
        var curves = PointCurves()
        curves.rgb = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.52), CurvePoint(x: 1, y: 1)]
        let stages: [(String, (CIImage) -> CIImage)] = [
            ("mixer", { ColorMixerStage.apply(to: $0, mixer: mixer) }),
            ("grading", { ColorGradingStage.apply(to: $0, grading: grading) }),
            ("calibration", { CalibrationStage.apply(to: $0, calibration: calib) }),
            ("curve", { PointCurveStage.apply(to: $0, curves: curves) }),
        ]
        for (name, stage) in stages {
            let bright = renderExtended(stage(highlight))
            XCTAssertGreaterThan(bright.r, 1.3, "\(name) keeps a highlight above 1.0")
            XCTAssertEqual(bright.r, bright.b, accuracy: 0.02, "\(name) keeps the highlight neutral")
            XCTAssertLessThan(renderExtended(stage(wide)).b, -0.02, "\(name) keeps a wide-gamut negative channel")
        }
    }

    // MARK: helpers

    private func renderExtended(_ image: CIImage) -> (r: Double, g: Double, b: Double) {
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear,
                                      .workingFormat: CIFormat.RGBAf])
        var out = [Float](repeating: 0, count: 4)
        ctx.render(image, toBitmap: &out, rowBytes: 16, bounds: CGRect(x: 8, y: 8, width: 1, height: 1),
                   format: .RGBAf, colorSpace: linear)
        return (Double(out[0]), Double(out[1]), Double(out[2]))
    }

    private func solid(_ v: Float) -> CIImage { solidRGB(v, v, v) }

    private func solidRGB(_ r: Float, _ g: Float, _ b: Float, w: Int = 16, h: Int = 16) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var px = [Float](repeating: 1, count: w * h * 4)
        for i in 0..<(w * h) {
            px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b; px[i * 4 + 3] = 1
        }
        return CIImage(
            bitmapData: Data(bytes: px, count: px.count * MemoryLayout<Float>.size),
            bytesPerRow: w * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: w, height: h),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func render(_ image: CIImage, w: Int = 16, h: Int = 16) -> (r: Double, g: Double, b: Double) {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var out = [Float](repeating: 0, count: w * h * 4)
        ctx.render(image, toBitmap: &out, rowBytes: w * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: linear)
        var r = 0.0, g = 0.0, b = 0.0
        let n = w * h
        for i in 0..<n { r += Double(out[i * 4]); g += Double(out[i * 4 + 1]); b += Double(out[i * 4 + 2]) }
        return (r / Double(n), g / Double(n), b / Double(n))
    }

    private func meanLuma(_ c: (r: Double, g: Double, b: Double)) -> Double {
        c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
    }

    private func encodedHueDegrees(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func encode(_ v: Double) -> Double {
            let x = min(max(v, 0), 1)
            return x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055
        }
        let r = encode(c.r), g = encode(c.g), b = encode(c.b)
        let maximum = max(r, g, b), minimum = min(r, g, b), d = maximum - minimum
        guard d > 1e-5 else { return 0 }
        var h: Double
        if maximum == r { h = (g - b) / d; if g < b { h += 6 } }
        else if maximum == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        return h * 60
    }

    private func meanChroma(_ c: (r: Double, g: Double, b: Double)) -> Double {
        let y = meanLuma(c)
        return sqrt(pow(c.r - y, 2) + pow(c.g - y, 2) + pow(c.b - y, 2))
    }
}
