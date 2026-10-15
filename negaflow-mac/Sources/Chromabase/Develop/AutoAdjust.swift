import Foundation
import CoreGraphics

// 라이트룸식 자동 보정(고전 알고리즘, AI 아님). 호출측(AppModel)이 대상 슬라이더를 0 으로 리셋한
// **중립 현상본**을 렌더해 그 통계를 넘기고, 여기 반환값을 슬라이더에 **대입**한다(누적 아님) → 1회 결정적.
//
// 2026-07-17 재설계(검증된 방법론 — 추측 아님):
//  • Auto Tone — 히스토그램 percentile 을 **linear 도메인**으로 환산해, 각 슬라이더의 실제
//    전달함수(ToneMapper.applyExposure — ExposureShoulder 와 같은 식, basicTone 커널의 luma 마스크·계수)를
//    **역산**한다. 노출→화이트/블랙→하이라이트/섀도→농도→대비 순서로, 앞 단계의 이동을 뒤 단계
//    percentile 예측에 반영한다(순차 시뮬레이션). 클리핑 목표는 일반 Auto Levels/Curves 의
//    0.1~0.5% 클리핑 관행을 따른다. 노출의 미드 앵커는 photometric mid(linear 0.18 — 반전
//    재설계와 동일 앵커)로, **밝히는 방향만** 움직인다(LATD "밝히는 방향만" 원리 — 설경/하이키를
//    회색으로 끌어내리는 gray-world 실패 배제); 감광은 실질 하이라이트 클리핑(≥5%)의 복구 전용.
//  • Auto WB — 근중립 부분집합(근중립 미드톤 평균 기반) 우선,
//    부족하면 gray-world(산술평균) 대신 **Minkowski p=6 norm 평균**(Shades-of-Gray,
//    Finlayson & Trezzi 2004 — 밝은 픽셀 가중으로 지배색 장면에서 산술평균보다 강건)으로 추정.
//    ColorModel 의 화이트밸런스 게인(WhiteBalanceGains — ±1 까지 예전 선형 게인, 그 너머 로그 연장)을
//    **linear 도메인 통계**로 역산하고, **부분 보정(85%) + 클램프(±0.6) + 데드밴드**를 둔다 —
//    완전 중립화(full-correction)는 gray-world 가정이 깨지는 장면(노을·숲·단색 배경)에서
//    반대 캐스트(과보정 노랑/파랑)로 폭주하고, 지각적으로도 차갑다(중립 회색 타겟의
//    문서화된 한계와 동일).
public enum AutoAdjust {
    public struct ImageStats: Sendable, Equatable {
        public var avgR: Double, avgG: Double, avgB: Double   // 0..1 (sRGB 감마 도메인 평균)
        public var neutralAvgR: Double, neutralAvgG: Double, neutralAvgB: Double
        public var neutralPixelFraction: Double
        public var lumaHist: [Double]                         // 256 bins (sRGB 감마 luma), 합=1
        public var avgSaturation: Double                      // 0..1 (HSV S 평균)
        /// 근중립 부분집합의 **linear** 평균(WB 역산 도메인 — ColorModel 게인은 linear 곱).
        public var neutralLinearR: Double, neutralLinearG: Double, neutralLinearB: Double
        /// Minkowski p=6 norm **linear** 평균(Shades-of-Gray) — 중립 부족 시 폴백.
        public var minkowskiLinearR: Double, minkowskiLinearG: Double, minkowskiLinearB: Double
        /// 휘도대별 중립축 증거(NeutralAxisEvidence). 있으면 자동 WB 가 대역 중앙값의 중앙값을 쓴다.
        var neutralAxis: NeutralAxisEvidence?

