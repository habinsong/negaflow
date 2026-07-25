import Foundation

enum FilmBaseStatistics {
    struct Cluster {
        let rgb: SIMD3<Double>
        let retained: [FilmBaseSample]
    }

    static func coherentCluster(_ samples: [FilmBaseSample]) -> Cluster? {
        guard !samples.isEmpty else { return nil }
        let lumas = samples.map(\.luma)
        let medianLuma = median(lumas)
        let mad = median(lumas.map { abs($0 - medianLuma) })
        let tolerance = max(mad * 1.4826 * 3.0, 1e-4)
        let filtered = zip(samples, lumas)
            .filter { abs($0.1 - medianLuma) <= tolerance }
            .map(\.0)
        let retained = filtered.count >= max(4, samples.count / 4) ? filtered : samples
        return Cluster(
            rgb: SIMD3(
                median(retained.map { $0.color.x }),
                median(retained.map { $0.color.y }),
                median(retained.map { $0.color.z })
            ),
            retained: retained
        )
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let midpoint = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[midpoint - 1] + sorted[midpoint]) / 2
            : sorted[midpoint]
    }

    static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction)))
        return sorted[index]
    }
}
