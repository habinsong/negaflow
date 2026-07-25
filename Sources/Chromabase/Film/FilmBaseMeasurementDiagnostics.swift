import Foundation

/// 필름 베이스 자동 측정의 관측 증거입니다.
/// `evidenceScore`는 보정된 확률이나 화학적 정확도가 아니라, 공개된 구성 지표 중 가장 약한
/// 항목을 나타내는 0...1 품질 점수입니다.
public struct FilmBaseMeasurementDiagnostics: Codable, Sendable, Equatable {
    public enum Method: String, Codable, Sendable {
        case connectedComponent
        case continuousBorder
        case distributedMask
        case stripFallback
    }

    public enum Anomaly: String, Codable, Sendable, CaseIterable {
        case fallbackEstimate
        case lowSampleSupport
        case sparseSampleCoverage
        case limitedSpatialCoverage
        case unstableLuma
        case inconsistentChannels
        case clippedSamples
        case heavyOutlierRejection
    }

    public struct EvidenceComponents: Codable, Sendable, Equatable {
        public let sampleSupport: Double
        public let sampleCoverage: Double
        public let spatialCoverage: Double
        public let lumaUniformity: Double
        public let channelConsistency: Double
        public let unclippedSamples: Double
        public let inlierRetention: Double

        var minimum: Double {
            min(
                sampleSupport,
                sampleCoverage,
                spatialCoverage,
                lumaUniformity,
                channelConsistency,
                unclippedSamples,
                inlierRetention
            )
        }
    }

    public let schemaVersion: Int
    public let method: Method
    public let sampledPixelCount: Int
    public let candidateCount: Int
    public let selectedSampleCount: Int
    public let retainedSampleCount: Int
    public let sampleCoverage: Double
    public let spatialCoverage: Double
    public let medianLuma: Double
    public let lumaMAD: Double
    public let channelMAD: [Double]
    public let chromaticityMAD: Double
    public let clippedFraction: Double
    public let outlierFraction: Double
    public let evidenceComponents: EvidenceComponents
    public let evidenceScore: Double
    public let isCalibratedProbability: Bool
    public let anomalies: [Anomaly]

