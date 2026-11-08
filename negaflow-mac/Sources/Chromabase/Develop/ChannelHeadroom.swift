import CoreGraphics
import Foundation

/// 자동 톤이 노출·기본 톤을 거친 뒤 채널이 1 에 닿는 화소를 미리 센다.
///
/// 노출(`exposureShoulder`)은 휘도비로 RGB 를 함께 늘린다. 기본 톤(`basicTone`)은 입력을 `toneSafeUnitRGB` 로
/// [0,1] 에 넣고(휘도 유지, chroma 축소 — 최대 채널은 min(M, 1)), 휘도를 밝히면 세 채널에 같은 값을 더하고
/// 어둡히면 채널비를 지킨다(`withLuma`). 그래서 화소의 선형 휘도 Y 와 최대 채널 M 두 값으로 최종 최대 채널이
/// 정해진다:
///   노출 뒤  Yₑ = E(Y), Mₑ = M·Yₑ/Y
///   톤 뒤    Y' = T(Yₑ)(BasicToneModel), M' = Y' < Yₑ ? min(Mₑ, 1)·Y'/Yₑ : min(min(Mₑ, 1) + Y' − Yₑ, 1)
/// 기본 톤 뒤의 단계(사용자 커브·스캐너 타깃·후처리)는 모형 밖이라 폐루프(`AutoAdjust.closedLoopTone`)가 확인
/// 렌더를 중립 현상본과 화소마다 맞대어 다룬다. 어느 쪽이든 톤 뒤 휘도가 확산 화이트(`diffuseWhite`) 이하인
/// 화소만 센다.
///
/// 휘도만 보던 예전 한도(노출은 휘도 p98 ≤ 0.95, 흰색은 휘도 p99.5 → 0.90)는 채도 높은 명부의 최대 채널을
/// 보지 못했다. 사용자 카탈로그 398장에서 노출 이득이 채도 높은 중간톤을 1 위로 민 사진(GT-X900 포지티브
/// +1.25 스톱 → 2.8%)과 흰색 리프트가 밝은 색을 민 사진(L1020776 +0.27 → 3.7%, 흰색을 빼면 0%)이 나왔다
/// (2026-11-08).
enum ChannelHeadroom {
    /// 잰 클리핑의 기준(`SceneAnalysisSampler` 와 같다).
    static let clipLevel = 0.995
    /// 예측의 여유. 예측과 렌더의 차이는 움직인 양에 비례한다: 사용자 카탈로그 90장(MAIN)의 칸별 차이는 95%가
    /// 0.002, 최대 0.0073 이고, 합성 노랑 면(상승 0.19)은 0.009(상승의 4.7%)였다(2026-11-08). 통계가 8 비트라
    /// 명부 반 코드(0.0045)는 늘 남는다. 그래서 여유는 0.004 + 상승의 5%, 많아야 0.015 다. 고정 여유(0.015)를
    /// 쓰면 원본에서 이미 0.98~0.995 에 있던 화소가 조금만 올라도 세어져, 원본이 날아간 JPEG 의 노출을 통째로
    /// 막았다(L1020777: 노출 0.47 → 0, 실제로 새로 날아간 칸은 0.01%).
    static let marginFloor = 0.004
    static let marginPerRise = 0.05
    static let maximumMargin = 0.015
    /// 세어질 수 있는 가장 낮은 값(최대 여유를 뺀 클리핑 기준). 미리 거르기의 경계다.
    static let safeLevel = clipLevel - maximumMargin
    /// 보호하는 휘도의 위 끝 — 자동 톤의 확산 화이트(백점 목표, 선형 0.90). 톤 뒤 휘도가 이보다 낮은데 채널이 1 에
    /// 닿는 화소는 채도 높은 색이 날아간 것이다. 휘도가 그 위인 화소는 반사광·광원이라 백점 목표가 이미 확산 화이트
    /// 위에 두는 몫이고 날아가도 된다 — 세면 어두운 장면의 등불 1.7% 를 지키려 노출을 2.75 스톱 내렸다(사용자 카탈로그
    /// SP-3000 슬라이드, 2026-11-08).
    static let diffuseWhite = AutoAdjust.diffuseWhiteLinear
    /// 8 비트 인코딩 휘도로 본 확산 화이트(이 코드 이하가 보호 대상).
    static let diffuseWhiteCode = UInt8((AutoAdjust.srgbEncode(diffuseWhite) * 255).rounded(.down))
    /// 자동 톤이 새로 만들어도 되는 채널 클리핑 비율. 백점 목표가 휘도 p99.5 라 상위 0.5% 는 확산 화이트를
    /// 넘어 반사광·광원으로 1 에 닿아도 된다 — 채널에도 같은 몫만 허용한다.
    static let allowance = 0.005

