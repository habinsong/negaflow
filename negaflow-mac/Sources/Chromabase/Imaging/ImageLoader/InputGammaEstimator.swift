import Foundation
import simd

/// 색 경계가 선형광에서 RGB 선분을 이룬다는 가정으로 power를 추정합니다.
/// 회색 경계·클리핑·평탄 영상·불일치 표본에서는 감마를 반환하지 않습니다.
enum InputGammaEstimator {
    struct Edge {
        let samples: [SIMD3<Double>]
        let tile: Int
    }
    struct Estimate: Equatable, Sendable {
        let gamma: Double
        let evidence: Double
        let edgeCount: Int
    }

    static func sample(width: Int, height: Int, pixel: (Int, Int) -> SIMD3<Double>) -> [Edge] {
        guard width >= 32, height >= 32 else { return [] }
        var edges: [Edge] = []
        for row in 0..<64 {
            let y = 8 + row * (height - 17) / 63
            for column in 0..<96 {
                let x = 8 + column * (width - 17) / 95
                for vertical in [false, true] {
                    let samples = (-4...4).map { pixel(x + (vertical ? 0 : $0), y + (vertical ? $0 : 0)) }
                    if accepts(samples) { edges.append(Edge(samples: samples, tile: row / 16 * 4 + column / 24)) }
                }
            }
        }
        return edges
    }

    static func estimate(_ edges: [Edge]) -> Estimate? {
        guard edges.count <= 12288 else { return nil }
        let candidates = edges.filter { (0..<16).contains($0.tile) && accepts($0.samples) }
        let valid = (0..<16).flatMap { tile -> [Edge] in
            let group = candidates.filter { $0.tile == tile }
            let count = min(32, group.count)
            return (0..<count).map { group[$0 * group.count / count] }
        }
        guard valid.count >= 48, Set(valid.map(\.tile)).count >= 6 else { return nil }
        let training = valid.filter { ($0.tile / 4 + $0.tile % 4).isMultiple(of: 2) }
        let validation = valid.filter { !($0.tile / 4 + $0.tile % 4).isMultiple(of: 2) }
        guard training.count >= 20, validation.count >= 20 else { return nil }
        let first = fit(training), second = fit(validation)
        guard first > 0.12, first < 3.98, second > 0.12, second < 3.98,
              abs(log(first / second)) < 0.15 else { return nil }
        let gamma = (first * second).squareRoot()
        let residual = score(gamma, edges: valid)
        let alternatives = [max(0.1, gamma * 0.75), min(4, gamma * 1.333333333333)]
        let separated = alternatives.map { score($0, edges: valid) }.min() ?? residual
        guard residual.isFinite, separated > residual + max(1e-6, residual * 0.25) else { return nil }
        let support = min(1, Double(valid.count) / 128)
        let agreement = max(0, 1 - abs(log(first / second)) / 0.15)
        let separation = min(1, (separated - residual) / max(separated, 1e-9))
        let evidence = min(support, min(agreement, separation))
        guard evidence >= 0.65 else { return nil }
        return Estimate(gamma: (gamma * 1000).rounded() / 1000, evidence: evidence, edgeCount: valid.count)
    }

    private static func accepts(_ samples: [SIMD3<Double>]) -> Bool {
        guard samples.count == 9,
              samples.allSatisfy({ p in (0..<3).allSatisfy { p[$0].isFinite && p[$0] > 0.02 && p[$0] < 0.98 } }) else { return false }
        let left = (samples[0] + samples[1]) / 2
        let right = (samples[7] + samples[8]) / 2
        let contrast = simd_length(right - left)
        guard contrast >= 0.08,
              max(simd_length(samples[0] - samples[1]), simd_length(samples[7] - samples[8])) <= contrast * 0.2,
              simd_length(simd_cross(left, right)) / (simd_length(left) * simd_length(right)) >= 0.05 else { return false }
        return true
    }

    private static func fit(_ edges: [Edge]) -> Double {
        var best = 1.0, loss = Double.infinity
        for index in 0...195 {
            let gamma = 0.1 + Double(index) * 0.02
            let candidate = score(gamma, edges: edges)
            if candidate < loss { best = gamma; loss = candidate }
        }
        let center = best
        for index in -19...19 {
            let gamma = min(4, max(0.1, center + Double(index) * 0.001))
            let candidate = score(gamma, edges: edges)
            if candidate < loss { best = gamma; loss = candidate }
        }
        return best
    }

    private static func score(_ gamma: Double, edges: [Edge]) -> Double {
        var residuals: [Double] = []
        residuals.reserveCapacity(edges.count)
        for edge in edges {
            let p = edge.samples.map { SIMD3(pow($0.x, gamma), pow($0.y, gamma), pow($0.z, gamma)) }
            let a = (p[0] + p[1]) / 2, b = (p[7] + p[8]) / 2
            let d = b - a
            let length = simd_dot(d, d)
            guard length > 1e-12 else { continue }
            var residual = 0.0
            for index in 2...6 {
                let q = p[index] - a
                let t = simd_dot(q, d) / length
                let delta = q - t * d
                residual += simd_dot(delta, delta) / length
            }
            residuals.append(residual / 5)
        }
        guard !residuals.isEmpty else { return .infinity }
        residuals.sort()
        return residuals[residuals.count / 2]
    }
}
