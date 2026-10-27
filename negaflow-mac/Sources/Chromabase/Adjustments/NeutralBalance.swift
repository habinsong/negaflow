import Foundation
import CoreImage
import CoreGraphics

// MARK: - NeutralBalance (자동 색상)
//
// 반전 뒤에 남은 캐스트를 장면의 **중립축 증거**(NeutralAxisEvidence)로 걷는다.
//
// 2026-10-14 재설계(실측 결함):
//  • 예전에는 전체 화소의 채널 중앙값을 목표로 채널별 감마(0·1 고정)를 걸었다. 감마는 균일한
//    캐스트(광원·WB 성분)를 고치지 못하고 교차 캐스트로 바꿨다 — R/B 0.667 의 균일 캐스트가
//    암부 +0.30 스톱 과보정, 명부 −0.49 스톱 미보정. 0·1 고정은 화이트가 0.70 인 이 파이프라인에서
//    명부 중립도 깼다. 전체 중앙값은 지배색 장면(숲·노을)을 무채색으로 끌었다.
//  • 이제 중립에 가까운 화소만 휘도대별로 모아, 채널마다 ln c = α + β·ln Ȳ 를 대역 중앙값에 맞춘다
//    (대역마다 한 표). 균일 캐스트는 α(게인), 중간톤 휨은 β(감마)로 잡히고, 보정 c' = exp((ln c − α)/β)
//    는 맞춘 중립축을 뒤집는다. 대역 수·휘도 폭이 부족하거나 분리한 대역에서 예측이 나빠지면
//    β 를 1 로 두고 게인만 쓴다. 자동 레벨과 무관하게 혼자 돌아도 된다.
//  • 적용은 정확한 Metal 커널(channelPowerGain) — 예전 32³ 큐브는 암부 거듭제곱을 양자화했다.
public enum NeutralBalance {
    /// 맞춘 중립축: 채널마다 ln c = offset + slope·ln Ȳ. 항등은 offset 0, slope 1.
    public struct Correction: Sendable, Equatable {
        public var offset: SIMD3<Double>
        public var slope: SIMD3<Double>
        public static let identity = Correction(offset: .zero, slope: SIMD3(repeating: 1))

        var isIdentity: Bool {
            let s = slope - SIMD3(repeating: 1)
            return [offset.x, offset.y, offset.z, s.x, s.y, s.z].allSatisfy { Swift.abs($0) < 0.003 }
        }
    }

    /// 한 채널 보정의 상한 — 게인 ±1 스톱(ln 0.7), 감마 0.8…1.25.
    static let maximumOffset = 0.7
    static let slopeRange = 0.8...1.25
    /// 기울기 후보의 최소 범위. 별도 대역 검증도 통과해야 한다.
    static let minimumBandsForSlope = 3
    static let minimumSpanForSlope = log(4.0)

    public static func apply(to image: CIImage,
                             sampleColorSpace: CGColorSpace? = nil,
                             strength: Double = 1.0) -> CIImage {
        var correction: Correction?
        return apply(to: image, sampleColorSpace: sampleColorSpace,
                     strength: strength, correction: &correction)
    }

