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

    // MARK: Calibration

    func testCalibrationRedSaturationBoostsRedChroma() {
        let red = solidRGB(0.62, 0.30, 0.30)
        var calib = CalibrationAdjust()
        calib.redSat = 1.0
        let baseChroma = meanChroma(render(red))
        let out = meanChroma(render(CalibrationStage.apply(to: red, calibration: calib)))
        XCTAssertGreaterThan(out, baseChroma + 0.01)
    }

    // MARK: helpers

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

    private func meanChroma(_ c: (r: Double, g: Double, b: Double)) -> Double {
        let y = meanLuma(c)
        return sqrt(pow(c.r - y, 2) + pow(c.g - y, 2) + pow(c.b - y, 2))
    }
}