        public init(
            avgR: Double,
            avgG: Double,
            avgB: Double,
            lumaHist: [Double],
            avgSaturation: Double,
            neutralAvgR: Double? = nil,
            neutralAvgG: Double? = nil,
            neutralAvgB: Double? = nil,
            neutralPixelFraction: Double = 0,
            neutralLinearR: Double? = nil,
            neutralLinearG: Double? = nil,
            neutralLinearB: Double? = nil,
            minkowskiLinearR: Double? = nil,
            minkowskiLinearG: Double? = nil,
            minkowskiLinearB: Double? = nil
        ) {
            self.avgR = avgR; self.avgG = avgG; self.avgB = avgB
            self.neutralAvgR = neutralAvgR ?? avgR
            self.neutralAvgG = neutralAvgG ?? avgG
            self.neutralAvgB = neutralAvgB ?? avgB
            self.neutralPixelFraction = neutralPixelFraction
            self.lumaHist = lumaHist; self.avgSaturation = avgSaturation
            // 폴백: 감마 평균의 decode 근사(저채도 평균이라 오차 작음) — 합성 통계 테스트 호환.
            self.neutralLinearR = neutralLinearR ?? AutoAdjust.srgbDecode(self.neutralAvgR)
            self.neutralLinearG = neutralLinearG ?? AutoAdjust.srgbDecode(self.neutralAvgG)
            self.neutralLinearB = neutralLinearB ?? AutoAdjust.srgbDecode(self.neutralAvgB)
            self.minkowskiLinearR = minkowskiLinearR ?? AutoAdjust.srgbDecode(avgR)
            self.minkowskiLinearG = minkowskiLinearG ?? AutoAdjust.srgbDecode(avgG)
            self.minkowskiLinearB = minkowskiLinearB ?? AutoAdjust.srgbDecode(avgB)
        }
    }

    /// 현상 결과 톤 보정 델타. 현재 DevelopParameters 위에 더한다(clamp는 호출측).
    public struct ToneDelta: Sendable, Equatable {
        public var exposure = 0.0, contrast = 0.0, highlight = 0.0, shadow = 0.0
        public var whites = 0.0, blacks = 0.0, vibrance = 0.0, saturation = 0.0
        /// 미드톤 농도(basicTone density — 미드 국소, +가 어둡게). 노출이 하이라이트 헤드룸
        /// cap 에 걸려 못 채운/넘친 미드 잔차를 하이라이트를 건드리지 않고 마무리한다.
        public var density = 0.0
        public init() {}
    }

    // MARK: 이미지 통계 (다운샘플 RGBA8 → 평균색/luma 히스토그램/채도)

