import Foundation
import CoreImage
import CoreGraphics

// Common luminance endpoints preserve RGB ratios; no per-channel white balance.
public enum AutoLevels {
    /// 이미지의 실제 데이터 범위를 자동 검출하여 0~1 선형으로 스트레치.
    /// - Parameters:
    ///   - blackClip: 블랙포인트로 사용할 하위 백분위(기본 0.5%)
    ///   - whiteClip: 화이트포인트로 사용할 상위 백분위(기본 0.1%)
    public static func apply(to image: CIImage,
                             blackClip: Double = 0.005,
                             whiteClip: Double = 0.001,
                             sampleColorSpace: CGColorSpace? = nil,
                             outputWhite outputWhiteOverride: Double? = nil,
                             outputBlack: Double = 0.0) -> CIImage {
        var points: Points?
        return apply(to: image, blackClip: blackClip, whiteClip: whiteClip,
                     sampleColorSpace: sampleColorSpace,
                     outputWhite: outputWhiteOverride, outputBlack: outputBlack,
                     points: &points)
    }

    /// 검출한 끝점 한 쌍. 인스펙터 값이 걸리기 전 이미지에서 나오므로 슬라이더와 무관하다.
    struct Points: Sendable, Equatable {
        var black: SIMD3<Double>
        var white: SIMD3<Double>
    }

    /// 이미 검출한 끝점이 있으면 다시 재지 않는 변형(DevelopSceneMeasurements).
    static func apply(to image: CIImage,
                      blackClip: Double = 0.005,
                      whiteClip: Double = 0.001,
                      sampleColorSpace: CGColorSpace? = nil,
                      outputWhite outputWhiteOverride: Double? = nil,
                      outputBlack: Double = 0.0,
                      region: AnalysisRegion? = nil,
                      sceneLinearOutput: Bool = false,
                      points cachedPoints: inout Points?) -> CIImage {
        // 샘플링을 위해 작은 영역으로 축소(CIAreaAverage 로는 히스토그램이 안 나옴).
        // 대신 작은 축소본을 렌더링해서 픽셀을 직접 읽는다.
        let measured: Points
        if let cached = cachedPoints {
            measured = cached
        } else if let sampled = sampleBlackWhite(
            AnalysisRegion.measurementImage(image, region: region),
            blackClip: blackClip,
            whiteClip: whiteClip,
            sampleColorSpace: sampleColorSpace,
            insetFraction: region == nil ? frameBorderInset : 0
        ) {
            measured = Points(black: sampled.black, white: sampled.white)
            cachedPoints = measured
        } else {
            return image   // 샘플링 실패 시 원본 반환(무해)
        }
        let black = measured.black.x, white = measured.white.x
        let minimumRange = sceneLinearOutput ? 0.04 * white : 0.04
        guard white > 1e-5, white - black >= minimumRange else { return image }
        if !sceneLinearOutput, white > 0.95, white < 1.05, black < 0.05 { return image }
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)
        let outputWhite = outputWhiteOverride ?? (sampleColorSpace?.name == linear?.name ? 0.70 : 0.88)
        let scale = (outputWhite - outputBlack) / (white - black)
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "luminanceLevels") else { return image }
        return kernel.apply(extent: image.extent, arguments: [image, scale, outputBlack - black * scale]) ?? image
    }

    /// 크롭 영역이 없을 때 버리는 프레임 가장자리 비율 — 반전 측정(NegativeInversion.sampleStats)과
    /// 같다. 예전에는 전체 프레임을 재서 홀더·백라이트가 화이트/블랙포인트가 됐다(2026-10-14 실측
    /// 디카 스캔 R/B 0.90 캐스트).
    static let frameBorderInset = 0.06

    /// 작은 축소본을 렌더링해서 휘도 black/white 포인트(p백분위) 검출.
    static func sampleBlackWhite(_ image: CIImage,
                                 blackClip: Double,
                                 whiteClip: Double,
                                 sampleColorSpace: CGColorSpace? = nil,
                                 insetFraction: Double = 0)
        -> (black: SIMD3<Double>, white: SIMD3<Double>)? {
        guard let grid = SceneAnalysisSampler.sample(image, longEdge: 256, inset: insetFraction) else { return nil }
        var luminances = grid.pixels.map { 0.2126 * $0.x + 0.7152 * $0.y + 0.0722 * $0.z }
        luminances.sort()
        func percentile(_ fraction: Double) -> Double {
            luminances[min(luminances.count - 1, max(0, Int(Double(luminances.count) * fraction)))]
        }
        return (SIMD3(repeating: percentile(blackClip)), SIMD3(repeating: percentile(1 - whiteClip)))
    }
}
