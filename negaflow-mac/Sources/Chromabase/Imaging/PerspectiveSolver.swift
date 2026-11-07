import CoreGraphics
import Foundation
import simd

/// 변환 모드의 보정값 찾기.
///
/// 방식: 사진의 곧은 선분(또는 사용자가 그린 안내선)을 수직에 가까운 것과 수평에 가까운 것으로
/// 나누고, 모드가 허용하는 회전(가로축·세로축·화면축)만 움직여 보정 뒤의 선분이 각각 수직·수평에서
/// 벗어난 각도의 가중 합을 가장 작게 만든다(Nelder–Mead 단체법). 카메라 내부 값이나 소실점은
/// 추정하지 않는다 — 고정 초점거리의 회전 하나와 각도 오차만 쓴다.
public enum PerspectiveSolver {
    public struct Solution: Equatable, Sendable {
        public var vertical: Double
        public var horizontal: Double
        public var rotate: Double
    }

    /// 이보다 많이 기운 선은 수직·수평 어느 쪽으로도 세지 않는다(대각선·사선 무늬).
    static let classificationDegrees = 30.0

    /// `segments` 는 회전·뒤집기 뒤 정규좌표, `size` 는 그 그림의 픽셀 크기. 쓸 선이 모자라면 nil.
    public static func solve(
        mode: PerspectiveMode,
        segments: [PerspectiveLineSegment],
        size: CGSize
    ) -> Solution? {
        guard size.width > 1, size.height > 1, mode != .off else { return nil }
        let w = Double(size.width), h = Double(size.height)
        let s = max(w, h) / 2
        var verticals: [(SIMD2<Double>, SIMD2<Double>, Double)] = []
        var horizontals: [(SIMD2<Double>, SIMD2<Double>, Double)] = []
        for segment in segments {
            // 정규 카메라 좌표(중심 0, 긴 변 절반 = 1).
            let a = SIMD2((Double(segment.start.x) * w - w / 2) / s, (Double(segment.start.y) * h - h / 2) / s)
            let b = SIMD2((Double(segment.end.x) * w - w / 2) / s, (Double(segment.end.y) * h - h / 2) / s)
            let d = b - a
            let length = simd_length(d)
            guard length > 1e-4 else { continue }
            let angle = abs(atan2(d.y, d.x) * 180 / .pi)       // 0…180
            let fromHorizontal = min(angle, 180 - angle)
            let fromVertical = abs(angle - 90)
            if fromVertical <= classificationDegrees {
                verticals.append((a, b, length))
            } else if fromHorizontal <= classificationDegrees {
                horizontals.append((a, b, length))
            }
        }

        let guided = mode == .guided
        // 모드별로 움직일 값과 선의 무게.
        var free: [Int] = [2]                      // 0 = 가로축(수직 원근), 1 = 세로축(수평 원근), 2 = 화면축
        var verticalWeight = 1.0, horizontalWeight = 1.0
        var regularization = 0.0
        switch mode {
        case .off:
            return nil
        case .level:
            break
        case .vertical:
            free = [0, 2]
            horizontalWeight = 0.1
        case .full:
            free = [0, 1, 2]
        case .auto:
            free = [0, 1, 2]
            // 균형 모드: 큰 원근 보정은 비용을 물려 과하게 늘이지 않는다.
            regularization = 1
        case .guided:
            if verticals.count >= 2 { free.append(0) }
            if horizontals.count >= 2 { free.append(1) }
        }
        let totalLines = verticals.count + horizontals.count
        guard guided ? totalLines >= 1 : totalLines >= 2 else { return nil }
        if free.contains(0), verticals.count < 2 { free.removeAll { $0 == 0 } }
        if free.contains(1), horizontals.count < 2 { free.removeAll { $0 == 1 } }

        let f = PerspectiveGeometry.focalLength
        // 사진 선은 이상값(사선·곡선의 일부)이 섞인다 — 2° 를 넘는 오차는 덜 센다. 안내선은 의도라 그대로 센다.
        let scale = guided ? 90.0 : 2.0
        func loss(_ degrees: Double) -> Double {
            let e = degrees / scale
            return guided ? e * e : log1p(e * e)
        }
        func cost(_ p: SIMD3<Double>) -> Double {
            let r = PerspectiveGeometry.rotationMatrix(p * (.pi / 180))
            func project(_ q: SIMD2<Double>) -> SIMD2<Double>? {
                let ray = r * SIMD3(q.x / f, q.y / f, 1)
                guard ray.z > PerspectiveGeometry.minimumDepth else { return nil }
                return SIMD2(f * ray.x / ray.z, f * ray.y / ray.z)
            }
            var total = 0.0
            for (a, b, length) in verticals {
                guard let pa = project(a), let pb = project(b) else { return .infinity }
                let d = pb - pa
                total += verticalWeight * length * loss(foldedVerticalError(d))
            }
            for (a, b, length) in horizontals {
                guard let pa = project(a), let pb = project(b) else { return .infinity }
                total += horizontalWeight * length * loss(foldedHorizontalError(pb - pa))
            }
            let tilt = SIMD2(p.x, p.y)
            total += regularization * Double(max(totalLines, 1)) * 0.02 * simd_length_squared(tilt / 10)
            return total
        }

        let best = nelderMead(start: SIMD3<Double>(0, 0, 0), free: free, cost: cost)
        let limit = PerspectiveGeometry.maximumSolvedDegrees
        let solution = Solution(
            vertical: min(max(best.x, -limit), limit),
            horizontal: min(max(best.y, -limit), limit),
            rotate: min(max(best.z, -45), 45)
        )
        guard solution.vertical.isFinite, solution.horizontal.isFinite, solution.rotate.isFinite else { return nil }
        return solution
    }