    /// 표본 하나(선형 휘도, 최대 채널).
    static func sample(_ p: SIMD3<Double>) -> SIMD2<Double> {
        let r = max(0, p.x), g = max(0, p.y), b = max(0, p.z)
        return SIMD2(0.2126 * r + 0.7152 * g + 0.0722 * b, max(r, max(g, b)))
    }

    /// 자동 톤의 기본 톤이 인코딩 휘도에 더할 수 있는 최대 몫: 대비 +0.55(0.07) + 농도 −0.4(0.04) + 암부 0.8(0.08)
    /// + 흰색 +1(0.12) + 검정 +0.15(0.009). 명부는 자동이 올리지 않는다.
    static let maximumAutoLift = 0.32

    /// 노출 ≤ `maxStops`, 인코딩 리프트 ≤ `maxLift` 로는 safeLevel 에 못 닿는 표본을 미리 뺀다(결과는 같고 셀 표본만
    /// 줄어든다). 숄더는 휘도를 접기만 하고 가산 리프트의 선형 몫은 휘도가 높을수록 크므로, 선형 이득과 그 휘도의
    /// 리프트로 잡은 값이 상한이다.
    static func candidates(_ samples: [SIMD2<Double>], maxStops: Double, maxLift: Double) -> [SIMD2<Double>] {
        let gain = pow(2, maxStops)
        return samples.filter { s in
            guard s.y < clipLevel else { return false }
            let y = min(s.x * gain, 1)
            let lifted = AutoAdjust.srgbDecode(min(AutoAdjust.srgbEncode(y) + maxLift, 1))
            return min(min(s.y * gain, 1) + lifted - y, 1) >= safeLevel
        }
    }

    /// 표본 하나의 노출·기본 톤 뒤 최대 채널.
    static func predictedPeak(_ s: SIMD2<Double>, _ d: AutoAdjust.ToneDelta, filmType: FilmType) -> Double {
        predictedPeak(s, d, gain: pow(2, d.exposure),
                      blend: d.exposure > 0 ? ExposureShoulder.blend(stops: d.exposure, filmType: filmType) : 0)
    }

    private static func predictedPeak(_ s: SIMD2<Double>, _ d: AutoAdjust.ToneDelta, gain: Double, blend: Double) -> Double {
        predicted(s, d, gain: gain, blend: blend).peak
    }

    /// 표본 하나의 노출·기본 톤 뒤 (최대 채널, 휘도). `withLuma` 는 휘도를 목표값에 둔다.
    private static func predicted(_ s: SIMD2<Double>, _ d: AutoAdjust.ToneDelta, gain: Double,
                                  blend: Double) -> (peak: Double, luma: Double) {
        let exposed = ExposureShoulder.exposedLuminance(s.x, gain: gain, blend: blend)
        let peak = s.x > 1e-9 ? s.y * exposed / s.x : 0
        let y = min(max(exposed, 0), 1)
        let toned = AutoAdjust.srgbDecode(BasicToneModel.apply(
            AutoAdjust.srgbEncode(y), contrast: d.contrast, density: d.density, highlight: d.highlight,
            shadow: d.shadow, whites: d.whites, blacks: d.blacks))
        return (finalPeak(min(peak, 1), from: y, to: toned), toned)
    }

    private static func exposure(_ d: AutoAdjust.ToneDelta, _ filmType: FilmType) -> (gain: Double, blend: Double) {
        (pow(2, d.exposure), d.exposure > 0 ? ExposureShoulder.blend(stops: d.exposure, filmType: filmType) : 0)
    }