    /// 이미 맞춘 보정이 있으면 다시 재지 않는 변형(DevelopSceneMeasurements). 근거가 없으면
    /// 항등을 기록해 슬라이더를 움직이는 동안 다시 재지 않는다.
    static func apply(to image: CIImage,
                      sampleColorSpace: CGColorSpace? = nil,
                      strength: Double = 1.0,
                      region: AnalysisRegion? = nil,
                      correction cachedCorrection: inout Correction?) -> CIImage {
        let correction = cachedCorrection ?? measure(
            AnalysisRegion.measurementImage(image, region: region),
            sampleColorSpace: sampleColorSpace,
            insetFraction: region == nil ? AutoLevels.frameBorderInset : 0,
            strength: strength
        )
        cachedCorrection = correction
        guard !correction.isIdentity,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "channelPowerGain") else { return image }
        // c' = exp((ln c − α)/β) = exp(−α/β) · c^(1/β)
        let exponent = SIMD3<Double>(repeating: 1) / correction.slope
        let gain = SIMD3(exp(-correction.offset.x * exponent.x),
                         exp(-correction.offset.y * exponent.y),
                         exp(-correction.offset.z * exponent.z))
        return kernel.apply(extent: image.extent, arguments: [
            image,
            CIVector(x: CGFloat(exponent.x), y: CGFloat(exponent.y), z: CGFloat(exponent.z)),
            CIVector(x: CGFloat(gain.x), y: CGFloat(gain.y), z: CGFloat(gain.z)),
        ])?.cropped(to: image.extent) ?? image
    }

    static func measure(_ image: CIImage, sampleColorSpace: CGColorSpace?,
                        insetFraction: Double, strength: Double) -> Correction {
        guard let pixels = samplePixels(image, sampleColorSpace: sampleColorSpace, insetFraction: insetFraction),
              let evidence = NeutralAxisEstimator.measure(pixels) else { return .identity }
        let applied = min(max(strength, 0), 1) * evidence.confidence
        return fit(evidence, strength: applied)
    }

    /// 대역 중앙 캐스트에 채널별 직선(cast = a + b·ln Ȳ)을 맞춘다 — 대역마다 같은 무게.
    static func fit(_ evidence: NeutralAxisEvidence, strength: Double) -> Correction {
        let bands = evidence.bands
        let xs = bands.map(\.logLuminance)
        let span = (xs.max() ?? 0) - (xs.min() ?? 0)
        let useSlope = bands.count >= minimumBandsForSlope && span >= minimumSpanForSlope && slopeImprovesHoldout(bands)
        func line(_ ys: [Double]) -> (a: Double, b: Double) {
            let n = Double(ys.count)
            let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
            guard useSlope else { return (my, 0) }
            var sxy = 0.0, sxx = 0.0
            for (x, y) in zip(xs, ys) { sxy += (x - mx) * (y - my); sxx += (x - mx) * (x - mx) }
            let b = sxx > 1e-12 ? sxy / sxx : 0
            return (my - b * mx, b)
        }
        let r = line(bands.map(\.cast.x)), g = line(bands.map(\.cast.y)), b = line(bands.map(\.cast.z))
        func clampOffset(_ v: Double) -> Double { min(max(v * strength, -maximumOffset), maximumOffset) }
        func clampSlope(_ v: Double) -> Double {
            min(max(1 + v * strength, slopeRange.lowerBound), slopeRange.upperBound)
        }
        return Correction(offset: SIMD3(clampOffset(r.a), clampOffset(g.a), clampOffset(b.a)),
                          slope: SIMD3(clampSlope(r.b), clampSlope(g.b), clampSlope(b.b)))
    }

    /// Fit even bands and validate odd bands before adding channel-dependent slopes.
    private static func slopeImprovesHoldout(_ bands: [NeutralAxisEvidence.Band]) -> Bool {
        guard bands.count >= 4 else { return false }
        let train = bands.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let holdout = bands.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        let mx = train.map(\.logLuminance).reduce(0, +) / Double(train.count)
        let my = train.map(\.cast).reduce(.zero, +) / Double(train.count)
        var sxx = 0.0, sxy = SIMD3<Double>(repeating: 0)
        for p in train { sxx += pow(p.logLuminance - mx, 2); sxy += (p.logLuminance - mx) * (p.cast - my) }
        guard sxx > 1e-12 else { return false }
        let b = sxy / sxx, a = my - b * mx
        var before = 0.0, after = 0.0
        for p in holdout {
            let residual = p.cast - a - b * p.logLuminance
            before += p.cast.x * p.cast.x + p.cast.y * p.cast.y + p.cast.z * p.cast.z
            after += residual.x * residual.x + residual.y * residual.y + residual.z * residual.z
        }
        return before > 1e-8 && after < before * 0.8
    }

    /// 긴 변이 최대 192인 linear 표본(가장자리 인셋 제외).
    static func samplePixels(_ image: CIImage, sampleColorSpace: CGColorSpace?,
                             insetFraction: Double) -> [SIMD3<Double>]? {
        SceneAnalysisSampler.sample(image, longEdge: 192, inset: insetFraction)?.pixels
    }
}