    /// CGImage 를 작은 격자로 다운샘플해 통계를 낸다(전체 픽셀 순회 불필요 — Lanczos 없이 ctx.draw 보간).
    public static func imageStats(_ cg: CGImage, sample: Int = 200) -> ImageStats? {
        let longSide = max(cg.width, cg.height)
        guard longSide > 0 else { return nil }
        let scale = min(1.0, Double(sample) / Double(longSide))
        let w = max(1, Int(Double(cg.width) * scale)), h = max(1, Int(Double(cg.height) * scale))
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // 8bit sRGB → linear 변환 LUT(256) — 픽셀별 정확 변환(평균의 decode ≠ decode 의 평균).
        var decodeLUT = [Double](repeating: 0, count: 256)
        for i in 0..<256 { decodeLUT[i] = srgbDecode(Double(i) / 255.0) }

        var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumSat = 0.0
        var neutralR = 0.0, neutralG = 0.0, neutralB = 0.0, neutralCount = 0
        var neutralLinR = 0.0, neutralLinG = 0.0, neutralLinB = 0.0
        var mink6R = 0.0, mink6G = 0.0, mink6B = 0.0
        var hist = [Double](repeating: 0, count: 256)
        let n = w * h
        var linearPixels: [SIMD3<Double>] = []
        linearPixels.reserveCapacity(n)
        for i in 0..<n {
            let o = i * 4
            let r = Double(data[o]) / 255, g = Double(data[o + 1]) / 255, b = Double(data[o + 2]) / 255
            let rl = decodeLUT[Int(data[o])], gl = decodeLUT[Int(data[o + 1])], bl = decodeLUT[Int(data[o + 2])]
            linearPixels.append(SIMD3(rl, gl, bl))
            sumR += r; sumG += g; sumB += b
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            hist[min(255, max(0, Int(luma * 255)))] += 1
            let mx = max(r, max(g, b)), mn = min(r, min(g, b))
            let sat = mx > 1e-6 ? (mx - mn) / mx : 0
            sumSat += sat
            // Minkowski p=6 (linear): 지배색 장면에서 산술평균보다 강건한 광원 추정
            // (Shades-of-Gray). 끝단(클립/순흑)은 정보가 없어 제외.
            if luma > 0.02 && luma < 0.99 {
                mink6R += pow(rl, 6); mink6G += pow(gl, 6); mink6B += pow(bl, 6)
            }
            // 근중립 후보: 채도·luma 대역을 좁혀 유채색/끝단 오염 배제
            // (근중립 미드톤 평균을 중립화 근거로 쓴다).
            if sat <= 0.22 && luma > 0.10 && luma < 0.90 {
                neutralR += r; neutralG += g; neutralB += b
                neutralLinR += rl; neutralLinG += gl; neutralLinB += bl
                neutralCount += 1
            }
        }
        let nd = Double(n)
        let neutralDen = Double(max(neutralCount, 1))
        let hasNeutralSamples = neutralCount >= max(16, n / 100)
        let mink6Count = max(1.0, nd)
        var stats = ImageStats(avgR: sumR / nd, avgG: sumG / nd, avgB: sumB / nd,
                          lumaHist: hist.map { $0 / nd }, avgSaturation: sumSat / nd,
                          neutralAvgR: hasNeutralSamples ? neutralR / neutralDen : sumR / nd,
                          neutralAvgG: hasNeutralSamples ? neutralG / neutralDen : sumG / nd,
                          neutralAvgB: hasNeutralSamples ? neutralB / neutralDen : sumB / nd,
                          neutralPixelFraction: Double(neutralCount) / nd,
                          neutralLinearR: hasNeutralSamples ? neutralLinR / neutralDen : nil,
                          neutralLinearG: hasNeutralSamples ? neutralLinG / neutralDen : nil,
                          neutralLinearB: hasNeutralSamples ? neutralLinB / neutralDen : nil,
                          minkowskiLinearR: pow(mink6R / mink6Count, 1.0 / 6.0),
                          minkowskiLinearG: pow(mink6G / mink6Count, 1.0 / 6.0),
                          minkowskiLinearB: pow(mink6B / mink6Count, 1.0 / 6.0))
        stats.neutralAxis = NeutralAxisEstimator.measure(linearPixels)
        return stats
    }

    // MARK: Auto White Balance (근중립 우선 + Shades-of-Gray 폴백, 부분 보정)

    /// WB 부분 보정 강도. 완전 중립화는 지배색 장면에서 반대 캐스트로 폭주하고 지각적으로
    /// 차갑다 — 측정 캐스트의 85% 만 걷는다(실무 관행; 중립 회색 타겟의 한계).
    static let wbCorrectionStrength = 0.85
    /// Warmth/Tint 절대 클램프. 슬라이더 전 범위(±4)가 아니라 잔차 캐스트 상한(±1 = 예전 슬라이더
    /// 끝, R/B ±0.525 스톱)까지만 — 반전이 채널 정규화(WB 의 대부분)를 이미 수행하므로 여기서
    /// 다루는 건 잔차다. 휘도대별 중립축 증거로 지배색 장면의 폭주가 줄어 ±0.6 에서 넓혔다.
    static let wbClamp = 1.0
    /// 데드밴드: R/B 채널비 오차가 이 이하(≈1.5%)면 이미 중립 — 건드리지 않는다.
    static let wbDeadband = 0.015

