import CoreImage
import XCTest
@testable import Chromabase

/// 중립 스포이드: 찍은 점이 현상 결과에서 무채색이 되는 온도·틴트(2026-10-14).
final class NeutralWhiteBalancePickerTests: XCTestCase {
    private func castOf(_ c: SIMD3<Double>) -> (redBlue: Double, green: Double) {
        (log2(c.x / c.z), log2(c.y / (c.x * c.z).squareRoot()))
    }

    /// 역산은 정확하다 — 범위 안의 캐스트는 게인을 곱하면 중립이 된다.
    func testSolveNeutralizesReferenceExactly() throws {
        let references: [SIMD3<Double>] = [
            SIMD3(0.30, 0.25, 0.18), SIMD3(0.12, 0.15, 0.22), SIMD3(0.40, 0.33, 0.41),
            SIMD3(0.20, 0.20, 0.20), SIMD3(0.05, 0.06, 0.04),
        ]
        for reference in references {
            let wb = try XCTUnwrap(NeutralWhiteBalancePicker.solve(reference))
            let gains = WhiteBalanceGains.gains(warmth: wb.warmth, tint: wb.tint) ?? SIMD3(repeating: 1)
            let cast = castOf(gains * reference)
            XCTAssertEqual(cast.redBlue, 0, accuracy: 0.003, "\(reference)")
            XCTAssertEqual(cast.green, 0, accuracy: 0.003, "\(reference)")
        }
    }

    /// 범위를 넘는 캐스트는 끝값에서 멈춘다.
    func testSolveClampsToSliderRange() throws {
        let wb = try XCTUnwrap(NeutralWhiteBalancePicker.solve(SIMD3(0.40, 0.20, 0.01)))
        XCTAssertEqual(wb.warmth, -WhiteBalanceGains.maximum, accuracy: 1e-9)
    }

    /// 실제 엔진 경로: 캐스트가 남은 네거티브에 톤·커브·채도와 기존 온도까지 걸린 상태에서 회색
    /// 패치를 찍으면, 결과 화면에서 그 패치가 중립이 된다. 화면 결과는 커브가 채널비를 바꾸므로
    /// 기준을 화이트밸런스 입력에서 잰다.
    func testPickedNegativePatchBecomesNeutralThroughToneAndCurves() throws {
        let wedge = SyntheticScan.negativeWedge()
        // 베이스를 틀리게 지정하면 반전 뒤 채널별 캐스트가 남는다.
        let wrongBase = SyntheticScan.colorBase * SIMD3(1.0, 0.96, 0.88)
        var params = DevelopParameters()
        params.baseEstimationMode = .manual
        params.manualBaseRGB = wrongBase
        params.exposure = 0.6
        params.contrast = 0.4
        params.curveLights = 0.5
        params.saturation = 0.3
        params.warmth = 1.5
        params.tint = -0.7
        let base = FilmBase(rgb: wrongBase, source: .manual)
        let engine = ChromabaseEngine()
        let patch = 10
        func displayPatch(_ p: DevelopParameters) -> SIMD3<Double> {
            let developed = engine.developScanner(image: wedge.image, base: base, params: p)
            return SyntheticScan.patchMeans(DisplayGamutMap.apply(to: developed), wedge: wedge)[patch]
        }
        let before = castOf(displayPatch(params))
        XCTAssertGreaterThan(abs(before.redBlue) + abs(before.green), 0.1, "픽스처에 캐스트가 없다")

        var measurements = DevelopSceneMeasurements()
        let reference = engine.developWhiteBalanceInputPreview(
            image: wedge.image, base: base, params: params, maxDimension: 700, measurements: &measurements)
        let point = CGPoint(x: Double(wedge.patchCenters[patch]) / Double(wedge.width), y: 0.5)
        let sampled = try XCTUnwrap(NeutralWhiteBalancePicker.sample(reference, atUnit: point))
        let wb = try XCTUnwrap(NeutralWhiteBalancePicker.solve(sampled))
        params.warmth = wb.warmth
        params.tint = wb.tint
        let after = castOf(displayPatch(params))
        XCTAssertEqual(after.redBlue, 0, accuracy: 0.01, "w=\(wb.warmth)")
        XCTAssertEqual(after.green, 0, accuracy: 0.01, "t=\(wb.tint)")
    }

    /// 포지티브(슬라이드)도 같은 단계에서 잰다.
    func testPickedSlidePatchBecomesNeutral() throws {
        let width = 400, height = 120
        let image = SyntheticScan.makeImage(width: width, height: height) { x, _ in
            let gray = 0.05 + 0.5 * Double(x) / Double(width)
            return SIMD3(1.12, 1.0, 0.82) * gray
        }
        var params = DevelopParameters()
        params.filmType = .colorPositive
        params.contrast = 0.3
        params.curveDarks = -0.4
        let engine = ChromabaseEngine()
        var measurements = DevelopSceneMeasurements()
        let reference = engine.developWhiteBalanceInputPreview(
            image: image, base: nil, params: params, maxDimension: 0, measurements: &measurements)
        let sampled = try XCTUnwrap(NeutralWhiteBalancePicker.sample(reference, atUnit: CGPoint(x: 0.5, y: 0.5)))
        let wb = try XCTUnwrap(NeutralWhiteBalancePicker.solve(sampled))
        params.warmth = wb.warmth
        params.tint = wb.tint
        let developed = DisplayGamutMap.apply(to: engine.developScanner(image: image, base: nil, params: params))
        var px = [Float](repeating: 0, count: 4)
        ChromabaseEngine.sharedLinearRenderContext.render(
            developed, toBitmap: &px, rowBytes: 16,
            bounds: CGRect(x: width / 2, y: height / 2, width: 1, height: 1),
            format: .RGBAf, colorSpace: SyntheticScan.linear)
        let cast = castOf(SIMD3(Double(px[0]), Double(px[1]), Double(px[2])))
        XCTAssertEqual(cast.redBlue, 0, accuracy: 0.01)
        XCTAssertEqual(cast.green, 0, accuracy: 0.01)
    }

    /// 거의 검은 점은 채널비가 잡음이라 거부한다.
    func testSampleRejectsBlackPoint() {
        let image = SyntheticScan.makeImage(width: 64, height: 64) { _, _ in SIMD3(0.001, 0.002, 0.001) }
        XCTAssertNil(NeutralWhiteBalancePicker.sample(image, atUnit: CGPoint(x: 0.5, y: 0.5)))
    }
}