    /// 수직에서 벗어난 각(도, −90…90). 선의 방향(위·아래)은 상관없다.
    static func foldedVerticalError(_ d: SIMD2<Double>) -> Double {
        var angle = atan2(d.x, d.y) * 180 / .pi
        if angle > 90 { angle -= 180 }
        if angle < -90 { angle += 180 }
        return angle
    }

    static func foldedHorizontalError(_ d: SIMD2<Double>) -> Double {
        var angle = atan2(d.y, d.x) * 180 / .pi
        if angle > 90 { angle -= 180 }
        if angle < -90 { angle += 180 }
        return angle
    }

    /// 고른 성분만 움직이는 Nelder–Mead. 시작 단체는 각 성분 2°.
    static func nelderMead(
        start: SIMD3<Double>,
        free: [Int],
        cost: (SIMD3<Double>) -> Double
    ) -> SIMD3<Double> {
        guard !free.isEmpty else { return start }
        let n = free.count
        func point(_ v: [Double]) -> SIMD3<Double> {
            var p = start
            for (k, index) in free.enumerated() { p[index] = v[k] }
            return p
        }
        var simplex: [[Double]] = [free.map { start[$0] }]
        for k in 0..<n {
            var v = simplex[0]
            v[k] += 2
            simplex.append(v)
        }
        var values = simplex.map { cost(point($0)) }
        for _ in 0..<400 {
            let order = values.indices.sorted { values[$0] < values[$1] }
            simplex = order.map { simplex[$0] }
            values = order.map { values[$0] }
            if abs(values[n] - values[0]) < 1e-9 * max(1, abs(values[0])),
               zip(simplex[n], simplex[0]).allSatisfy({ abs($0 - $1) < 1e-4 }) { break }
            var centroid = [Double](repeating: 0, count: n)
            for v in simplex.dropLast() { for k in 0..<n { centroid[k] += v[k] / Double(n) } }
            func along(_ t: Double) -> [Double] { (0..<n).map { centroid[$0] + t * (simplex[n][$0] - centroid[$0]) } }
            let reflected = along(-1), reflectedValue = cost(point(reflected))
            if reflectedValue < values[0] {
                let expanded = along(-2), expandedValue = cost(point(expanded))
                if expandedValue < reflectedValue {
                    simplex[n] = expanded; values[n] = expandedValue
                } else {
                    simplex[n] = reflected; values[n] = reflectedValue
                }
            } else if reflectedValue < values[n - 1] {
                simplex[n] = reflected; values[n] = reflectedValue
            } else {
                let contracted = reflectedValue < values[n] ? along(-0.5) : along(0.5)
                let contractedValue = cost(point(contracted))
                if contractedValue < min(reflectedValue, values[n]) {
                    simplex[n] = contracted; values[n] = contractedValue
                } else {
                    for i in 1...n {
                        simplex[i] = (0..<n).map { simplex[0][$0] + 0.5 * (simplex[i][$0] - simplex[0][$0]) }
                        values[i] = cost(point(simplex[i]))
                    }
                }
            }
        }
        let bestIndex = values.indices.min { values[$0] < values[$1] } ?? 0
        return point(simplex[bestIndex])
    }
}