    init(
        method: Method,
        sampledPixelCount: Int,
        candidateCount: Int,
        selected: [FilmBaseSample],
        retained: [FilmBaseSample],
        gridWidth: Int,
        gridHeight: Int
    ) {
        let selectedCount = selected.count
        let retainedCount = retained.count
        let lumas = selected.map(\.luma)
        let medianLuma = FilmBaseStatistics.median(lumas)
        let lumaMAD = FilmBaseStatistics.median(lumas.map { abs($0 - medianLuma) })
        let channelMedians = SIMD3(
            FilmBaseStatistics.median(selected.map { $0.color.x }),
            FilmBaseStatistics.median(selected.map { $0.color.y }),
            FilmBaseStatistics.median(selected.map { $0.color.z })
        )
        let channelMAD = [
            FilmBaseStatistics.median(selected.map { abs($0.color.x - channelMedians.x) }),
            FilmBaseStatistics.median(selected.map { abs($0.color.y - channelMedians.y) }),
            FilmBaseStatistics.median(selected.map { abs($0.color.z - channelMedians.z) }),
        ]
        let chromaticities = selected.map { sample -> SIMD3<Double> in
            let sum = max(sample.color.x + sample.color.y + sample.color.z, 1e-9)
            return sample.color / sum
        }
        let medianChromaticity = SIMD3(
            FilmBaseStatistics.median(chromaticities.map(\.x)),
            FilmBaseStatistics.median(chromaticities.map(\.y)),
            FilmBaseStatistics.median(chromaticities.map(\.z))
        )
        let chromaticityMAD = FilmBaseStatistics.median(chromaticities.map {
            max(abs($0.x - medianChromaticity.x), abs($0.y - medianChromaticity.y), abs($0.z - medianChromaticity.z))
        })
        let clippedCount = selected.lazy.filter {
            min($0.color.x, $0.color.y, $0.color.z) <= 1e-4
                || max($0.color.x, $0.color.y, $0.color.z) >= 0.9999
        }.count
        let sampleCoverage = Double(selectedCount) / Double(max(1, sampledPixelCount))
        let xCoverage = Double(Set(selected.map(\.x)).count) / Double(max(1, gridWidth))
        let yCoverage = Double(Set(selected.map(\.y)).count) / Double(max(1, gridHeight))
        let spatialCoverage = max(xCoverage, yCoverage)
        let clippedFraction = Double(clippedCount) / Double(max(1, selectedCount))
        let outlierFraction = 1 - Double(retainedCount) / Double(max(1, selectedCount))
        let relativeLumaMAD = lumaMAD / max(abs(medianLuma), 1e-6)
        let components = EvidenceComponents(
            sampleSupport: min(1, Double(selectedCount) / 64),
            sampleCoverage: min(1, sampleCoverage / 0.02),
            spatialCoverage: min(1, spatialCoverage),
            lumaUniformity: max(0, 1 - relativeLumaMAD / 0.08),
            channelConsistency: max(0, 1 - chromaticityMAD / 0.03),
            unclippedSamples: max(0, 1 - clippedFraction / 0.05),
            inlierRetention: max(0, 1 - outlierFraction)
        )

        var anomalies: [Anomaly] = []
        if method == .stripFallback { anomalies.append(.fallbackEstimate) }
        if selectedCount < 32 { anomalies.append(.lowSampleSupport) }
        if sampleCoverage < 0.02 { anomalies.append(.sparseSampleCoverage) }
        if spatialCoverage < 0.65 { anomalies.append(.limitedSpatialCoverage) }
        if relativeLumaMAD > 0.04 { anomalies.append(.unstableLuma) }
        if chromaticityMAD > 0.015 { anomalies.append(.inconsistentChannels) }
        if clippedFraction > 0.01 { anomalies.append(.clippedSamples) }
        if outlierFraction > 0.10 { anomalies.append(.heavyOutlierRejection) }

        self.schemaVersion = 1
        self.method = method
        self.sampledPixelCount = sampledPixelCount
        self.candidateCount = candidateCount
        self.selectedSampleCount = selectedCount
        self.retainedSampleCount = retainedCount
        self.sampleCoverage = sampleCoverage
        self.spatialCoverage = spatialCoverage
        self.medianLuma = medianLuma
        self.lumaMAD = lumaMAD
        self.channelMAD = channelMAD
        self.chromaticityMAD = chromaticityMAD
        self.clippedFraction = clippedFraction
        self.outlierFraction = outlierFraction
        self.evidenceComponents = components
        self.evidenceScore = components.minimum
        self.isCalibratedProbability = false
        self.anomalies = anomalies
    }
}

struct FilmBaseMeasurement {
    let rgb: SIMD3<Double>
    let diagnostics: FilmBaseMeasurementDiagnostics

    func filmBase(source: FilmBase.Source) -> FilmBase {
        FilmBase(rgb: rgb, source: source, measurementDiagnostics: diagnostics)
    }
}

enum FilmBaseMeasurementBuilder {
    static func build(
        method: FilmBaseMeasurementDiagnostics.Method,
        sampledPixelCount: Int,
        candidateCount: Int,
        selected: [FilmBaseSample],
        gridWidth: Int,
        gridHeight: Int
    ) -> FilmBaseMeasurement? {
        guard let cluster = FilmBaseStatistics.coherentCluster(selected) else { return nil }
        return FilmBaseMeasurement(
            rgb: cluster.rgb,
            diagnostics: FilmBaseMeasurementDiagnostics(
                method: method,
                sampledPixelCount: sampledPixelCount,
                candidateCount: candidateCount,
                selected: selected,
                retained: cluster.retained,
                gridWidth: gridWidth,
                gridHeight: gridHeight
            )
        )
    }
}
