import Foundation
import CoreGraphics
import CoreImage

// Automatic tone uses linear luminance, encoded only for the tone masks' histogram.
// WB uses bounded near-neutral evidence; neither operation changes saturation.
public enum AutoAdjust {
    public struct ImageStats: Sendable, Equatable {
        public var avgR: Double, avgG: Double, avgB: Double   // 0..1 (sRGB 감마 도메인 평균)
        public var neutralAvgR: Double, neutralAvgG: Double, neutralAvgB: Double
        public var neutralPixelFraction: Double
        public var lumaHist: [Double]                         // 256 bins (encoded linear luminance), sum=1
        public var avgSaturation: Double                      // 0..1 (HSV S 평균)
        /// 근중립 부분집합의 **linear** 평균(WB 역산 도메인 — ColorModel 게인은 linear 곱).
        public var neutralLinearR: Double, neutralLinearG: Double, neutralLinearB: Double
        /// Minkowski p=6 norm **linear** 평균(Shades-of-Gray) — 중립 부족 시 폴백.
        public var minkowskiLinearR: Double, minkowskiLinearG: Double, minkowskiLinearB: Double
        /// 휘도대별 중립축 증거(NeutralAxisEvidence). 있으면 자동 WB 가 대역 중앙값의 중앙값을 쓴다.
        var neutralAxis: NeutralAxisEvidence?
        var whiteBalanceConfidence = 1.0
        public var clippedFraction: Double = 0
        /// 표본 칸마다 (선형 휘도, 선형 최대 채널). 자동 톤이 노출·기본 톤 뒤에 새로 1 에 닿는 채널을 세는 데
        /// 쓴다(`ChannelHeadroom`). 휘도 히스토그램만 만든 합성 통계는 비어 있고, 그때는 채널 한도를 걸지 않는다.
        public var peakSamples: [SIMD2<Double>] = []
        /// 렌더한 8 비트 그림의 화소마다 가장 큰 채널 코드(0~255). 폐루프가 중립 현상본과 화소마다 맞대어 새로
        /// 255 에 닿은 화소를 센다 — 칸 평균은 구름·잎사귀처럼 질감 있는 명부의 클리핑을 묻는다(사용자 카탈로그
        /// 윈도우 감사: 칸 기준 0%, 화소 기준 5.75%). 합성 통계는 비어 있고, 그때는 칸으로 센다.
        public var pixelPeaks: [UInt8] = []
        /// 같은 화소의 인코딩 휘도 코드(0~255, 가장 큰 채널이 255 인 화소에만 채운다). 확산 화이트 위의 반사광·광원은
        /// 채널 한도에서 뺀다(`ChannelHeadroom.diffuseWhite`).
        public var pixelLuma: [UInt8] = []

        /// 장면 키 — 선형 휘도의 로그 평균(Reinhard 외 2002, 식 1). 휘도 히스토그램 칸 가운데를 선형으로
        /// 풀어 계산하므로 Windows(`auto_adjust.cpp`)가 같은 히스토그램에서 같은 값을 낸다. δ = 1e-4 가
        /// 검정 칸의 log 0 을 막는다.
        public var logAverageLuminance: Double {
            var sum = 0.0, weight = 0.0
            for (i, h) in lumaHist.enumerated() where h > 0 {
                sum += h * log(max(AutoAdjust.srgbDecode(Double(i) / 255), 1e-4))
                weight += h
            }
            return weight > 0 ? exp(sum / weight) : 0
        }

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

    /// 대상 톤 슬라이더에 대입할 절대값. 색상 필드는 호환을 위해 0으로 남긴다.
    public struct ToneDelta: Sendable, Equatable {
        public var exposure = 0.0, contrast = 0.0, highlight = 0.0, shadow = 0.0
        public var whites = 0.0, blacks = 0.0, vibrance = 0.0, saturation = 0.0
        /// 미드톤 농도(basicTone density — 미드 국소, +가 어둡게). 노출이 하이라이트 헤드룸
        /// cap 에 걸려 못 채운/넘친 미드 잔차를 하이라이트를 건드리지 않고 마무리한다.
        public var density = 0.0
        public init() {}
    }

    // MARK: 면적 평균 linear 표본 → 색 평균과 휘도 히스토그램

    /// CGImage를 linear RGB로 변환한 뒤 긴 변이 제한된 면적 평균 격자로 측정한다.
    public static func imageStats(_ cg: CGImage, sample: Int = 200) -> ImageStats? {
        guard let grid = SceneAnalysisSampler.sample(CIImage(cgImage: cg), longEdge: sample) else { return nil }
        var sum = SIMD3<Double>(repeating: 0), neutral = sum, neutralLinear = sum, minkowski = sum
        var neutralCount = 0, eligibleCount = 0, saturation = 0.0
        var hist = [Double](repeating: 0, count: 256)
        var eligible: [SIMD3<Double>] = []
        eligible.reserveCapacity(grid.pixels.count)
        var peaks: [SIMD2<Double>] = []
        peaks.reserveCapacity(grid.pixels.count)
        for (index, p) in grid.pixels.enumerated() {
            peaks.append(ChannelHeadroom.sample(p))
            let rgb = SIMD3(srgbEncode(max(0, p.x)), srgbEncode(max(0, p.y)), srgbEncode(max(0, p.z)))
            sum += rgb
            let y = 0.2126 * p.x + 0.7152 * p.y + 0.0722 * p.z
            let encodedY = srgbEncode(max(0, y))
            hist[min(255, max(0, Int((encodedY * 255).rounded())))] += 1
            let mx = max(rgb.x, max(rgb.y, rgb.z)), mn = min(rgb.x, min(rgb.y, rgb.z))
            let sat = mx > 1e-6 ? (mx - mn) / mx : 0
            saturation += sat
            guard grid.clippedFractions[index] == 0, min(p.x, min(p.y, p.z)) > 0.0003,
                  y > 0.002, y < 0.90 else { continue }
            eligible.append(p); eligibleCount += 1
            minkowski += SIMD3(pow(p.x, 6), pow(p.y, 6), pow(p.z, 6))
            if sat <= 0.22, encodedY > 0.10, encodedY < 0.90 {
                neutral += rgb; neutralLinear += p; neutralCount += 1
            }
        }
        let n = Double(grid.pixels.count), count = Double(max(neutralCount, 1))
        let hasNeutral = neutralCount >= max(16, grid.pixels.count / 100)
        let m = Double(max(eligibleCount, 1))
        var stats = ImageStats(avgR: sum.x / n, avgG: sum.y / n, avgB: sum.z / n,
            lumaHist: hist.map { $0 / n }, avgSaturation: saturation / n,
            neutralAvgR: hasNeutral ? neutral.x / count : sum.x / n,
            neutralAvgG: hasNeutral ? neutral.y / count : sum.y / n,
            neutralAvgB: hasNeutral ? neutral.z / count : sum.z / n,
            neutralPixelFraction: Double(neutralCount) / n,
            neutralLinearR: hasNeutral ? neutralLinear.x / count : nil,
            neutralLinearG: hasNeutral ? neutralLinear.y / count : nil,
            neutralLinearB: hasNeutral ? neutralLinear.z / count : nil,
            minkowskiLinearR: pow(minkowski.x / m, 1.0 / 6.0),
            minkowskiLinearG: pow(minkowski.y / m, 1.0 / 6.0),
            minkowskiLinearB: pow(minkowski.z / m, 1.0 / 6.0))
        stats.neutralAxis = NeutralAxisEstimator.measure(eligible)
        if stats.neutralAxis != nil {
            stats.neutralAxis!.confidence *= min(1, Double(eligible.count) / (n * 0.10))
        }
        stats.whiteBalanceConfidence = stats.neutralAxis?.confidence ?? 0
        stats.clippedFraction = grid.clippedFractions.reduce(0, +) / n
        stats.peakSamples = peaks
        (stats.pixelPeaks, stats.pixelLuma) = ChannelHeadroom.pixelPeaks(cg)
        return stats
    }

