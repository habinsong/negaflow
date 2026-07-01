import XCTest
@testable import Chromabase

// 라이트룸식 자동 보정 알고리즘(AutoAdjust)의 방향성 검증.
final class AutoAdjustTests: XCTestCase {
    private func stats(_ r: Double, _ g: Double, _ b: Double, _ hist: [Double], sat: Double) -> AutoAdjust.ImageStats {
        AutoAdjust.ImageStats(avgR: r, avgG: g, avgB: b, lumaHist: hist, avgSaturation: sat)
    }
    private func spike(_ bin: Int) -> [Double] { var h = [Double](repeating: 0, count: 256); h[bin] = 1; return h }
    private func flat() -> [Double] { [Double](repeating: 1.0 / 256, count: 256) }

    func testAutoToneBrightensDarkImage() {
        let d = AutoAdjust.autoTone(stats(0.2, 0.2, 0.2, spike(51), sat: 0.3))   // luma 0.2
        XCTAssertGreaterThan(d.exposure, 0.3, "어두운 이미지는 노출을 올려야 한다")
    }
    func testAutoToneDoesNotDarkenBrightNonClippedImage() {
        // 하이라이트 여유가 있는 밝은 이미지(p99≈0.85)는 어둡게 만들면 안 된다(밝은 씬 보호).
        var h = [Double](repeating: 0, count: 256); h[217] = 1
        let d = AutoAdjust.autoTone(stats(0.85, 0.85, 0.85, h, sat: 0.3))
        XCTAssertGreaterThan(d.exposure, -0.15, "밝은(비클리핑) 이미지를 과하게 어둡게 하면 안 된다")
    }
    func testAutoToneDoesNotBrightenClippedImage() {
        // 하이라이트가 클리핑된 과노출 이미지(p99≈1.0)는 노출을 더 올리면 안 된다.
        var h = [Double](repeating: 0, count: 256); h[240] = 0.5; h[255] = 0.5
        let d = AutoAdjust.autoTone(stats(0.95, 0.95, 0.95, h, sat: 0.3))
        XCTAssertLessThanOrEqual(d.exposure, 0, "클리핑된 과노출 이미지는 노출을 더 올리면 안 된다")
    }
    func testAutoToneAddsContrastToFlatHistogram() {
        let d = AutoAdjust.autoTone(stats(0.5, 0.5, 0.5, spike(128), sat: 0.3))  // 단일 톤(분산 0)
        XCTAssertGreaterThan(d.contrast, 0, "평평한(저대비) 히스토그램은 대비를 올려야 한다")
    }
    func testAutoToneStretchesWhitesBlacksWhenCompressed() {
        // 0.3~0.7 에 몰린(압축된) 톤 → whites 올리고 blacks 내려 풀스트레치.
        var h = [Double](repeating: 0, count: 256); for i in 77...179 { h[i] = 1.0 / 103 }
        let d = AutoAdjust.autoTone(stats(0.5, 0.5, 0.5, h, sat: 0.3))
        XCTAssertGreaterThan(d.whites, 0, "상위가 떠 있으면 Whites 를 올려야")
        XCTAssertLessThan(d.blacks, 0, "하위가 떠 있으면 Blacks 를 내려야")
    }
    func testAutoToneBoostsLowSaturation() {
        let d = AutoAdjust.autoTone(stats(0.5, 0.5, 0.5, flat(), sat: 0.1))
        XCTAssertGreaterThan(d.vibrance, 0, "채도가 낮으면 Vibrance 를 올려야")
    }
    func testAutoWBNeutralizesWarmCast() {
        let (w, _) = AutoAdjust.autoWhiteBalance(stats(0.6, 0.5, 0.4, flat(), sat: 0.2))
        XCTAssertLessThan(w, 0, "따뜻한 캐스트(R>B)는 Warmth 를 낮춰 식혀야")
    }
    func testAutoWBNeutralizesCoolCast() {
        let (w, _) = AutoAdjust.autoWhiteBalance(stats(0.4, 0.5, 0.6, flat(), sat: 0.2))
        XCTAssertGreaterThan(w, 0, "차가운 캐스트(B>R)는 Warmth 를 올려 데워야")
    }
    func testAutoWBNeutralCastNoChange() {
        let (w, t) = AutoAdjust.autoWhiteBalance(stats(0.5, 0.5, 0.5, flat(), sat: 0.2))
        XCTAssertEqual(w, 0, accuracy: 0.03)
        XCTAssertEqual(t, 0, accuracy: 0.03)
    }
    func testAutoToneRecoversHighlightsWhenTopHeavy() {
        var h = [Double](repeating: 0, count: 256); for i in 200...255 { h[i] = 1.0 / 56 }
        let d = AutoAdjust.autoTone(stats(0.85, 0.85, 0.85, h, sat: 0.3))
        XCTAssertLessThan(d.highlight, 0, "상위가 밝게 몰리면 Highlights 를 내려 복구해야")
    }
    func testAutoToneLiftsShadowsWhenBottomHeavy() {
        var h = [Double](repeating: 0, count: 256); for i in 0...55 { h[i] = 1.0 / 56 }
        let d = AutoAdjust.autoTone(stats(0.15, 0.15, 0.15, h, sat: 0.3))
        XCTAssertGreaterThan(d.shadow, 0, "하위가 어둡게 몰리면 Shadows 를 올려 복구해야")
    }
}