    /// 중립 현상본에서 1 에 닿지 않던 채널이 `d` 의 노출·기본 톤으로 올라 여유를 둔 클리핑 기준을 넘는 표본 비율.
    /// `samples` 는 `candidates` 로 거른 표본이어도 되고, 분모 `total` 은 전체 표본 수다.
    static func inducedClipping(_ samples: [SIMD2<Double>], total: Int, _ d: AutoAdjust.ToneDelta,
                                filmType: FilmType) -> Double {
        guard total > 0 else { return 0 }
        let (gain, blend) = exposure(d, filmType)
        var count = 0
        for s in samples where s.y < clipLevel {
            let after = predicted(s, d, gain: gain, blend: blend)
            if after.luma < diffuseWhite, pushedPast(s.y, after.peak) { count += 1 }
        }
        return Double(count) / Double(total)
    }

    /// 이미 렌더한 결과에 노출 `stops` 와 흰색 `whites` 를 더 얹을 때 새로 여유를 둔 클리핑 기준을 넘는 표본 비율. 폐루프가
    /// 더 밝히는 몫에만 쓴다 — 노출은 숄더 없이 선형 이득으로 본다(밝은 화소를 덜 접으므로 보수적이다).
    static func additionalClipping(_ samples: [SIMD2<Double>], total: Int, stops: Double, whites: Double) -> Double {
        guard total > 0 else { return 0 }
        let gain = pow(2, stops)
        var count = 0
        for s in samples where s.y < clipLevel {
            let y = min(s.x * gain, 1)
            let toned = AutoAdjust.srgbDecode(min(max(BasicToneModel.whites(AutoAdjust.srgbEncode(y), whites), 0), 1))
            if toned < diffuseWhite, pushedPast(s.y, finalPeak(min(s.y * gain, 1), from: y, to: toned)) { count += 1 }
        }
        return Double(count) / Double(total)
    }

    /// 올라서 여유를 둔 클리핑 기준을 넘었는가.
    private static func pushedPast(_ before: Double, _ after: Double) -> Bool {
        after > before + 1e-6 && after + margin(rise: after - before) >= clipLevel
    }

    static func margin(rise: Double) -> Double { min(maximumMargin, marginFloor + marginPerRise * max(rise, 0)) }

    /// `before` 에서 올라 세어지지 않는 가장 높은 값.
    static func ceiling(above before: Double) -> Double {
        let unbounded = (clipLevel - marginFloor + marginPerRise * before) / (1 + marginPerRise)
        return unbounded - before >= (maximumMargin - marginFloor) / marginPerRise ? safeLevel : unbounded
    }

    // MARK: 폐루프 — 중립 현상본과 확인 렌더를 칸마다 맞대어 본다

    /// 중립 현상본에서 255 가 아니던 화소 중 확인 렌더에서 어느 채널이든 255 인 화소의 비율 — 타깃·커브·후처리까지
    /// 거친 실제 결과다. 두 그림에 화소 표본이 없거나 크기가 다르면 칸으로 센다(`measuredInducedClipping(neutral:measured:)`
    /// 의 표본판). 그것도 맞지 않으면 nil.
    static func measuredInducedClipping(neutral: AutoAdjust.ImageStats, measured: AutoAdjust.ImageStats) -> Double? {
        if !neutral.pixelPeaks.isEmpty, neutral.pixelPeaks.count == measured.pixelPeaks.count,
           measured.pixelLuma.count == measured.pixelPeaks.count {
            var count = 0
            for i in neutral.pixelPeaks.indices
            where neutral.pixelPeaks[i] < 255 && measured.pixelPeaks[i] == 255 && measured.pixelLuma[i] <= diffuseWhiteCode {
                count += 1
            }
            return Double(count) / Double(neutral.pixelPeaks.count)
        }
        return measuredInducedClipping(neutral: neutral.peakSamples, measured: measured.peakSamples)
    }