    // MARK: Auto White Balance (근중립 우선 + Shades-of-Gray 폴백, 부분 보정)

    /// 최대 보정 강도. 실제 적용량은 중립 후보의 비율과 휘도 범위로 더 줄인다.
    static let wbCorrectionStrength = 0.85
    /// Warmth/Tint 절대 클램프. 슬라이더 전 범위(±4)가 아니라 잔차 캐스트 상한(±1 = 예전 슬라이더
    /// 끝)까지만 보정한다. 기본 반전의 자동 밸런스와는 별도 조정이다.
    /// 장면색과 광원색을 구분할 근거가 부족한 자동 추정은 제한하고 큰 캐스트는 수동 WB로 맞춘다.
    static let wbClamp = 1.0
    /// 데드밴드: R/B 채널비 오차가 이 이하(≈1.5%)면 이미 중립 — 건드리지 않는다.
    static let wbDeadband = 0.015

    /// 근중립(부족 시 Minkowski p=6) linear 평균을 무채색으로 보내는 Warmth/Tint.
    /// ColorModel 의 화이트밸런스 게인(WhiteBalanceGains)을 거꾸로 푼다: 온도는 R/B 를, 틴트는
    /// 온도가 남긴 G/√(R·B) 를 맞춘다. |w| ≤ 1 에서 온도 해는 예전 R(1+0.18w)=B(1−0.18w) 의 해와
    /// 같다(같은 식의 로그). R>B(따뜻)면 음수(식힘).
    public static func autoWhiteBalance(_ s: ImageStats) -> (warmth: Double, tint: Double) {
        let r: Double, g: Double, b: Double
        var confidence = s.whiteBalanceConfidence
        if let axis = s.neutralAxis {
            confidence = axis.confidence
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
        warmth = clamp(warmth * wbCorrectionStrength * confidence, -wbClamp, wbClamp)

        // Tint: 온도를 적용한 뒤의 잔차로 푼다(온도 자신의 녹색 성분 포함).
        let residualGreenStops = 0.5 * (log2(r) + log2(b)) - log2(g)
            - WhiteBalanceGains.warmthGreenStops(warmth)
        var tint = WhiteBalanceGains.solve(residualGreenStops, WhiteBalanceGains.tintGreenStops)
        if abs(residualGreenStops) * log(2.0) < wbDeadband { tint = 0 }
        tint = clamp(tint * wbCorrectionStrength * confidence, -wbClamp, wbClamp)
        return (warmth, tint)
    }

    // MARK: Auto Tone (linear percentile 역산 + 순차 시뮬레이션)

    /// photometric 미드 앵커(linear) — 반전 재설계와 동일한 밝기 기준.
    static let midGrayLinear = 0.18
    /// 노출이 맞추는 장면 키(로그 평균 휘도) — Reinhard 의 자동 키 식 k = r·s^z,
    /// z = (2·log Lav − log Lmin − log Lmax) / (log Lmax − log Lmin) (Reinhard 2002 JGT, US7636496).
    /// 하이키 장면(로그 평균이 명부 쪽에 몰림)은 키를 높게, 로우키는 낮게 잡아 설경을 회색으로 끌어내리지
    /// 않는다. Lmin 은 자동 톤의 검정 목표(blackPointLinear), Lmax 는 장면 명부 p99 다.
    /// r·s 는 사용자 카탈로그에서 손으로 톤을 맞춘 145장과 실제 파이프라인(노출 한도·회복 바닥·기본 톤 합성·
    /// 폐루프 포함)으로 비교해 골랐다(2026-11-08, 결과 로그 평균 대비 |log2| 오차):
    ///   r 0.10·s 4(Reinhard 의 s) — 중앙값 0.28·상위 10% 0.78 스톱, 밝은 장면(중립 로그 평균 ≥ 0.30, 33장)
    ///     편향 −0.62 스톱, 백점 하위 10% 0.52
    ///   r 0.09·s 6 — 0.25·0.66, 밝은 장면 −0.46
    ///   r 0.08·s 8 — 0.25·0.64, 밝은 장면 −0.17, 백점 하위 10% 0.74(채널 클리핑 0.5% 초과는 13→18장)
    /// 같은 데이터에서 고정 키 0.18 은 0.55·1.40, 장면 p01 을 Lmin 으로 쓴 원식은 0.35·1.00 이었다.
    /// 세 후보를 같은 145장에서 고른 값이라 표본 밖 오차는 이보다 클 수 있다.
    static let sceneKeyCenter = 0.08
    static let sceneKeySpread = 8.0

    /// 장면 키(목표 로그 평균). `highlight` 는 장면 명부(p99, 선형).
    static func sceneKey(logAverage: Double, highlight: Double) -> Double {
        let low = log2(blackPointLinear)
        let high = log2(max(highlight, blackPointLinear * 2))
        let z = clamp((2 * log2(max(logAverage, 1e-4)) - low - high) / (high - low), -1, 1)
        return sceneKeyCenter * pow(sceneKeySpread, z)
    }

    /// 노출 ev 를 준 뒤의 로그 평균이 그 장면 키와 같아지는 ev. 키가 노출에 따라 변하므로(z 가 Lav·p99
    /// 에 의존) f(ev) = log2(키 / 로그 평균) = 0 을 이분법으로 푼다. f 는 ev → −∞ 에서 양수, +∞ 에서 음수이고
    /// 로그 평균 0.001~0.9·명부 0.012~1.5 격자에서 부호가 한 번만 바뀐다(2026-11-08). 예전 고정점 반복
    /// (6 회)은 명부가 1 에 닿는 영역에서 수축률이 0.79 까지 올라, s 4 에서도 최대 0.10 스톱·s 8 에서는
    /// 1.09 스톱이 남았다. ±16 스톱 구간 60 회라 오차는 1e-16 스톱 아래다.
    static func sceneKeyExposure(logAverage: Double, highlight: Double) -> Double {
        func residual(_ ev: Double) -> Double {
            let gain = pow(2, ev)
            let lav = max(logAverage, 1e-4) * gain
            return log2(sceneKey(logAverage: lav, highlight: min(highlight * gain, 1)) / lav)
        }
        var low = -16.0, high = 16.0
        for _ in 0..<60 {
            let mid = 0.5 * (low + high)
            if residual(mid) > 0 { low = mid } else { high = mid }
        }
        return 0.5 * (low + high)
    }

    /// 확산 화이트 목표(linear) — 노출/화이트가 상위 percentile 을 이 근처로 보낸다.
    static let diffuseWhiteLinear = 0.90
    /// 블랙 포인트 목표(linear ≈ sRGB 0.06).
    static let blackPointLinear = 0.005
    /// 노출로 어둡게 할 때 백점(p995)의 바닥(선형). 자동 톤이 쓰는 대비 최대(+0.55)와 흰색 계열 최대(+1)를
    /// 함께 걸어도 확산 화이트(0.90)까지 되돌릴 수 있는 가장 낮은 백점이다(basicTone 계수로 푼 값,
    /// `testWhiteRecoveryFloorMatchesBasicToneReach`). 그 아래로 내리면 흰색이 회색으로 남는다 — 사용자
    /// 카탈로그 실측에서 바닥 없이 내리면 평탄하고 밝은 네거티브 14장의 백점이 0.43~0.5 로 떨어졌고,
    /// 손으로 맞춘 145장과의 오차도 이 바닥 근처(0.55~0.65)에서 가장 작았다(2026-11-08).
    static let whiteRecoveryFloor = 0.584
    /// 감광(노출 −)을 발동하는 실질 클리핑 비율. 소수 스펙큘러(<5%)는 노출 대신
    /// Highlights 복구가 담당한다.
    static let clipRecoveryThreshold = 0.05
    /// 자동 톤이 스스로 낼 수 있는 노출 한도(스톱). 슬라이더 범위(DevelopToneRange.exposure)보다
    /// 좁게 둬 자동 결과가 사용자가 손으로 갈 수 있는 끝까지 밀어붙이지는 않게 한다.
    static let autoExposureLimit = 3.0

    /// 밝히는 기본 톤 단계의 상한(채널 한도용). 흰색·대비는 양수 상한, 농도는 밝히는 쪽(음수) 크기의 상한이다.
    struct LiftCaps {
        var whites = Double.infinity, densityLift = Double.infinity, contrast = Double.infinity
    }

    public static func autoTone(_ s: ImageStats, filmType: FilmType = .colorNegative) -> ToneDelta {
        let hist = s.lumaHist
        func percentileSRGB(_ p: Double) -> Double {
            var acc = 0.0
            for i in 0..<256 { acc += hist[i]; if acc >= p { return Double(i) / 255 } }
            return 1
        }
        func lin(_ srgb: Double) -> Double { srgbDecode(srgb) }
        let clipHigh = max(hist[255], s.clippedFraction), clipLow = hist[0]
        // 블랙/섀도 포인트는 스캔 프레임 경계(순흑 대량)에 강건한 percentile 을 쓴다. p005/p025 는
        // 경계가 2.5%만 넘어도 그 경계를 블랙/섀도 포인트로 잡아, 정상 노출 이미지의 암부까지
        // 목표점으로 끌어올려 이미지를 찢었다(사용자 증상). p02/p08 은 그보다 얇은 경계를 건너뛴다.
        let pBlackS = percentileSRGB(0.02), pShadowS = percentileSRGB(0.08)
        let p50s = percentileSRGB(0.50)
        let p975s = percentileSRGB(0.975), p98s = percentileSRGB(0.98)
        let p995s = percentileSRGB(0.995)
        let p10s = percentileSRGB(0.10), p90s = percentileSRGB(0.90)
        let p98 = lin(p98s), p995 = lin(p995s)

        // ── 1. Exposure — 장면 키(로그 평균 휘도)를 sceneKey 로 보낸다. 양방향이다: 밝은 장면은
        //    내리고 어두운 장면은 올린다(현상소 LATD 전량 보정, Lightroom 자동과 같은 방향). 예전에는
        //    밝히는 쪽만 허용해, 중립 현상본이 18% 보다 밝은 사진(사용자 카탈로그 398장 중 49%, 컬러
        //    네거티브는 85%)에서 노출이 늘 0 이었다(2026-11-08 실측).
        //    밝힐 때는 p98(이상치 2% 를 뺀 실제 명부)이 0.95 를 넘지 않게, 어둡힐 때는 백점이
        //    whiteRecoveryFloor 아래로 내려가지 않게 막는다. 실질 클리핑(≥5%)이면 적어도 p995 를 0.92 로
        //    내릴 만큼 어둡게 한다. 노출은 선형(2^ev) 곱이라 선형에서 계산한다.
        let wantedEV = sceneKeyExposure(logAverage: s.logAverageLuminance, highlight: lin(percentileSRGB(0.99)))
        var ev = clamp(wantedEV, -autoExposureLimit, autoExposureLimit)
        if ev > 0 { ev = min(ev, max(0, log2(0.95 / max(p98, 1e-4)))) }
        if ev < 0 { ev = max(ev, min(0, log2(whiteRecoveryFloor / max(p995, 1e-4)))) }
        if clipHigh >= clipRecoveryThreshold {
            ev = min(ev, clamp(log2(0.92 / max(p995, 1e-4)), -autoExposureLimit, 0))
        }
        // ── 2~6. 노출 뒤의 기본 톤. 채널 한도(7)가 노출을 줄이면 이 단계들을 그 노출로 다시 푼다.
        func solve(_ ev: Double, _ caps: LiftCaps) -> ToneDelta {
            var d = ToneDelta()
            d.exposure = ev

            // ── 2. 노출 적용 후 percentile 예측(엔진과 같은 노출 연산자 — EV>0 명부 숄더)을 감마 도메인으로.
            func afterEV(_ srgb: Double) -> Double {
                srgbEncode(min(ExposureShoulder.exposedLuminance(lin(srgb), stops: ev, filmType: filmType), 1))
            }
            let pBlackA = afterEV(pBlackS), pShadowA = afterEV(pShadowS)
            let p50a = afterEV(p50s)
            let p975a = afterEV(p975s), p995a = afterEV(p995s)

            // 기본 톤 커널은 대비 → 농도 → 명부 → 암부 → 흰색 → 검정 순서로 단계를 합성한다
            // (BasicToneModel). 각 슬라이더는 앞 단계를 이미 적용한 값에서, 그 단계의 실제 계수·마스크로
            // 역산한다 — 예전에는 모두 노출 직후 값에서 따로 역산해 대비가 옮긴 백점·암부를 보지 못했다.

            // ── 3. Contrast — 지각(감마) 도메인 스프레드 목표(노출 이동 예측 반영). 평평한 장면은
            //    올리되 깎는 쪽은 소량만 — 스프레드 목표는 평균적인 컬러 장면의 값이라, 원래 대비가 큰
            //    장면(흑백 프린트·역광)을 그 값까지 깎으면 계조가 무너진다(실측 −0.45 한계에 붙었다).
            //    양 끝의 복구는 Highlights/Shadows 가 맡는다.
            let p10as = afterEV(p10s)
            let p90as = afterEV(p90s)
            d.contrast = min(clamp((0.52 - (p90as - p10as)) * 1.15, -0.15, 0.55), caps.contrast)
            func throughContrast(_ v: Double) -> Double { BasicToneModel.contrast(v, d.contrast) }

            // ── 4. Density — 노출이 명부 여유(p98 ≤ 0.95)·채널 한도·노출 한도(±3 스톱)에 막혀 키까지 못 밝힌
            //    만큼만 중간톤을 밝힌다(명부 불침범, density < 0 = 밝게). 장면 키는 노출이 맞추므로 그 밖에서는 0 이다.
            if wantedEV - ev > 0.05 {
                let goal = srgbEncode(min(lin(p50a) * pow(2, wantedEV - ev), diffuseWhiteLinear))
                let mid = throughContrast(p50a)
                let mdMask = max(BasicToneModel.densityMask(mid), 0.3)
                d.density = max(clamp((mid - goal) / (0.10 * mdMask), -0.4, 0), -caps.densityLift)
            }
            func throughDensity(_ v: Double) -> Double { BasicToneModel.density(throughContrast(v), d.density) }

            // ── 5. Highlights/Shadows — 복구 전용(한 방향). 상/하위 percentile 의 목표 초과분을
            //    커널 계수(0.10)·마스크로 역산한다. 순수 끝빈 클리핑 질량(clipLow/clipHigh)은
            //    **스캔 프레임 경계·순흑/순백 소수 픽셀**을 포함하므로 소량으로 캡한다 — 캡이 없으면
            //    검정 경계 하나가 shadow 를 최대로 밀어 암부만 과도하게 들리며 이미지를 찢는다.
            let high = throughDensity(p975a)
            let hlMask = max(BasicToneModel.highlightMask(high), 0.3)
            // 초과분의 절반만 회수(전량 회수는 명부가 균일하게 눌려 부자연 — 복구는 보수적으로).
            // 회수 시작점 = sRGB 0.89(linear 0.75).
            d.highlight = clamp(-min(clipHigh, 0.05) * 4.0
                - max(0, high - 0.89) * 0.5 / (0.10 * hlMask), -1, 0)
            func throughHighlight(_ v: Double) -> Double { BasicToneModel.highlight(throughDensity(v), d.highlight) }
            // 섀도는 그 톤에서 슬라이더가 실제로 먹는 만큼(마스크)만 반응하고 초과분의 절반만 회수한다.
            // 예전엔 마스크를 하한(0.3)으로 나눠 역산해, 슬라이더가 거의 안 닿는 깊은 검정(흑백 프린트의
            // 검정·스캔 테두리)을 끌어올리려 최대치(0.8)로 밀었고 그 위의 중간 암부가 통째로 들렸다
            // (2026-10-15 실측: 흑백 7 장 중 5 장·컬러 19 장 중 8 장이 0.8, 하위 25% 지점 2 배 상승).
            let low = throughHighlight(pShadowA)
            d.shadow = clamp(min(clipLow, 0.05) * 4.0
                + max(0, 0.10 - low) * 0.5 / 0.10 * BasicToneModel.shadowLiftMask(low), 0, 0.8)
            func throughShadow(_ v: Double) -> Double { BasicToneModel.shadow(throughHighlight(v), d.shadow) }

            // ── 6. Whites/Blacks — 엔드포인트 스트레치. 목표: 확산 화이트 sRGB 0.956(linear 0.90) /
            //    블랙 포인트 sRGB 0.062(linear 0.005). 목표점 마스크가 작으면 하한 가드로 폭주 방지.
            let diffuseWhiteSRGB = srgbEncode(diffuseWhiteLinear)
            let blackPointSRGB = srgbEncode(blackPointLinear)
            let white = throughShadow(p995a)
            let whMask = max(BasicToneModel.whitesMask(white), 0.25)
            d.whites = clamp((diffuseWhiteSRGB - white) / (0.12 * whMask), -1, 1)
            if clipHigh > 0.001 { d.whites = min(d.whites, 0) }   // 이미 클리핑이면 더 밀지 않는다
            d.whites = min(d.whites, caps.whites)
            // 블랙 포인트는 헤이즈(들뜬 검정)를 내리는 방향이 주기능이다. 이미 깊은 검정(스캔
            // 프레임 경계 포함)을 목표점으로 **끌어올리면** 검정이 씻겨 이미지가 들뜬다(사용자
            // 증상). 상향 리프트는 소량으로 캡해 필름 페이퍼-블랙 느낌만 남기고, 하향(헤이즈 복구)은
            // 그대로 둔다.
            let black = BasicToneModel.whites(throughShadow(pBlackA), d.whites)
            let blMask = max(BasicToneModel.blacksMask(black, lifting: black < blackPointSRGB), 0.25)
            d.blacks = clamp((blackPointSRGB - black) / (0.06 * blMask), -1, 0.15)
            return d
        }

        // ── 7. 채널 한도 — 휘도 목표가 채도 높은 명부·중간톤의 최대 채널을 1 쪽으로 밀면(새로 안전 상한을
        //    넘는 표본 > ChannelHeadroom.allowance) 밝히는 몫을 거둔다. 내주는 순서는 흰색(백점을 클리핑 직전까지
        //    보내는 단계) → 장면 키(노출을 줄이고 모자란 중간톤은 농도가 채운다 — 가산 리프트는 채도 높은 화소의
        //    최대 채널을 휘도만큼만 올려 노출 이득보다 덜 민다, 노출은 channelExposureBudget 까지만) → 농도·대비
        //    리프트다. 그 뒤 흰색을 맞는 만큼 되돌린다. 각 한도는 이분법이다.
        var d = solve(ev, LiftCaps())
        guard !s.peakSamples.isEmpty else { return d }
        // 탐색은 노출을 줄이기만 하므로 지금 노출과 최대 리프트로 닿을 수 없는 표본은 미리 뺀다.
        let candidates = ChannelHeadroom.candidates(s.peakSamples, maxStops: max(ev, 0),
                                                    maxLift: ChannelHeadroom.maximumAutoLift)
        func fits(_ x: ToneDelta) -> Bool {
            ChannelHeadroom.inducedClipping(candidates, total: s.peakSamples.count, x, filmType: filmType)
                <= ChannelHeadroom.allowance
        }
        /// [0, upper] 에서 맞는 가장 큰 값(0 도 맞지 않으면 0). 9 회면 노출 3 스톱 구간에서 0.006 스톱,
        /// 흰색 1 구간에서 0.002 — 슬라이더 표시(0.01)보다 곱다.
        func largest(_ upper: Double, _ ok: (Double) -> Bool) -> Double {
            if ok(upper) { return upper }
            var low = 0.0, high = upper
            for _ in 0..<9 {
                let mid = 0.5 * (low + high)
                if ok(mid) { low = mid } else { high = mid }
            }
            return low
        }
        if !fits(d) {
            // 노출은 휘도만 본 값에서 channelExposureBudget 까지만 내준다(그 아래는 클리핑을 받아들인다).
            let floor = channelExposureFloor(luminanceExposure: ev)
            var caps = LiftCaps(whites: 0)
            if !fits(solve(ev, caps)) {
                if ev > floor, fits(solve(floor, caps)) {
                    ev = floor + largest(ev - floor) { fits(solve(floor + $0, caps)) }
                } else {
                    caps = LiftCaps(whites: 0, densityLift: 0, contrast: 0)
                    if ev > floor { ev = floor + largest(ev - floor) { fits(solve(floor + $0, caps)) } }
                    let densityUpper = max(0, -solve(ev, LiftCaps(whites: 0)).density)
                    caps.densityLift = largest(densityUpper) { value in
                        var trial = caps
                        trial.densityLift = value
                        return fits(solve(ev, trial))
                    }
                    let contrastUpper = max(0, solve(ev, LiftCaps(whites: 0, densityLift: caps.densityLift)).contrast)
                    caps.contrast = largest(contrastUpper) { value in
                        var trial = caps
                        trial.contrast = value
                        return fits(solve(ev, trial))
                    }
                }
            }
            let whitesUpper = max(0, solve(ev, LiftCaps(densityLift: caps.densityLift, contrast: caps.contrast)).whites)
            caps.whites = largest(whitesUpper) { value in
                var trial = caps
                trial.whites = value
                return fits(solve(ev, trial))
            }
            d = solve(ev, caps)
        }

        // Color controls belong to their own adjustment operation.
        // Retained result field for compatibility; tone does not propose color edits.
        d.vibrance = 0
        return d
    }

    // MARK: Auto Tone 폐루프

    /// 자동 톤 1 회 폐루프 보정. 첫 계산(autoTone)은 슬라이더 전달함수를 모형으로 역산하지만
    /// 사용자 커브·색 깊이·스캐너 타겟·기본톤 상호작용은 모형 밖이다(2026-10-14 실측: 사용자
    /// 커브 +0.6 이 있어도 같은 값을 냈고 결과만 어긋났다). 계산값을 실제로 적용해 다시 잰 통계로
    /// 장면 키(양방향)와 백점을 한 번 바로잡는다. 결정적이다.
    ///
    /// `neutral`(톤 슬라이더 0 의 중립 현상본 통계)을 주면 확인 렌더와 칸마다 맞대어 실제로 새로 날아간 채널을
    /// 센다 — 스캐너 타깃·사용자 커브처럼 첫 계산의 모형 밖 단계까지 거친 값이다. 그 비율이 채널 한도를 넘으면
    /// 키·백점 보정 대신 흰색 → 노출 순서로 첫 제안의 밝히는 몫을 거둔다(`withdrawChannels`). 넘지 않으면 키·백점
    /// 보정을 그대로 내고, 더 밝힌 몫이 넘치는지는 `closedLoopTone` 이 그려서 본다. `neutral` 이 없으면 잰 클리핑을
    /// 모두 이미 쓴 몫으로 보고 더 밝히는 몫을 모형으로 줄인다.
    public static func refineTone(_ delta: ToneDelta, measured s: ImageStats, neutral: ImageStats? = nil,
                                  filmType: FilmType = .colorNegative) -> ToneDelta {
        let induced = neutral.flatMap { ChannelHeadroom.measuredInducedClipping(neutral: $0, measured: s) }
        if let induced, induced > ChannelHeadroom.allowance, let neutral {
            return withdrawChannels(delta, neutral: neutral, measured: s, filmType: filmType)
        }
        var d = delta
        let hist = s.lumaHist
        func percentileSRGB(_ p: Double) -> Double {
            var acc = 0.0
            for i in 0..<256 { acc += hist[i]; if acc >= p { return Double(i) / 255 } }
            return 1
        }
        let p98 = srgbDecode(percentileSRGB(0.98))
        var p995s = percentileSRGB(0.995)
        let clipped = max(hist[255], s.clippedFraction) >= clipRecoveryThreshold

        // 장면 키: 잰 로그 평균과 키의 차이만큼 노출을 더하거나 뺀다. 밝힐 때는 명부 여유 안에서,
        // 실질 클리핑이 남아 있으면 더 밝히지 않는다.
        let measuredKey = s.logAverageLuminance
        var residual = log2(sceneKey(logAverage: measuredKey, highlight: srgbDecode(percentileSRGB(0.99)))
                            / max(measuredKey, 1e-4))
        if residual > 0 {
            residual = clipped ? 0 : min(residual, max(0, log2(0.95 / max(p98, 1e-4))))
        } else if !clipped {
            residual = max(residual, min(0, log2(whiteRecoveryFloor / max(srgbDecode(p995s), 1e-4))))
        }
        let refined = clamp(d.exposure + residual, -autoExposureLimit, autoExposureLimit)
        if abs(refined - d.exposure) > 0.02 {
            // 노출이 바뀌면 백점도 같이 움직인다 — 같은 연산자로 되돌린 뒤 다시 예측한다.
            let p995 = srgbDecode(p995s)
            let unexposed = ExposureShoulder.unexposedLuminance(p995, stops: d.exposure, filmType: filmType)
            p995s = srgbEncode(min(ExposureShoulder.exposedLuminance(unexposed, stops: refined,
                                                                     filmType: filmType), 1))
            d.exposure = refined
        }

        // 백점: 확산 화이트 목표(linear 0.90)에 남은 오차를 Whites 계수로 메운다.
        let residualWhite = srgbEncode(diffuseWhiteLinear) - p995s
        if induced == nil, clipped, d.whites > 0 {
            // 첫 제안이 실질 채널 클리핑(≥5%)을 만들었으면 흰색 리프트를 거둔다 — autoTone 의 "이미
            // 클리핑이면 흰색을 올리지 않는다"를 렌더 결과에 건다. 흰색은 휘도 p995 를 보므로 채도 높은
            // 명부의 최대 채널이 먼저 1 에 닿는다(2026-11-08 사용자 카탈로그: GT-X900_frame_26 흰색 +0.34 →
            // 채널 클리핑 16%, Kirstenbosch +0.48 → 15%, 흰색을 빼면 둘 다 0%).
            d.whites = 0
        } else if abs(residualWhite) > 0.01, max(hist[255], s.clippedFraction) <= 0.001 || residualWhite < 0 {
            let mask = max(smoothstep(0.68, 0.92, p995s), 0.25)
            d.whites = clamp(d.whites + residualWhite / (0.12 * mask), -1, 1)
        }

        // 채널(중립 현상본이 없을 때): 더 밝히는 몫(노출 증가·흰색 증가)이 잰 결과에서 새로 1 에 닿게 하는 화소는, 잰
        // 클리핑과 합쳐 ChannelHeadroom.allowance 안이어야 한다 — 잰 클리핑을 모두 이미 쓴 몫으로 본다(원본이 이미
        // 날아간 사진은 폐루프가 더 밝히지 않는다). 넘치면 두 증가분을 같은 비율로 줄인다.
        // 중립 현상본이 있으면 여기서 줄이지 않는다 — 모형은 스캐너 타깃이 명부를 누르는 몫을 모르고, 첫 제안이 중립과
        // 거의 같으면 확인 렌더로 바로잡을 정보도 없다(사용자 카탈로그: SP-3000 JPEG 노출 0.47 → 0.015, 실제로 새로
        // 날아간 칸은 0.01%). 대신 `closedLoopTone` 이 후보를 그려 넘치면 첫 제안과 후보 사이를 이분한다.
        let raiseEV = max(0, d.exposure - delta.exposure), raiseWhites = max(0, d.whites - delta.whites)
        if induced == nil, raiseEV > 0 || raiseWhites > 0, !s.peakSamples.isEmpty {
            let budget = max(0, ChannelHeadroom.allowance - s.clippedFraction)
            let candidates = ChannelHeadroom.candidates(s.peakSamples, maxStops: raiseEV, maxLift: 0.12 * raiseWhites)
            func extra(_ scale: Double) -> Double {
                ChannelHeadroom.additionalClipping(candidates, total: s.peakSamples.count,
                                                   stops: raiseEV * scale, whites: raiseWhites * scale)
            }
            if extra(1) > budget {
                var low = 0.0, high = 1.0
                for _ in 0..<9 {
                    let mid = 0.5 * (low + high)
                    if extra(mid) <= budget { low = mid } else { high = mid }
                }
                if raiseEV > 0 { d.exposure = delta.exposure + raiseEV * low }
                if raiseWhites > 0 { d.whites = delta.whites + raiseWhites * low }
            }
        }
        return d
    }

    /// A bounded rendering objective, not a claim about creative intent or measured color accuracy.
    /// 중간 오차는 로그 평균 휘도 대 그 장면의 키(sceneKey)다. `adjustMid` 가 false 면 중간을 보지 않는다.
    public static func toneScore(_ stats: ImageStats, adjustMid: Bool) -> Double {
        func p(_ fraction: Double) -> Double {
            var sum = 0.0
            for i in 0..<256 { sum += stats.lumaHist[i]; if sum >= fraction { return Double(i) / 255 } }
            return 1
        }
        let white = srgbDecode(p(0.995)), black = srgbDecode(p(0.02))
        let key = stats.logAverageLuminance
        let midError = adjustMid
            ? abs(log2(max(key, 1e-4) / sceneKey(logAverage: key, highlight: srgbDecode(p(0.99))))) : 0
        let whiteError = 0.25 * abs(log2(max(white, 1e-4) / diffuseWhiteLinear))
        let blackError = 0.25 * max(0, log2(max(black, 1e-4) / blackPointLinear))
        let flatness = 0.5 * max(0, 0.52 - (p(0.9) - p(0.1)))
        return midError + whiteError + blackError + flatness + 4 * stats.clippedFraction + 2 * stats.lumaHist[0]
    }

    public static func refinementDistance(_ first: ToneDelta, _ second: ToneDelta) -> Double {
        abs(first.exposure - second.exposure) + 0.5 * abs(first.whites - second.whites)
    }

    /// 채널 한도가 노출에서 거둘 수 있는 최대 몫(스톱). 그 아래로는 클리핑을 받아들인다 — 어두운 SP-3000 슬라이드의
    /// 채도 높은 등불(화소 1.7%)을 지키려 폐루프가 노출을 1.2 스톱 내려 장면 키가 2.5 스톱 어두워졌고, 사용자는 같은
    /// 사진을 1.35% 클리핑을 감수하고 밝게 맞췄다. 1 스톱 안에서 거둔 사진(GT-X900 포지티브 −0.96)은 사용자 보정에
    /// 더 가까웠다(2026-11-08 사용자 카탈로그 145장).
    public static let channelExposureBudget = 1.0

    /// 채널 한도가 노출을 내릴 수 있는 바닥: 휘도만 본 노출에서 channelExposureBudget 을 뺀 값, 다만 0 아래로는
    /// 내리지 않는다(휘도만 본 노출이 이미 음수면 그 값).
    static func channelExposureFloor(luminanceExposure ev: Double) -> Double {
        max(ev - channelExposureBudget, min(ev, 0))
    }

    /// 중립 현상본에서 채널을 보지 않고 푼 노출로 정한 바닥(폐루프용).
    static func channelExposureFloor(neutral: ImageStats, filmType: FilmType) -> Double {
        var luminanceOnly = neutral
        luminanceOnly.peakSamples = []
        return channelExposureFloor(luminanceExposure: autoTone(luminanceOnly, filmType: filmType).exposure)
    }

    /// 채널 한도가 폐루프 뒤에도 넘칠 때 더 그려 보는 최대 횟수. 이미 1 에 닿은 칸은 잰 값이 하한이라 모형 보정만으로는
    /// 덜 거둘 수 있다 — 고른 제안과 바닥 사이를 실제로 그려 이분한다(3 회면 그 구간의 1/8).
    public static let channelRefinementLimit = 3

    /// 자동 톤 폐루프 전체(앱과 감사가 같이 쓴다). `measured` 는 첫 제안을 그려 잰 통계, `measure` 는 제안을 실제로
    /// 그려 잰 통계(실패하면 nil)다. 순서: 키·백점 보정(또는 채널 거두기) 후보를 그려 `prefersCandidate` 로 고른다 →
    /// 중립 현상본이 있고 고른 결과에서도 새로 날아간 채널이 한도를 넘으면 고른 제안과 그 바닥(흰색·노출의 밝히는
    /// 몫을 뺀 값) 사이를 그려 이분해, 맞는 가장 밝은 점을 쓴다(맞는 점이 없으면 초과가 가장 적은 점).
    public static func closedLoopTone(_ first: ToneDelta, measured: ImageStats, neutral: ImageStats?,
                                      filmType: FilmType, measure: (ToneDelta) -> ImageStats?) -> ToneDelta {
        // 채널을 지키느라 어두워지는 몫의 바닥: 확인 렌더의 장면 키에서 남은 예산(1 스톱 − 첫 계산이 이미 내준 노출)
        // 만큼 아래. 노출이 아니라 잰 키로 거는 것은 스캐너 타깃의 톤 곡선이 노출 변화를 키워서다(SP-3000 슬라이드:
        // 노출 0.95 스톱에 키 2 스톱).
        let keyFloor = neutral.map {
            measured.logAverageLuminance * pow(2, -remainingKeyBudget(first: first, neutral: $0, filmType: filmType))
        } ?? 0
        var chosen = first, chosenStats = measured
        let candidate = refineTone(first, measured: measured, neutral: neutral, filmType: filmType)
        if refinementDistance(first, candidate) > 0.02, let checked = measure(candidate) {
            if let neutral, channelExcess(neutral: neutral, measured: measured) == 0,
               let excess = channelExcess(neutral: neutral, measured: checked), excess > 0 {
                // 더 밝힌 후보가 한도를 넘었다 — 첫 제안(맞음)과 후보 사이를 그려 맞는 가장 밝은 점을 찾고, 그 점을
                // 점수로 첫 제안과 견준다.
                if let (inside, insideStats) = bisectChannels(from: first, to: candidate, exceedingStats: checked,
                                                              neutral: neutral, keyFloor: keyFloor,
                                                              measure: measure).fit,
                   toneScore(insideStats, adjustMid: true) < toneScore(measured, adjustMid: true) {
                    chosen = inside; chosenStats = insideStats
                }
            } else if checked.logAverageLuminance >= keyFloor,
                      prefersCandidate(checked, over: measured, neutral: neutral) {
                chosen = candidate; chosenStats = checked
            }
        }
        guard let neutral, let excess = channelExcess(neutral: neutral, measured: chosenStats), excess > 0 else {
            return chosen
        }
        // 고른 결과도 넘친다 — 고른 제안과 그 바닥(흰색의 밝히는 몫을 빼고, 노출은 channelExposureFloor 까지) 사이를
        // 그려 이분한다. 키가 바닥보다 어두운 점은 고르지 않는다. 맞는 점이 없으면 초과가 가장 적은 점이다(그만큼은
        // 받아들인다).
        var bottom = chosen
        bottom.whites = min(chosen.whites, 0)
        bottom.exposure = min(chosen.exposure, max(min(chosen.exposure, 0),
                                                   channelExposureFloor(neutral: neutral, filmType: filmType)))
        guard refinementDistance(chosen, bottom) > 0.005 else { return chosen }
        let result = bisectChannels(from: bottom, to: chosen, exceedingStats: chosenStats, neutral: neutral,
                                    keyFloor: keyFloor, measure: measure)
        return result.fit?.delta ?? result.least.delta
    }

    /// 채널 한도가 폐루프에서 더 내줄 수 있는 장면 키(스톱): channelExposureBudget 에서 첫 계산이 휘도만 본 노출보다
    /// 이미 낮춘 몫을 뺀 값.
    static func remainingKeyBudget(first: ToneDelta, neutral: ImageStats, filmType: FilmType) -> Double {
        var luminanceOnly = neutral
        luminanceOnly.peakSamples = []
        let given = max(0, autoTone(luminanceOnly, filmType: filmType).exposure - first.exposure)
        return max(0, channelExposureBudget - given)
    }

    /// `fitting`(맞는다고 보는 끝)에서 `exceeding`(넘친다고 잰 끝)으로 가는 노출·흰색 선분을 그려 이분한다
    /// (`channelRefinementLimit` 회). 장면 키가 `keyFloor` 보다 어두운 점은 너무 어두운 것으로 보고 더 밝은 쪽을 찾는다.
    /// `fit` 은 맞는 가장 밝은 점, `least` 는 키 바닥을 지킨 잰 점 가운데 `prefersCandidate` 로 가장 나은 점(맞는 점이
    /// 없을 때 쓴다)이다.
    static func bisectChannels(from fitting: ToneDelta, to exceeding: ToneDelta, exceedingStats: ImageStats,
                               neutral: ImageStats, keyFloor: Double, measure: (ToneDelta) -> ImageStats?)
        -> (fit: (delta: ToneDelta, stats: ImageStats)?, least: (delta: ToneDelta, stats: ImageStats)) {
        var low = 0.0, high = 1.0
        var fit: (delta: ToneDelta, stats: ImageStats)?
        var least = (delta: exceeding, stats: exceedingStats)
        for _ in 0..<channelRefinementLimit {
            let t = 0.5 * (low + high)
            var trial = exceeding
            trial.whites = fitting.whites + (exceeding.whites - fitting.whites) * t
            trial.exposure = fitting.exposure + (exceeding.exposure - fitting.exposure) * t
            guard let checked = measure(trial) else { break }
            if checked.logAverageLuminance < keyFloor {
                low = t
            } else if channelExcess(neutral: neutral, measured: checked) == 0 {
                low = t; fit = (trial, checked)
            } else {
                high = t
                if prefersCandidate(checked, over: least.stats, neutral: neutral) { least = (trial, checked) }
            }
        }
        return (fit, least)
    }

    /// 확인 렌더에서 새로 날아간 채널이 한도를 넘었을 때: 흰색을 0(이미 음수면 그대로)까지, 그래도 넘치면 노출을
    /// `channelExposureFloor` 까지 맞는 만큼만 낮춘다. 예측은 확인 렌더의 칸별 잰 값으로 바로잡는다
    /// (`ChannelHeadroom.correctedInducedClipping`). 둘 다 바닥까지 내려도 넘치면 바닥 값이다 — 남는 것은
    /// 중립 현상본 위에 걸린 사용자 커브·타깃의 몫이라 자동 톤이 더 어둡게 할 일이 아니다.
    static func withdrawChannels(_ first: ToneDelta, neutral: ImageStats, measured: ImageStats,
                                 filmType: FilmType) -> ToneDelta {
        func fits(_ candidate: ToneDelta) -> Bool {
            ChannelHeadroom.correctedInducedClipping(neutral: neutral.peakSamples, measured: measured.peakSamples,
                                                     first: first, candidate: candidate, filmType: filmType)
                <= ChannelHeadroom.allowance
        }
        /// `from` 에서 `to` 쪽으로 가며 처음 맞는 값(이분법, 9 회). `to` 도 맞지 않으면 `to`.
        func lowered(_ from: Double, to floor: Double, _ apply: (Double) -> ToneDelta) -> Double {
            guard from > floor, !fits(apply(from)) else { return from }
            guard fits(apply(floor)) else { return floor }
            var high = from, low = floor
            for _ in 0..<9 {
                let mid = 0.5 * (low + high)
                if fits(apply(mid)) { low = mid } else { high = mid }
            }
            return low
        }
        var d = first
        d.whites = lowered(first.whites, to: min(first.whites, 0)) { value in
            var trial = d
            trial.whites = value
            return trial
        }
        let exposureFloor = min(first.exposure, max(min(first.exposure, 0),
                                                    channelExposureFloor(neutral: neutral, filmType: filmType)))
        d.exposure = lowered(first.exposure, to: exposureFloor) { value in
            var trial = d
            trial.exposure = value
            return trial
        }
        return d
    }

    /// 확인 렌더 둘 중 후보를 받을지. 중립 현상본이 있으면 채널 한도를 먼저 본다 — 새로 날아간 채널이 한도를
    /// 넘는 양이 적은 쪽이 낫고, 같으면 `toneScore` 가 정한다(제약을 먼저 지키고 그 안에서 목표를 본다).
    public static func prefersCandidate(_ candidate: ImageStats, over current: ImageStats,
                                        neutral: ImageStats?) -> Bool {
        if let neutral,
           let excessNow = channelExcess(neutral: neutral, measured: current),
           let excessCandidate = channelExcess(neutral: neutral, measured: candidate),
           abs(excessNow - excessCandidate) > 1e-9 {
            return excessCandidate < excessNow
        }
        return toneScore(candidate, adjustMid: true) < toneScore(current, adjustMid: true)
    }

    /// 새로 날아간 채널이 한도를 넘는 양(넘지 않으면 0). 두 그림이 맞지 않으면 nil.
    public static func channelExcess(neutral: ImageStats, measured: ImageStats) -> Double? {
        ChannelHeadroom.measuredInducedClipping(neutral: neutral, measured: measured)
            .map { (induced: Double) -> Double in max(0, induced - ChannelHeadroom.allowance) }
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
