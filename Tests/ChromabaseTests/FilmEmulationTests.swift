import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// FilmEmulationStage 검증 — 데이터시트 사실을 측정으로 확인(합성 패치, 오버핏 방지).
//   • none / intensity 0 = 완전 항등
//   • Velvia: 채도·대비 큰 폭 증가(E100 보다), 딥 섀도우, 밝기대별 색 크로스오버
//   • E100: 절제된 채도 + 전 계조 뉴트럴(저대비)
//   • 채도 부스트는 여러 밝기에서 일관되게 동작(밝기 의존적 필름 응답)
final class FilmEmulationTests: XCTestCase {

    // MARK: 항등

    func testNoneIsIdentity() {
        let patch = solidRGB(0.4, 0.25, 0.15)
        assertEqualRGB(render(FilmEmulationStage.apply(to: patch, emulation: .none, intensity: 1.0)),
                       render(patch), accuracy: 1e-4)
    }

    func testIntensityZeroIsIdentity() {
        let patch = solidRGB(0.4, 0.25, 0.15)
        assertEqualRGB(render(FilmEmulationStage.apply(to: patch, emulation: .velvia50, intensity: 0)),
                       render(patch), accuracy: 1e-4)
    }

    // MARK: 채도

    func testBothFilmsBoostSaturationOnColoredPatch() {
        let green = solidRGB(0.14, 0.42, 0.16)
        let base = meanChroma(render(green))
        let e100 = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .ektachromeE100, intensity: 1)))
        let velvia = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .velvia50, intensity: 1)))
        XCTAssertGreaterThan(e100, base + 0.005, "E100 도 채도를 올려야 합니다(절제).")
        XCTAssertGreaterThan(velvia, base + 0.03, "Velvia 는 채도를 크게 올려야 합니다.")
    }

    func testVelviaMoreSaturatedThanE100() {
        let green = solidRGB(0.14, 0.42, 0.16)
        let e100 = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .ektachromeE100, intensity: 1)))
        let velvia = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .velvia50, intensity: 1)))
        XCTAssertGreaterThan(velvia, e100 + 0.03, "Velvia 채도 > E100 채도.")
    }

    /// 밝기가 달라도 채도 부스트가 일관되게 동작해야 한다(밝기 의존적 필름 응답).
    func testSaturationBoostConsistentAcrossBrightness() {
        for scale in [0.5, 1.0, 1.6] {
            let g = solidRGB(Float(0.10 * scale), Float(0.34 * scale), Float(0.12 * scale))
            let base = meanChroma(render(g))
            let velvia = meanChroma(render(FilmEmulationStage.apply(to: g, emulation: .velvia50, intensity: 1)))
            XCTAssertGreaterThan(velvia, base + 0.01, "밝기 \(scale) 에서도 Velvia 채도가 올라야 합니다.")
        }
    }

    // MARK: 대비 / 섀도우

    func testVelviaDeepensShadows() {
        let dark = solid(0.08)
        let base = meanLuma(render(dark))
        let velvia = meanLuma(render(FilmEmulationStage.apply(to: dark, emulation: .velvia50, intensity: 1)))
        XCTAssertLessThan(velvia, base - 0.01, "Velvia 는 섀도우를 더 깊게 크러시해야 합니다.")
    }

    /// Velvia 가 E100 보다 대비가 높다(밝은 패치 - 어두운 패치 휘도 스프레드가 더 큼).
    func testVelviaHigherContrastThanE100() {
        let dark = solid(0.16), light = solid(0.72)
        func spread(_ f: FilmEmulation) -> Double {
            let d = meanLuma(render(FilmEmulationStage.apply(to: dark, emulation: f, intensity: 1)))
            let l = meanLuma(render(FilmEmulationStage.apply(to: light, emulation: f, intensity: 1)))
            return l - d
        }
        XCTAssertGreaterThan(spread(.velvia50), spread(.ektachromeE100) + 0.02,
                             "Velvia 대비 > E100 대비.")
    }

    // MARK: 크로스오버 / 중립

    /// Velvia 채널 크로스오버 — 어두운 중립은 밝은 중립보다 상대적으로 쿨(B-R 가 더 큼).
    func testVelviaShadowsCoolerThanHighlights() {
        let darkGray = solid(0.14), lightGray = solid(0.68)
        let d = render(FilmEmulationStage.apply(to: darkGray, emulation: .velvia50, intensity: 1))
        let l = render(FilmEmulationStage.apply(to: lightGray, emulation: .velvia50, intensity: 1))
        XCTAssertGreaterThan((d.b - d.r), (l.b - l.r) + 0.004,
                             "Velvia 섀도우가 하이라이트보다 쿨(B-R 큼)해야 합니다.")
    }

    func testE100KeepsNeutralApproximatelyNeutral() {
        // "consistent gray scale rendition throughout the tonal range" — 여러 밝기에서 중립 유지.
        for v in [0.12, 0.35, 0.62] as [Float] {
            let out = render(FilmEmulationStage.apply(to: solid(v), emulation: .ektachromeE100, intensity: 1))
            XCTAssertLessThan(meanChroma(out), 0.02,
                              "E100 은 밝기 \(v) 중립 그레이를 크게 물들이면 안 됩니다.")
        }
    }

    func testE100TiltsCoolOnNeutral() {
        let out = render(FilmEmulationStage.apply(to: solid(0.4), emulation: .ektachromeE100, intensity: 1))
        XCTAssertGreaterThan(out.b, out.r + 0.002, "E100 은 중립을 미세하게 쿨(B>R)로 틸트해야 합니다.")
    }

    // MARK: intensity

    func testIntensityScalesMonotonically() {
        let green = solidRGB(0.14, 0.42, 0.16)
        let base = meanChroma(render(green))
        let half = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .velvia50, intensity: 0.5)))
        let full = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .velvia50, intensity: 1.0)))
        XCTAssertGreaterThan(half, base + 0.005, "intensity 0.5 는 원본보다 강해야 합니다.")
        XCTAssertGreaterThan(full, half + 0.005, "intensity 1.0 은 0.5 보다 강해야 합니다.")
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

    private func assertEqualRGB(_ a: (r: Double, g: Double, b: Double),
                                _ b: (r: Double, g: Double, b: Double),
                                accuracy: Double) {
        XCTAssertEqual(a.r, b.r, accuracy: accuracy)
        XCTAssertEqual(a.g, b.g, accuracy: accuracy)
        XCTAssertEqual(a.b, b.b, accuracy: accuracy)
    }
}