    /// 8 비트 sRGB 로 그린 화소마다 (가장 큰 채널 코드, 인코딩 휘도 코드). 휘도 코드는 가장 큰 채널이 255 인 화소에만
    /// 채우고 나머지는 0 이다. 투명한 곳(원근 보정의 빈 곳)은 0 이다.
    static func pixelPeaks(_ cg: CGImage) -> (peaks: [UInt8], luma: [UInt8]) {
        let width = cg.width, height = cg.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return ([], []) }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return ([], []) }
        let decode = (0..<256).map { AutoAdjust.srgbDecode(Double($0) / 255) }
        var peaks = [UInt8](repeating: 0, count: width * height)
        var luma = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = rgba[4 * i], g = rgba[4 * i + 1], b = rgba[4 * i + 2]
            let peak = max(r, max(g, b))
            peaks[i] = peak
            // 휘도는 255 에 닿은 화소에서만 본다(확산 화이트 판정) — 나머지는 계산하지 않는다.
            guard peak == 255 else { continue }
            let y = 0.2126 * decode[Int(r)] + 0.7152 * decode[Int(g)] + 0.0722 * decode[Int(b)]
            luma[i] = UInt8(min(255, max(0, (AutoAdjust.srgbEncode(y) * 255).rounded())))
        }
        return (peaks, luma)
    }

    /// 중립 현상본에서 닿지 않던 칸 중 확인 렌더에서 1 에 닿은 칸의 비율. 두 표본의 칸 수가 다르면 nil.
    static func measuredInducedClipping(neutral: [SIMD2<Double>], measured: [SIMD2<Double>]) -> Double? {
        guard !neutral.isEmpty, neutral.count == measured.count else { return nil }
        var count = 0
        for (n, m) in zip(neutral, measured) where n.y < clipLevel && m.y >= clipLevel && m.x < diffuseWhite { count += 1 }
        return Double(count) / Double(neutral.count)
    }

    /// 확인 렌더로 바로잡은 예측. 통계는 모형 밖 단계(스캐너 타깃·사용자 커브·후처리)까지 거친 값이라, 그 단계가
    /// 칸마다 더하는 몫은 중립 현상본에서 정의상 0 이고 첫 제안에서 잰 값 − 예측이다. 그 사이는 예측이 중립에서
    /// 움직인 양에 비례한다고 보고 후보에 더한다. 첫 제안에서 이미 1 에 닿은 칸은 잰 값이 1 에 묶여 그 몫이
    /// 하한이라 한 번에 덜 거둘 수 있다 — 호출 쪽이 다시 그려 잰 값으로 한두 번 더 거둔다. 여유는 첫 제안에서
    /// 예측이 움직인 만큼이다.
    static func correctedInducedClipping(neutral: [SIMD2<Double>], measured: [SIMD2<Double>],
                                         first: AutoAdjust.ToneDelta, candidate: AutoAdjust.ToneDelta,
                                         filmType: FilmType) -> Double {
        guard !neutral.isEmpty, neutral.count == measured.count else { return 0 }
        var count = 0
        let (firstGain, firstBlend) = exposure(first, filmType)
        let (candidateGain, candidateBlend) = exposure(candidate, filmType)
        for (n, m) in zip(neutral, measured) where n.y < clipLevel {
            let atFirst = predicted(n, first, gain: firstGain, blend: firstBlend)
            let atCandidate = predicted(n, candidate, gain: candidateGain, blend: candidateBlend)
            let reach = atFirst.peak - n.y
            let share = abs(reach) > 1e-6 ? min(max((atCandidate.peak - n.y) / reach, 0), 1) : 1
            let corrected = atCandidate.peak + (m.y - atFirst.peak) * share
            let luma = atCandidate.luma + (m.x - atFirst.luma) * share
            if luma < diffuseWhite, corrected + margin(rise: abs(atCandidate.peak - atFirst.peak)) >= clipLevel {
                count += 1
            }
        }
        return Double(count) / Double(neutral.count)
    }

    /// `withLuma` 의 최대 채널: 어둡히면 채널비, 밝히면 같은 값을 더하고 1 에서 멈춘다.
    private static func finalPeak(_ peak: Double, from y: Double, to toned: Double) -> Double {
        toned < y && y > 1e-6 ? peak * toned / y : min(peak + toned - y, 1)
    }
}
