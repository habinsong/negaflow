import XCTest
import CoreGraphics
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
    func testAutoToneStillBrightensDarkImageWithSmallWhiteOutliers() {
        var h = [Double](repeating: 0, count: 256)
        h[64] = 0.98
        h[255] = 0.02

        let d = AutoAdjust.autoTone(stats(0.26, 0.26, 0.26, h, sat: 0.22))

        XCTAssertGreaterThan(
            d.exposure,
            0.2,
            "어두운 이미지에 작은 흰색 이상치가 있어도 Auto Tone 노출은 장면 전체를 기준으로 올려야 합니다."
        )
        XCTAssertLessThan(
            d.highlight,
            0,
            "흰색 이상치는 노출을 포기하기보다 Highlights 복구 쪽으로 처리해야 합니다."
        )
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
    func testAutoWBUsesNeutralLowSaturationSamplesInsteadOfSaturatedColorBias() throws {
        let cg = try makeNeutralAndSaturatedRedPatch()
        let s = try XCTUnwrap(AutoAdjust.imageStats(cg, sample: 64))

        let (w, t) = AutoAdjust.autoWhiteBalance(s)

        XCTAssertEqual(
            w,
            0,
            accuracy: 0.12,
            "Auto WB는 고채도 빨강 영역보다 저채도 중립 샘플을 우선해야 합니다."
        )
        XCTAssertEqual(
            t,
            0,
            accuracy: 0.12,
            "저채도 중립 샘플이 충분하면 Tint도 크게 움직이면 안 됩니다."
        )
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

    /// 정상 노출 이미지 + 검정 프레임 경계(스캔 원본): 경계의 순흑 대량이 Shadows/Blacks 를
    /// 최대로 밀어 암부만 과도하게 들리며 이미지를 찢으면 안 된다(사용자 증상). 경계에 강건한
    /// percentile(p08/p02) + 클립 질량 캡으로 온건해야 한다.
    func testAutoToneDoesNotSlamShadowsForBlackFrameBorder() {
        // 5% 순흑 경계 + 95% 미드톤(sRGB 0.46 = linear 0.18, 이미 적정 노출).
        var h = [Double](repeating: 0, count: 256)
        h[0] = 0.05
        h[118] = 0.95
        let d = AutoAdjust.autoTone(stats(0.44, 0.44, 0.44, h, sat: 0.3))
        XCTAssertLessThan(d.shadow, 0.35,
            "검정 경계가 Shadows 를 최대로 밀면 안 된다(정상 노출 이미지 보호). shadow=\(d.shadow)")
        XCTAssertLessThanOrEqual(d.blacks, 0.15,
            "검정 경계가 Blacks 를 크게 끌어올려 검정을 씻으면 안 된다. blacks=\(d.blacks)")
    }

    // MARK: 2026-07-17 재설계 가드 — 부분 보정/클램프/density/하이키 보호/지배색 강건성

    /// 강한 웜 캐스트: 보정은 클램프(±0.6) 이내여야 하고, 보정을 실제 게인으로 적용했을 때
    /// 캐스트 부호가 뒤집히면(과보정 → 반대 파랑) 안 된다.
    func testAutoWBDoesNotOvershootStrongWarmCastIntoBlue() {
        let s = stats(0.72, 0.55, 0.38, flat(), sat: 0.2)
        let (w, _) = AutoAdjust.autoWhiteBalance(s)
        XCTAssertLessThan(w, 0, "웜 캐스트는 식혀야 한다")
        XCTAssertGreaterThanOrEqual(w, -0.6, "Warmth 클램프(±0.6)를 넘으면 안 된다")
        // 적용 시뮬레이션(ColorModel linear 게인): R'(1+0.18w) vs B'(1−0.18w) — 부호 유지.
        let rl = AutoAdjust.srgbDecode(0.72), bl = AutoAdjust.srgbDecode(0.38)
        let rAfter = rl * (1 + 0.18 * w), bAfter = bl * (1 - 0.18 * w)
        XCTAssertGreaterThanOrEqual(rAfter, bAfter - 0.02,
            "과보정으로 웜 캐스트가 파랑 캐스트로 뒤집히면 안 된다. R'=\(rAfter) B'=\(bAfter)")
    }

    /// 부분 보정: 측정 캐스트를 100% 지우지 않는다(완전 중립화는 지배색 장면 폭주·차가운 밸런스).
    /// 픽스처는 클램프(±0.6)에 걸리지 않는 약한 캐스트 — 부분 보정 비율 자체를 검증한다.
    func testAutoWBAppliesPartialCorrectionNotFull() {
        let s = stats(0.52, 0.50, 0.48, flat(), sat: 0.2)   // 약한 웜 캐스트
        let (w, _) = AutoAdjust.autoWhiteBalance(s)
        let rl = AutoAdjust.srgbDecode(0.52), bl = AutoAdjust.srgbDecode(0.48)
        let fullW = (bl - rl) / (0.18 * (rl + bl))          // full-correction 필요치
        XCTAssertLessThan(abs(w), abs(fullW) * 0.95,
            "부분 보정(≈85%)이어야 한다. w=\(w) full=\(fullW)")
        XCTAssertGreaterThan(abs(w), abs(fullW) * 0.6,
            "보정이 의미 있게 작동해야 한다. w=\(w) full=\(fullW)")
    }

    /// 지배색(화면 대부분이 고채도 빨강) + 소수 중립: gray-world 산술평균식 폭주 없이
    /// 중립 후보를 우선해 보정이 온건해야 한다.
    func testAutoWBResistsDominantSaturatedColor() throws {
        let cg = try makeDominantRedWithNeutralStrip()
        let s = try XCTUnwrap(AutoAdjust.imageStats(cg, sample: 64))
        let (w, t) = AutoAdjust.autoWhiteBalance(s)
        XCTAssertEqual(w, 0, accuracy: 0.15, "지배 빨강이 Warmth 를 끌고 가면 안 된다. w=\(w)")
        XCTAssertEqual(t, 0, accuracy: 0.15, "지배 빨강이 Tint 를 끌고 가면 안 된다. t=\(t)")
    }

    /// 미드가 photometric 앵커(linear 0.18)보다 밝은 이미지: 노출은 밝히는 방향만이므로 0,
    /// 미드 잔차는 density(+, 미드 국소 어둡히기)가 담당한다 — 하이라이트 불침범.
    func testAutoToneUsesDensityForBrightMidtones() {
        // p50 sRGB ≈ 0.62 (linear ≈ 0.34) — 미드가 앵커보다 +0.9 스탑 밝은 중간톤 이미지.
        let d = AutoAdjust.autoTone(stats(0.62, 0.62, 0.62, spike(158), sat: 0.3))
        XCTAssertEqual(d.exposure, 0, accuracy: 1e-9, "밝히는 방향이 아니면 노출은 0")
        XCTAssertGreaterThan(d.density, 0.1, "밝은 미드는 density(+) 로 국소 조정해야 한다")
    }

    /// 어두운 미드(노출 상한 이내): 노출이 미드 앵커를 채우면 density 잔차는 작아야 한다.
    /// (노출 상한을 넘는 극단 저조도는 density 가 이어받는 것이 설계 — 별도 케이스.)
    func testAutoToneDarkMidtonesPreferExposureOverDensity() {
        // p50 sRGB ≈ 0.353 (linear ≈ 0.10) — 노출 +0.82 스탑으로 앵커(0.18) 도달 가능.
        let d = AutoAdjust.autoTone(stats(0.35, 0.35, 0.35, spike(90), sat: 0.3))
        XCTAssertGreaterThan(d.exposure, 0.5, "어두운 미드는 노출이 주로 담당")
        XCTAssertLessThan(abs(d.density), 0.15, "노출이 채운 뒤 density 는 잔차만")
    }

    /// 노출 상한(AutoAdjust.autoExposureLimit)을 넘는 극단 저조도: 남은 미드 잔차를
    /// density(−, 미드 리프트)가 이어받는다 — 노출/농도의 역할 분담.
    func testAutoToneDensityTakesOverBeyondExposureCap() {
        // p50 sRGB ≈ 0.12 (linear ≈ 0.013) — 미드 앵커까지 3스탑을 넘게 필요하다.
        let d = AutoAdjust.autoTone(stats(0.12, 0.12, 0.12, spike(31), sat: 0.3))
        XCTAssertEqual(d.exposure, AutoAdjust.autoExposureLimit, accuracy: 1e-9, "노출은 상한까지")
        XCTAssertLessThan(d.density, -0.1, "남은 잔차는 density(미드 리프트)가 담당")
    }

    /// 하이키(밝은 비클리핑) 보호: 감광은 실질 클리핑(≥5%)에서만 — 설경/하이키를
    /// 회색으로 끌어내리지 않는다.
    func testAutoToneNeverDarkensHighKeyWithoutClipping() {
        var h = [Double](repeating: 0, count: 256); h[230] = 0.97; h[252] = 0.03
        let d = AutoAdjust.autoTone(stats(0.9, 0.9, 0.9, h, sat: 0.2))
        XCTAssertGreaterThanOrEqual(d.exposure, 0, "비클리핑 하이키를 어둡게 하면 안 된다")
    }

    private func makeDominantRedWithNeutralStrip(width: Int = 64, height: Int = 32) throws -> CGImage {
        var data = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if x < width * 4 / 5 {
                    data[offset] = 210; data[offset + 1] = 42; data[offset + 2] = 38   // 지배 빨강
                } else {
                    data[offset] = 120; data[offset + 1] = 120; data[offset + 2] = 122 // 중립 스트립
                }
            }
        }
        let provider = CGDataProvider(data: Data(data) as CFData)
        let cg = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: try XCTUnwrap(provider),
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
        return try XCTUnwrap(cg)
    }

    private func makeNeutralAndSaturatedRedPatch(width: Int = 64, height: Int = 32) throws -> CGImage {
        var data = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if x < width / 2 {
                    data[offset] = 128
                    data[offset + 1] = 128
                    data[offset + 2] = 128
                } else {
                    data[offset] = 235
                    data[offset + 1] = 38
                    data[offset + 2] = 32
                }
            }
        }
        let provider = CGDataProvider(data: Data(data) as CFData)
        let cg = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: try XCTUnwrap(provider),
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
        return try XCTUnwrap(cg)
    }
}
