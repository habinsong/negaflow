import CoreGraphics
import CoreImage
import Foundation

// MARK: - ColorProcessProbe
//
// 컬러 프로세스(자동 베이스 → 반전 → EXPIRED)가 **한 파일에서 무엇을 보고 무엇을 정했는지**
// 를 숫자로 남기는 진단 창구다. Windows 의 `--auto-base-probe` / `--rescue-probe` 와 같은
// 항목을 같은 이름으로 낸다(두 판본의 보고를 그대로 맞대어 볼 수 있게).
//
// ⚠️ 이 값으로 정상/비정상을 가르지 말 것. 여기서 도는 것은 반전까지이고 앱은 그 뒤에 자동
// 색상·자동 레벨·타겟 그레이드를 건다. 진짜로 어두운 장면과 결함을 절대 밝기로는 구분할 수
// 없다(2026-09-01 Windows 보고에서 실제로 이 함정에 빠졌다). **같은 파일의 앞뒤 비교**와
// **채널 사이 관계**에만 쓴다.
public enum ColorProcessProbe {
    /// 채널 평균/색 벌어짐을 재는 축소본 폭. 평균은 축소에 불변이고, 69 Mpx 원본을 float 로
    /// 통째로 올리면 기가바이트 단위가 된다.
    static let statisticsWidth = 512

    public struct AutoBaseReport: Sendable {
        public let width: Int
        public let height: Int
        public let source: String
        public let dmin: SIMD3<Double>
        /// 고른 베이스보다 밝은 필름 화소의 비율. 필름에 베이스보다 밝은 것은 없으므로
        /// 이 값이 크다는 것은 고른 값이 베이스가 아니라는 뜻이다.
        public let brighterThanBase: Double
        /// 리베이트 띠에서 다시 재어 값을 바꿨는가.
        public let rebateRescued: Bool
        public let method: String?
        public let evidenceScore: Double?
        public let sampledPixelCount: Int?
        public let anomalies: [String]
        public let microseconds: Int
    }

    public struct RescueReport: Sendable {
        public let width: Int
        public let height: Int
        public let dmin: SIMD3<Double>
        public let dmaxNormalized: SIMD3<Double>
        public let applied: Bool
        public let eligibleBands: Int
        public let coveredTiles: Int
        public let trainingSamples: Int
        public let holdoutSamples: Int
        public let spreadBefore: Double
        public let spreadAfter: Double
        public let meanBefore: SIMD3<Double>
        public let meanAfter: SIMD3<Double>
    }

    /// 자동 베이스가 무엇을 골랐는지.
    public static func autoBase(for image: CIImage, filmType: FilmType) -> AutoBaseReport? {
        let extent = image.extent.integral
        let neutralBase = filmType == .bwNegative
        let started = DispatchTime.now().uptimeNanoseconds
        guard let base = ChromabaseEngine.estimateBaseWithChromogenicFallback(
            from: image, neutralBase: neutralBase
        ) else { return nil }
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        let brighter = FilmBaseSampleGrid(image: image).map {
            FilmBaseRebate.brighterThanBaseFraction(grid: $0, dmin: base.rgb)
        } ?? 0
        let diagnostics = base.measurementDiagnostics
        return AutoBaseReport(
            width: Int(extent.width),
            height: Int(extent.height),
            source: base.source.rawValue,
            dmin: base.rgb,
            brighterThanBase: brighter,
            rebateRescued: diagnostics?.method == .rebateBand,
            method: diagnostics?.method.rawValue,
            evidenceScore: diagnostics?.evidenceScore,
            sampledPixelCount: diagnostics?.sampledPixelCount,
            anomalies: diagnostics?.anomalies.map(\.rawValue) ?? [],
            microseconds: Int(elapsed / 1000)
        )
    }

    /// 자동 베이스로 반전한 뒤 EXPIRED 를 걸고, 그 앞뒤를 잰다.
    /// - Parameter dminOverride: 베이스를 손으로 넣어 본다 — "어두운 것이 베이스 탓인가" 가
    ///   다른 베이스로 한 번 반전해 보면 그 자리에서 갈린다.
    public static func rescue(
        for image: CIImage,
        filmType: FilmType,
        dminOverride: SIMD3<Double>? = nil
    ) -> RescueReport? {
        let extent = image.extent.integral
        let neutralBase = filmType == .bwNegative
        let base: FilmBase
        if let dminOverride {
            base = FilmBase(rgb: dminOverride, source: .manual)
        } else if let estimated = ChromabaseEngine.estimateBaseWithChromogenicFallback(
            from: image, neutralBase: neutralBase
        ) {
            base = estimated
        } else {
            return nil
        }
        let stats = NegativeInversion.sampleStats(image, base: base, filmType: filmType)
            ?? NegativeInversion.fallbackStats(base: base, filmType: filmType)
        let developed = NegativeInversion.applySceneRanged(
            to: image, base: base, filmType: filmType
        )
        guard let linear = CGColorSpace(name: CGColorSpace.linearSRGB),
              let before = statistics(of: developed) else { return nil }

        let recovery = RescueGrade.measureRecovery(
            in: developed,
            sampleColorSpace: linear,
            alignChannels: filmType == .colorNegative || filmType == .colorPositive
        )
        let graded = RescueGrade.apply(
            to: developed, sampleColorSpace: linear, filmType: filmType, recoverRange: false
        )
        guard let after = statistics(of: graded) else { return nil }
        return RescueReport(
            width: Int(extent.width),
            height: Int(extent.height),
            dmin: stats.dmin,
            dmaxNormalized: stats.dmaxNorm,
            applied: recovery.isEligible,
            eligibleBands: recovery.eligibleBandCount,
            coveredTiles: recovery.coveredTileCount,
            trainingSamples: recovery.trainingSampleCount,
            holdoutSamples: recovery.holdoutSampleCount,
            spreadBefore: before.spread,
            spreadAfter: after.spread,
            meanBefore: before.mean,
            meanAfter: after.mean
        )
    }

    /// 채널 평균과 색 벌어짐(화소별 max−min 의 평균). 캐스트가 걷히면 벌어짐이 내려간다.
    static func statistics(of image: CIImage) -> (mean: SIMD3<Double>, spread: Double)? {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0,
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        let width = max(1, min(statisticsWidth, Int(extent.width)))
        let scale = Double(width) / Double(extent.width)
        let height = max(1, Int(Double(extent.height) * scale))
        let normalized = image.transformed(by: CGAffineTransform(
            translationX: -extent.minX, y: -extent.minY
        ))
        let scaled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var bitmap = [Float](repeating: 0, count: width * height * 4)
        SamplingContextPool.context(workingColorSpace: linear).render(
            scaled,
            toBitmap: &bitmap,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        var sum = SIMD3<Double>(repeating: 0)
        var spread = 0.0
        let count = width * height
        for index in 0..<count {
            let rgb = SIMD3(
                Double(bitmap[index * 4]),
                Double(bitmap[index * 4 + 1]),
                Double(bitmap[index * 4 + 2])
            )
            sum += rgb
            spread += max(rgb.x, max(rgb.y, rgb.z)) - min(rgb.x, min(rgb.y, rgb.z))
        }
        return (sum / Double(count), spread / Double(count))
    }
}