    /// 근중립(부족 시 Minkowski p=6) linear 평균을 무채색으로 보내는 Warmth/Tint.
    /// ColorModel 의 화이트밸런스 게인(WhiteBalanceGains)을 거꾸로 푼다: 온도는 R/B 를, 틴트는
    /// 온도가 남긴 G/√(R·B) 를 맞춘다. |w| ≤ 1 에서 온도 해는 예전 R(1+0.18w)=B(1−0.18w) 의 해와
    /// 같다(같은 식의 로그). R>B(따뜻)면 음수(식힘).
    public static func autoWhiteBalance(_ s: ImageStats) -> (warmth: Double, tint: Double) {
        let r: Double, g: Double, b: Double
        if let axis = s.neutralAxis, !axis.isFallback {
            // 휘도대마다 한 표 — 한 휘도대를 차지한 따뜻한 조명 면이 평균을 끌지 못한다.
            let cast = axis.medianCast
            (r, g, b) = (exp(cast.x), exp(cast.y), exp(cast.z))
        } else {
            let useNeutral = s.neutralPixelFraction >= 0.03
            r = useNeutral ? s.neutralLinearR : s.minkowskiLinearR
            g = useNeutral ? s.neutralLinearG : s.minkowskiLinearG
            b = useNeutral ? s.neutralLinearB : s.minkowskiLinearB
        }
        guard r > 1e-5, g > 1e-5, b > 1e-5 else { return (0, 0) }

        var warmth = WhiteBalanceGains.solve(log2(b / r), WhiteBalanceGains.warmthRedBlueStops)
        if abs(b - r) / max(r + b, 1e-6) * 2 < wbDeadband { warmth = 0 }
        warmth = clamp(warmth * wbCorrectionStrength, -wbClamp, wbClamp)

        // Tint: 온도를 적용한 뒤의 잔차로 푼다(온도 자신의 녹색 성분 포함).
        let residualGreenStops = 0.5 * (log2(r) + log2(b)) - log2(g)
            - WhiteBalanceGains.warmthGreenStops(warmth)
        var tint = WhiteBalanceGains.solve(residualGreenStops, WhiteBalanceGains.tintGreenStops)
        if abs(residualGreenStops) * log(2.0) < wbDeadband { tint = 0 }
        tint = clamp(tint * wbCorrectionStrength, -wbClamp, wbClamp)
        return (warmth, tint)
    }

    // MARK: Auto Tone (linear percentile 역산 + 순차 시뮬레이션)

    /// photometric 미드 앵커(linear) — 반전 재설계와 동일한 밝기 기준.
    static let midGrayLinear = 0.18
    /// 확산 화이트 목표(linear) — 노출/화이트가 상위 percentile 을 이 근처로 보낸다.
    static let diffuseWhiteLinear = 0.90
    /// 블랙 포인트 목표(linear ≈ sRGB 0.06) — 일반 Auto 의 0.1~0.5% 클리핑 관행.
    static let blackPointLinear = 0.005
    /// 감광(노출 −)을 발동하는 실질 클리핑 비율. 소수 스펙큘러(<5%)는 노출 대신
    /// Highlights 복구가 담당한다.
    static let clipRecoveryThreshold = 0.05
    /// 자동 톤이 스스로 낼 수 있는 노출 한도(스톱). 슬라이더 범위(DevelopToneRange.exposure)보다
    /// 좁게 둬 자동 결과가 사용자가 손으로 갈 수 있는 끝까지 밀어붙이지는 않게 한다.
    static let autoExposureLimit = 3.0

