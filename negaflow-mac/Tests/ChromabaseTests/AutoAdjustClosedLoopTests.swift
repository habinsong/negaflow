import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

/// 자동 WB 의 휘도대별 중립축 증거와 자동 톤 폐루프(2026-10-14).
final class AutoAdjustClosedLoopTests: XCTestCase {
    private func displayCG(_ image: CIImage) -> CGImage {
        let mapped = DisplayGamutMap.apply(to: image)
        return ChromabaseEngine.sharedLinearRenderContext.createCGImage(
            mapped, from: mapped.extent, format: .RGBA8, colorSpace: SyntheticScan.srgb)!
    }

    /// 화면 15% 를 차지한 따뜻한 조명 면이 자동 WB 를 끌고 가지 않는다. 예전: 근중립 판정(채도 ≤ 0.22)이
    /// 웜 면을 받아들여 진짜 중립을 R/B 0.90 으로 식혔다.
    func testAutoWhiteBalanceIgnoresWarmLitRegion() throws {
        let width = 420, height = 200
        let tones = (0..<14).map { 0.01 * pow(0.70 / 0.01, Double($0) / 13) }
        let image = SyntheticScan.makeImage(width: width, height: height) { x, y in
            if y < 30 { return SIMD3(0.80, 0.62, 0.50) }          // 웜 조명 면(R/B 1.6)
            return SIMD3(repeating: tones[x * tones.count / width])
        }
        let stats = try XCTUnwrap(AutoAdjust.imageStats(displayCG(image)))
        XCTAssertNotNil(stats.neutralAxis)
        let wb = AutoAdjust.autoWhiteBalance(stats)
        let gains = WhiteBalanceGains.gains(warmth: wb.warmth, tint: wb.tint) ?? SIMD3(repeating: 1)
        XCTAssertEqual(gains.x / gains.z, 1, accuracy: 0.02, "웜 면 때문에 중립이 식었다 (w=\(wb.warmth))")
        XCTAssertEqual(gains.y / (gains.x * gains.z).squareRoot(), 1, accuracy: 0.02)
    }

    /// 자동 톤 폐루프: 사용자 커브(모형 밖)가 백점을 밀어도 다시 재서 목표(확산 화이트)로 되돌린다.
    func testRefineToneAbsorbsUserCurve() throws {
        let wedge = SyntheticScan.negativeWedge()
        let engine = ChromabaseEngine()
        func develop(_ configure: (inout DevelopParameters) -> Void) -> CGImage {
            var p = DevelopParameters()
            p.baseEstimationMode = .manual
            p.manualBaseRGB = SyntheticScan.colorBase
            configure(&p)
            return displayCG(engine.developScanner(
                image: wedge.image, base: FilmBase(rgb: SyntheticScan.colorBase, source: .manual), params: p))
        }
        func p995(_ cg: CGImage) throws -> Int {
            let s = try XCTUnwrap(AutoAdjust.imageStats(cg))
            var acc = 0.0
            for i in 0..<256 { acc += s.lumaHist[i]; if acc >= 0.995 { return i } }
            return 255
        }
        func apply(_ d: AutoAdjust.ToneDelta, to p: inout DevelopParameters) {
            p.exposure = d.exposure; p.contrast = d.contrast; p.density = d.density
            p.highlight = d.highlight; p.shadow = d.shadow; p.whites = d.whites; p.blacks = d.blacks
            p.vibrance = d.vibrance
        }
        let target = Int((AutoAdjust.srgbEncode(AutoAdjust.diffuseWhiteLinear) * 255).rounded())
        let first = AutoAdjust.autoTone(try XCTUnwrap(AutoAdjust.imageStats(develop { _ in })))
        let withCurve = develop { apply(first, to: &$0); $0.curveHighlights = 0.8 }
        let refined = AutoAdjust.refineTone(first, measured: try XCTUnwrap(AutoAdjust.imageStats(withCurve)))
        let after = develop { apply(refined, to: &$0); $0.curveHighlights = 0.8 }
        let afterWhite = try p995(after)
        let missBefore = abs(try p995(withCurve) - target), missAfter = abs(afterWhite - target)
        XCTAssertLessThanOrEqual(missAfter, 4, "폐루프 후 백점 \(afterWhite) / 목표 \(target)")
        XCTAssertLessThanOrEqual(missAfter, missBefore)
        XCTAssertEqual(refined.exposure, first.exposure, accuracy: 1e-9, "노출이 밝히지 않았으면 미드는 그대로")
    }

    /// 폐루프가 노출을 더 올릴 때 백점 예측은 숄더를 한 번만 거친다. 잰 백점이 이미 목표(확산 화이트)
    /// 위인데 노출을 올리면 백점은 더 올라가므로 화이트는 내려가야 한다. 예전: ÷2^EV 로 되돌려 숄더에
    /// 두 번 접어 백점을 목표 아래로 예측했고, 화이트를 그대로 두거나 올렸다(Windows 실측 247 → 250).
    func testRefineToneDoesNotDoubleFoldTheShoulder() {
        var hist = [Double](repeating: 0, count: 256)
        hist[60] = 0.60     // 어두운 미드 — 노출을 더 올린다
        hist[240] = 0.385   // p98 — 헤드룸이 조금 남아 노출이 조금만 오른다
        hist[247] = 0.015   // p995 — 목표(243) 위
        let measured = AutoAdjust.ImageStats(avgR: 0.4, avgG: 0.4, avgB: 0.4, lumaHist: hist, avgSaturation: 0.2)
        var first = AutoAdjust.ToneDelta()
        first.exposure = 0.438
        first.whites = 0.07
        let refined = AutoAdjust.refineTone(first, measured: measured)
        XCTAssertGreaterThan(refined.exposure, first.exposure + 0.02, "픽스처가 노출을 바꾸지 않는다")
        XCTAssertLessThan(refined.whites, first.whites, "목표 위 백점에서 노출을 올리며 화이트를 내리지 않았다")
    }

    /// 숄더 역함수는 순방향의 정확한 역이다.
    func testUnexposedLuminanceInvertsTheShoulder() {
        for stops in [0.0, 0.2, 0.438, 0.9, 2.0] {
            for y in [0.05, 0.4, 0.7, 0.9, 1.2] {
                let exposed = ExposureShoulder.exposedLuminance(y, stops: stops, filmType: .colorNegative)
                let back = ExposureShoulder.unexposedLuminance(exposed, stops: stops, filmType: .colorNegative)
                XCTAssertEqual(back, y, accuracy: 1e-9, "stops \(stops) y \(y)")
            }
        }
    }
}
