import XCTest
import CoreGraphics
@testable import Chromabase

// 자동 보정 알고리즘(AutoAdjust)의 방향성 검증.
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
    private func highlight(of s: AutoAdjust.ImageStats, _ fraction: Double = 0.99) -> Double {
        var acc = 0.0
        for i in 0..<256 { acc += s.lumaHist[i]; if acc >= fraction { return AutoAdjust.srgbDecode(Double(i) / 255) } }
        return 1
    }

    /// 밝은(비클리핑) 이미지도 그 장면의 키(sceneKey)까지 내린다 — 예전의 "밝히는 방향만" 규칙은 사용자
    /// 카탈로그 398장 중 49%(컬러 네거티브 85%)에서 노출을 늘 0 으로 묶었다(2026-11-08).
    func testAutoToneDarkensBrightImageToSceneKey() {
        var h = [Double](repeating: 0, count: 256); h[217] = 0.98; h[250] = 0.02   // 대부분 linear ≈ 0.69
        let s = stats(0.85, 0.85, 0.85, h, sat: 0.3)
        let d = AutoAdjust.autoTone(s)
        // 장면 키까지 내리되, 백점(p995)이 회복 바닥 아래로 내려가지 않는 데서 멈춘다.
        let expected = max(AutoAdjust.sceneKeyExposure(logAverage: s.logAverageLuminance, highlight: highlight(of: s)),
                           log2(AutoAdjust.whiteRecoveryFloor / highlight(of: s, 0.995)))
        XCTAssertEqual(d.exposure, expected, accuracy: 1e-9)
        XCTAssertLessThan(d.exposure, -0.5, "밝은 이미지는 노출을 내려야 한다")
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
    func testAutoToneLeavesColorToColorControls() {
        let d = AutoAdjust.autoTone(stats(0.5, 0.5, 0.5, flat(), sat: 0.1))
        XCTAssertEqual(d.vibrance, 0, "자동 톤은 색상 값을 제안하지 않습니다")
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

    /// 흑백 프린트형(깊은 검정이 넓고 대비가 큰) 분포: 슬라이더가 닿지 않는 검정을 끌어올리려 Shadows 를
    /// 최대로 밀거나, 평균 컬러 장면의 스프레드에 맞추려 Contrast 를 크게 깎으면 계조가 무너진다
    /// (2026-10-15 실측: D-76 흑백 7 장 중 5 장 shadow 0.8·contrast −0.45, 하위 25% 지점 2 배 상승).
    func testAutoToneKeepsDeepBlacksAndContrastOfPrintLikeMonochrome() {
        var h = [Double](repeating: 0, count: 256)
        for i in 1...3 { h[i] = 0.04 }            // 12% 깊은 검정
        for i in 4...60 { h[i] = 0.28 / 57 }      // 28% 암부
        for i in 61...149 { h[i] = 0.10 / 89 }    // 10% 미드
        for i in 150...236 { h[i] = 0.50 / 87 }   // 50% 밝은 면
        let d = AutoAdjust.autoTone(stats(0.42, 0.42, 0.42, h, sat: 0.0), filmType: .bwNegative)
        XCTAssertLessThanOrEqual(d.shadow, 0.15, "깊은 검정 때문에 암부를 들었다 shadow=\(d.shadow)")
        XCTAssertGreaterThanOrEqual(d.contrast, -0.15, "대비를 크게 깎아 계조를 눌렀다 contrast=\(d.contrast)")
    }

    // MARK: 2026-07-17 재설계 가드 — 부분 보정/클램프/density/하이키 보호/지배색 강건성

    /// 강한 웜 캐스트: 보정은 클램프(±1 = 예전 슬라이더 끝, 2026-10-14 ±0.6 에서 넓힘) 이내여야
    /// 하고, 보정을 실제 게인으로 적용했을 때 캐스트 부호가 뒤집히면(과보정 → 반대 파랑) 안 된다.
    func testAutoWBDoesNotOvershootStrongWarmCastIntoBlue() {
        let s = stats(0.72, 0.55, 0.38, flat(), sat: 0.2)
        let (w, _) = AutoAdjust.autoWhiteBalance(s)
        XCTAssertLessThan(w, 0, "웜 캐스트는 식혀야 한다")
        XCTAssertGreaterThanOrEqual(w, -1.0, "Warmth 클램프(±1)를 넘으면 안 된다")
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

    /// 미드가 키보다 밝은 이미지: 노출이 내려서 맞추고, 농도는 쓰지 않는다(농도는 노출이 막힌 만큼만).
    func testAutoToneDarkensBrightMidtonesWithExposureNotDensity() {
        // 대부분 sRGB 0.62(linear 0.34), 명부 3% 가 linear 0.9.
        var h = [Double](repeating: 0, count: 256); h[158] = 0.97; h[243] = 0.03
        let s = stats(0.62, 0.62, 0.62, h, sat: 0.3)
        let d = AutoAdjust.autoTone(s)
        XCTAssertEqual(d.exposure, AutoAdjust.sceneKeyExposure(logAverage: s.logAverageLuminance,
                                                                highlight: highlight(of: s)), accuracy: 1e-9)
        XCTAssertLessThan(d.exposure, -0.2, "장면 키(r 0.08·s 8)에서 약 −0.26 스톱")
        XCTAssertEqual(d.density, 0, accuracy: 1e-12)
    }

    /// whiteRecoveryFloor 는 basicTone 의 대비(피벗 0.46, 지수 2^(c·0.9))·흰색 계열(0.12·smoothstep(0.68,
    /// 0.92)) 식으로, 자동 톤의 대비 최대(+0.55)와 흰색 계열 +1 이 확산 화이트(0.90)까지 되돌릴 수 있는 가장
    /// 낮은 백점이다. 커널 계수가 바뀌면 이 시험이 상수를 다시 맞추라고 알린다.
    func testWhiteRecoveryFloorMatchesBasicToneReach() {
        func contrast(_ x: Double, _ c: Double) -> Double {
            let pivot = 0.46, e = pow(2, c * 0.9)
            return x < pivot ? pivot * pow(x / pivot, e) : 1 - (1 - pivot) * pow((1 - x) / (1 - pivot), e)
        }
        let target = AutoAdjust.srgbEncode(AutoAdjust.diffuseWhiteLinear)
        var lo = 0.46, hi = target
        for _ in 0..<60 {
            let mid = 0.5 * (lo + hi)
            let y = contrast(mid, 0.55)
            if y + 0.12 * AutoAdjust.smoothstep(0.68, 0.92, y) < target { lo = mid } else { hi = mid }
        }
        XCTAssertEqual(AutoAdjust.whiteRecoveryFloor, AutoAdjust.srgbDecode(hi), accuracy: 0.001)
    }

    /// 자동 톤은 기본 톤 커널의 합성 순서(대비 → 농도 → 명부 → 암부 → 흰색 → 검정)대로 역산한다. 흰색이
    /// 한도(±1)에 걸리지 않으면 대비·명부가 옮긴 뒤의 백점(p995)이 정확히 확산 화이트에 닿는다.
    func testAutoToneWhitesLandOnDiffuseWhiteThroughTheComposedKernel() {
        var h = [Double](repeating: 0, count: 256)
        for i in 30...190 { h[i] = 1 }                       // 대비·노출·흰색이 모두 움직이는 장면
        let total = h.reduce(0, +)
        h = h.map { (v: Double) -> Double in v / total }
        let s = stats(0.3, 0.3, 0.3, h, sat: 0.2)
        let d = AutoAdjust.autoTone(s)
        XCTAssertGreaterThan(abs(d.contrast), 0.05, "시험이 대비 단계를 실제로 거친다")
        XCTAssertLessThan(abs(d.whites), 0.999, "흰색이 한도에 걸리지 않는 장면이어야 한다")
        var acc = 0.0, p995s = 1.0
        for i in 0..<256 { acc += h[i]; if acc >= 0.995 { p995s = Double(i) / 255; break } }
        let p995a = AutoAdjust.srgbEncode(min(ExposureShoulder.exposedLuminance(
            AutoAdjust.srgbDecode(p995s), stops: d.exposure, filmType: .colorNegative), 1))
        let white = BasicToneModel.apply(p995a, contrast: d.contrast, density: d.density, highlight: d.highlight,
                                         shadow: d.shadow, whites: d.whites, blacks: d.blacks)
        // 흰색 단계의 마스크는 그 단계의 입력에서 재고 검정 단계는 0.30 위를 건드리지 않으므로 정확하다.
        XCTAssertEqual(white, AutoAdjust.srgbEncode(AutoAdjust.diffuseWhiteLinear), accuracy: 1e-9)
    }

    /// 어둡힐 때 백점이 회복 바닥 아래로 내려가지 않는다.
    func testAutoToneDoesNotDarkenWhitesBelowRecoveryFloor() {
        var h = [Double](repeating: 0, count: 256); h[200] = 0.97; h[218] = 0.03   // 대부분 0.58, 백점 0.70
        let s = stats(0.8, 0.8, 0.8, h, sat: 0.2)
        let d = AutoAdjust.autoTone(s)
        XCTAssertLessThan(d.exposure, 0)
        XCTAssertGreaterThanOrEqual(0.70 * pow(2, d.exposure), AutoAdjust.whiteRecoveryFloor - 0.01)
    }

    /// 장면 키는 하이키를 높게, 로우키를 낮게 잡는다(Reinhard k = r·s^z). 같은 명부에서 로그 평균이 명부
    /// 쪽에 몰릴수록 키가 커지고, 키는 r/s ~ r·s 범위 안이다.
    func testSceneKeyFollowsSceneKey() {
        let low = AutoAdjust.sceneKey(logAverage: 0.02, highlight: 0.9)
        let normal = AutoAdjust.sceneKey(logAverage: 0.12, highlight: 0.9)
        let high = AutoAdjust.sceneKey(logAverage: 0.6, highlight: 0.9)
        XCTAssertLessThan(low, normal); XCTAssertLessThan(normal, high)
        for k in [low, normal, high] {
            XCTAssertGreaterThanOrEqual(k, AutoAdjust.sceneKeyCenter / AutoAdjust.sceneKeySpread - 1e-12)
            XCTAssertLessThanOrEqual(k, AutoAdjust.sceneKeyCenter * AutoAdjust.sceneKeySpread + 1e-12)
        }
        // 고정점: 그 노출을 준 뒤의 로그 평균이 그 장면의 키와 같다.
        let ev = AutoAdjust.sceneKeyExposure(logAverage: 0.3, highlight: 0.7)
        let g = pow(2, ev)
        XCTAssertEqual(log2(0.3 * g), log2(AutoAdjust.sceneKey(logAverage: 0.3 * g, highlight: 0.7 * g)), accuracy: 1e-3)
    }

    /// 장면 키 노출은 명부가 1 에 닿아 키가 노출에 빠르게 따라오는 영역에서도 정확한 근이다. 예전 고정점
    /// 반복(6 회)은 이 영역에서 최대 1 스톱 넘게 남았다.
    func testSceneKeyExposureIsExactWhereTheHighlightSaturates() {
        for logAverage in [0.002, 0.01, 0.05, 0.12, 0.3, 0.6] {
            for highlight in [0.02, 0.2, 0.6, 0.95, 1.0] where highlight >= logAverage {
                let ev = AutoAdjust.sceneKeyExposure(logAverage: logAverage, highlight: highlight)
                let g = pow(2, ev)
                let key = AutoAdjust.sceneKey(logAverage: logAverage * g, highlight: min(highlight * g, 1))
                XCTAssertEqual(log2(key / (logAverage * g)), 0, accuracy: 1e-9, "Lav \(logAverage) p99 \(highlight)")
            }
        }
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

    /// 실질 클리핑(≥5%)이면 장면 키와 무관하게 적어도 p995 를 0.92 로 내릴 만큼 어둡게 한다.
    func testAutoToneClippingDarkensAtLeastToRecoverHighlights() {
        var h = [Double](repeating: 0, count: 256); h[40] = 0.90; h[255] = 0.10
        let s = stats(0.3, 0.3, 0.3, h, sat: 0.2)
        let d = AutoAdjust.autoTone(s)
        XCTAssertLessThanOrEqual(d.exposure, log2(0.92 / 1.0) + 1e-9, "클리핑을 두고 밝히면 안 된다")
    }

    /// 보정 단계도 양방향이다: 잰 장면 키가 밝으면 노출을 더 내린다.
    func testRefineToneLowersExposureWhenMeasuredKeyIsBright() {
        var h = [Double](repeating: 0, count: 256); h[180] = 0.98; h[245] = 0.02   // 대부분 linear ≈ 0.46
        var first = AutoAdjust.ToneDelta(); first.exposure = -0.5
        let measured = stats(0.7, 0.7, 0.7, h, sat: 0.2)
        let refined = AutoAdjust.refineTone(first, measured: measured)
        let residual = log2(AutoAdjust.sceneKey(logAverage: measured.logAverageLuminance, highlight: highlight(of: measured))
                            / measured.logAverageLuminance)
        XCTAssertLessThan(residual, -0.1)
        let floorLimit = log2(AutoAdjust.whiteRecoveryFloor / highlight(of: measured, 0.995))
        XCTAssertEqual(refined.exposure, first.exposure + max(residual, floorLimit), accuracy: 1e-9)
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