    public static func autoTone(_ s: ImageStats, filmType: FilmType = .colorNegative) -> ToneDelta {
        var d = ToneDelta()
        let hist = s.lumaHist
        func percentileSRGB(_ p: Double) -> Double {
            var acc = 0.0
            for i in 0..<256 { acc += hist[i]; if acc >= p { return Double(i) / 255 } }
            return 1
        }
        func lin(_ srgb: Double) -> Double { srgbDecode(srgb) }
        let clipHigh = hist[255], clipLow = hist[0]
        // 블랙/섀도 포인트는 스캔 프레임 경계(순흑 대량)에 강건한 percentile 을 쓴다. p005/p025 는
        // 경계가 2.5%만 넘어도 그 경계를 블랙/섀도 포인트로 잡아, 정상 노출 이미지의 암부까지
        // 목표점으로 끌어올려 이미지를 찢었다(사용자 증상). p02/p08 은 그보다 얇은 경계를 건너뛴다.
        let pBlackS = percentileSRGB(0.02), pShadowS = percentileSRGB(0.08)
        let p50s = percentileSRGB(0.50)
        let p975s = percentileSRGB(0.975), p98s = percentileSRGB(0.98)
        let p995s = percentileSRGB(0.995)
        let p10s = percentileSRGB(0.10), p90s = percentileSRGB(0.90)
        let p50 = lin(p50s), p98 = lin(p98s), p995 = lin(p995s)

        // ── 1. Exposure — photometric 미드 앵커, **밝히는 방향만**(설경/하이키 보호).
        //    상한: 미드를 채우다 p98(이상치 2% 제외한 실 하이라이트)이 확산 화이트 목표를
        //    넘지 않게. 감광은 실질 클리핑(≥5%)의 복구 전용 — 소수 스펙큘러 때문에 장면
        //    전체를 어둡게 만들지 않는다(그건 Highlights 가 담당). 노출만 linear 도메인
        //    (2^ev 물리) — 이후 슬라이더 역산은 basicTone 커널과 같은 sRGB 감마 도메인.
        //    한도는 ±3 스톱이다 — 슬라이드 필름의 노출 부족은 1.5스톱으로 복구가 안 된다.
        //    실제 리프트는 아래 headroomCap(하이라이트 여유)이 다시 눌러 주므로, 이 한도를 넓혀도
        //    여유가 없는 장면에서는 그만큼 올라가지 않는다.
        var ev = clamp(log2(midGrayLinear / max(p50, 1e-4)), 0, autoExposureLimit)
        let headroomCap = max(0, log2(0.95 / max(p98, 1e-4)))
        ev = min(ev, headroomCap)
        if clipHigh >= clipRecoveryThreshold {
            ev = clamp(log2(0.92 / max(p995, 1e-4)), -autoExposureLimit, 0)
        }
        d.exposure = ev

        // ── 2. 노출 적용 후 percentile 예측(엔진과 같은 노출 연산자 — EV>0 명부 숄더)을 감마 도메인으로.
        func afterEV(_ srgb: Double) -> Double {
            srgbEncode(min(ExposureShoulder.exposedLuminance(lin(srgb), stops: ev, filmType: filmType), 1))
        }
        let pBlackA = afterEV(pBlackS), pShadowA = afterEV(pShadowS)
        let p50a = afterEV(p50s)
        let p975a = afterEV(p975s), p995a = afterEV(p995s)

        // ── 3. Whites/Blacks — 엔드포인트 스트레치. basicTone(2026-07-18 photometric 재캘리브
        //    레이션) 의 실제 감마 도메인 계수·마스크로 역산: whites Δ = w·0.12·smoothstep(0.68,
        //    0.92,gy), blacks Δ = k·0.06·mask(gy). 목표: 확산 화이트 sRGB 0.956(linear 0.90) /
        //    블랙 포인트 sRGB 0.062(linear 0.005). 목표점 마스크가 작으면 하한 가드로 폭주 방지.
        let diffuseWhiteSRGB = srgbEncode(diffuseWhiteLinear)
        let blackPointSRGB = srgbEncode(blackPointLinear)
        let whMask = max(smoothstep(0.68, 0.92, p995a), 0.25)
        d.whites = clamp((diffuseWhiteSRGB - p995a) / (0.12 * whMask), -1, 1)
        if clipHigh > 0.001 { d.whites = min(d.whites, 0) }   // 이미 클리핑이면 더 밀지 않는다
        // 블랙 포인트는 헤이즈(들뜬 검정)를 내리는 방향이 주기능이다. 이미 깊은 검정(스캔
        // 프레임 경계 포함)을 목표점으로 **끌어올리면** 검정이 씻겨 이미지가 들뜬다(사용자
        // 증상). 상향 리프트는 소량으로 캡해 필름 페이퍼-블랙 느낌만 남기고, 하향(헤이즈 복구)은
        // 그대로 둔다.
        let blMask = max(smoothstep(0.0, 0.03, pBlackA) * (1 - smoothstep(0.14, 0.30, pBlackA)), 0.25)
        d.blacks = clamp((blackPointSRGB - pBlackA) / (0.06 * blMask), -1, 0.15)

        // ── 4. Highlights/Shadows — 복구 전용(한 방향). 상/하위 percentile 의 목표 초과분을
        //    커널 계수(0.10)·마스크로 역산한다. 순수 끝빈 클리핑 질량(clipLow/clipHigh)은
        //    **스캔 프레임 경계·순흑/순백 소수 픽셀**을 포함하므로 소량으로 캡한다 — 캡이 없으면
        //    검정 경계 하나가 shadow 를 최대로 밀어 암부만 과도하게 들리며 이미지를 찢는다.
        let hlMask = max(smoothstep(0.55, 0.80, p975a), 0.3)
        // 초과분의 절반만 회수(전량 회수는 명부가 균일하게 눌려 부자연 — 복구는 보수적으로).
        // 회수 시작점 = sRGB 0.89(linear 0.75).
        d.highlight = clamp(-min(clipHigh, 0.05) * 4.0
            - max(0, p975a - 0.89) * 0.5 / (0.10 * hlMask), -1, 0)
        // 섀도는 그 톤에서 슬라이더가 실제로 먹는 만큼(마스크)만 반응하고 초과분의 절반만 회수한다.
        // 예전엔 마스크를 하한(0.3)으로 나눠 역산해, 슬라이더가 거의 안 닿는 깊은 검정(흑백 프린트의
        // 검정·스캔 테두리)을 끌어올리려 최대치(0.8)로 밀었고 그 위의 중간 암부가 통째로 들렸다
        // (2026-10-15 실측: 흑백 7 장 중 5 장·컬러 19 장 중 8 장이 0.8, 하위 25% 지점 2 배 상승).
        let shMask = smoothstep(0.02, 0.08, pShadowA) * (1 - smoothstep(0.32, 0.46, pShadowA))
        d.shadow = clamp(min(clipLow, 0.05) * 4.0
            + max(0, 0.10 - pShadowA) * 0.5 / 0.10 * shMask, 0, 0.8)

        // ── 5. Density — 미드 정밀 앵커. 노출이 헤드룸 cap 에 걸려 남긴/넘친 미드 잔차를
        //    미드 국소 마스크(하이라이트 불침범)로 마무리한다. density>0 = 어둡게.
        let midResidual = p50a - srgbEncode(midGrayLinear)
        if abs(midResidual) > 0.02 {
            let mdMask = max(smoothstep(0.18, 0.36, p50a) * (1 - smoothstep(0.58, 0.76, p50a)), 0.3)
            d.density = clamp(midResidual / (0.10 * mdMask), -0.4, 0.4)
            // 밝히는 방향만 원칙(노출과 같다): 노출이 밝히지 않았다면 미드를 어둡게 하지 않는다 —
            // 하이키·설경을 회색으로 끌어내린다(2026-10-14 실측: 미드 127 → 116). 노출 과잉을
            // 되돌리는 양수 농도와 클리핑 복구만 남긴다.
            if ev <= 0, clipHigh < clipRecoveryThreshold { d.density = min(d.density, 0) }
        }

        // ── 6. Contrast — 지각(감마) 도메인 스프레드 목표(노출 이동 예측 반영). 평평한 장면은
        //    올리되 깎는 쪽은 소량만 — 스프레드 목표는 평균적인 컬러 장면의 값이라, 원래 대비가 큰
        //    장면(흑백 프린트·역광)을 그 값까지 깎으면 계조가 무너진다(실측 −0.45 한계에 붙었다).
        //    양 끝의 복구는 Highlights/Shadows 가 맡는다.
        let p10as = afterEV(p10s)
        let p90as = afterEV(p90s)
        d.contrast = clamp((0.52 - (p90as - p10as)) * 1.15, -0.15, 0.55)

        // ── 7. Vibrance — 채도가 낮으면 부스트(+ only — 라이트룸 Auto 도 채도를 거의 올리기만 한다).
        d.vibrance = clamp((0.42 - s.avgSaturation) * 1.0, 0, 0.6)
        return d
    }

    // MARK: Auto Tone 폐루프

    /// 자동 톤 1 회 폐루프 보정. 첫 계산(autoTone)은 슬라이더 전달함수를 모형으로 역산하지만
    /// 사용자 커브·색 깊이·스캐너 타겟·기본톤 상호작용은 모형 밖이다(2026-10-14 실측: 사용자
    /// 커브 +0.6 이 있어도 같은 값을 냈고 결과만 어긋났다). 계산값을 실제로 적용해 다시 잰 통계로
    /// 미드(노출이 밝힌 경우만 — 밝히는 방향만 원칙)와 백점을 한 번 바로잡는다. 결정적이다.
    public static func refineTone(_ delta: ToneDelta, measured s: ImageStats,
                                  filmType: FilmType = .colorNegative) -> ToneDelta {
        var d = delta
        let hist = s.lumaHist
        func percentileSRGB(_ p: Double) -> Double {
            var acc = 0.0
            for i in 0..<256 { acc += hist[i]; if acc >= p { return Double(i) / 255 } }
            return 1
        }
        let p50 = srgbDecode(percentileSRGB(0.50)), p98 = srgbDecode(percentileSRGB(0.98))
        var p995s = percentileSRGB(0.995)

        // 미드: 노출이 밝혔다면 남은 오차만큼 더/덜 밝힌다(헤드룸·한도 안에서).
        if d.exposure > 0 {
            var residual = log2(midGrayLinear / max(p50, 1e-4))
            if residual > 0 { residual = min(residual, max(0, log2(0.95 / max(p98, 1e-4)))) }
            let refined = clamp(d.exposure + residual, 0, autoExposureLimit)
            if abs(refined - d.exposure) > 0.02 {
                // 노출이 바뀌면 백점도 같이 움직인다 — 같은 연산자로 되돌린 뒤 다시 예측한다.
                let p995 = srgbDecode(p995s)
                let unexposed = ExposureShoulder.unexposedLuminance(p995, stops: d.exposure,
                                                                     filmType: filmType)
                p995s = srgbEncode(min(ExposureShoulder.exposedLuminance(unexposed, stops: refined,
                                                                         filmType: filmType), 1))
                d.exposure = refined
            }
        }

        // 백점: 확산 화이트 목표(linear 0.90)에 남은 오차를 Whites 계수로 메운다.
        let residualWhite = srgbEncode(diffuseWhiteLinear) - p995s
        if abs(residualWhite) > 0.01, hist[255] <= 0.001 || residualWhite < 0 {
            let mask = max(smoothstep(0.68, 0.92, p995s), 0.25)
            d.whites = clamp(d.whites + residualWhite / (0.12 * mask), -1, 1)
        }
        return d
    }

    // MARK: 수치 유틸

    @inline(__always)
    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    @inline(__always)
    static func smoothstep(_ lo: Double, _ hi: Double, _ x: Double) -> Double {
        let t = clamp((x - lo) / max(hi - lo, 1e-9), 0, 1)
        return t * t * (3 - 2 * t)
    }

    @inline(__always)
    static func srgbDecode(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    @inline(__always)
    static func srgbEncode(_ v: Double) -> Double {
        v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1.0 / 2.4) - 0.055
    }
}
