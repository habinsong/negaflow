import CoreGraphics
import Foundation

/// 곧은 선분 하나(정규좌표, y 아래)와 길이(픽셀).
public struct PerspectiveLineSegment: Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    public var length: Double

    public init(start: CGPoint, end: CGPoint, length: Double) {
        self.start = start
        self.end = end
        self.length = length
    }
}

/// 변환 자동 모드가 쓰는 곧은 선분 찾기.
///
/// 방식: 밝기 기울기가 뚜렷한 화소 가운데 가장자리 방향(기울기에 수직)이 이웃과 비슷한 화소끼리
/// 묶고(합집합 찾기), 묶음마다 주성분으로 직선을 맞춘다. 가늘고 길며 방향이 고른 묶음만 선분으로
/// 남긴다. 기울기 방향으로 화소를 묶어 직선을 찾는 것은 1980년대부터 쓰인 공개 기법이다.
public enum PerspectiveLineDetector {
    /// 분석할 회색조 그림의 긴 변(픽셀). 더 크면 줄여서 넘긴다.
    public static let analysisLongEdge = 900

    /// `luma` 는 감마 도메인 밝기(0…1), 행 우선 `width × height`. 크기가 맞지 않으면 빈 결과.
    public static func detect(luma: [Float], width: Int, height: Int, maximumSegments: Int = 400)
        -> [PerspectiveLineSegment] {
        guard width >= 16, height >= 16, luma.count == width * height else { return [] }
        let blurred = blur(luma, width: width, height: height)
        let count = width * height
        var magnitude = [Float](repeating: 0, count: count)
        var direction = [Float](repeating: 0, count: count)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let gx = (blurred[i - width + 1] + 2 * blurred[i + 1] + blurred[i + width + 1])
                    - (blurred[i - width - 1] + 2 * blurred[i - 1] + blurred[i + width - 1])
                let gy = (blurred[i + width - 1] + 2 * blurred[i + width] + blurred[i + width + 1])
                    - (blurred[i - width - 1] + 2 * blurred[i - width] + blurred[i - width + 1])
                let m = (gx * gx + gy * gy).squareRoot()
                magnitude[i] = m
                // 가장자리 방향(기울기에 수직), 0…π.
                var a = atan2(gx, -gy)
                if a < 0 { a += .pi }
                if a >= .pi { a -= .pi }
                direction[i] = a
            }
        }
        let threshold = edgeThreshold(magnitude)
        guard threshold > 0 else { return [] }

        // 방향이 22.5° 안으로 비슷한 8-이웃끼리 묶는다.
        var parent = [Int32](repeating: -1, count: count)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != Int32(root) { root = Int(parent[root]) }
            var node = i
            while parent[node] != Int32(root) {
                let next = Int(parent[node])
                parent[node] = Int32(root)
                node = next
            }
            return root
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[max(ra, rb)] = Int32(min(ra, rb)) }
        }
        for i in 0..<count where magnitude[i] >= threshold { parent[i] = Int32(i) }
        let tolerance: Float = .pi / 8
        func similar(_ a: Float, _ b: Float) -> Bool {
            let d = abs(a - b)
            return min(d, .pi - d) < tolerance
        }
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                guard parent[i] >= 0 else { continue }
                for j in [i + 1, i + width - 1, i + width, i + width + 1] where parent[j] >= 0 {
                    if similar(direction[i], direction[j]) { union(i, j) }
                }
            }
        }

        // 묶음별 모멘트.
        struct Moments { var n = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0, c = 0.0, s = 0.0 }
        var groups: [Int: Moments] = [:]
        for i in 0..<count where parent[i] >= 0 {
            let root = find(i)
            let x = Double(i % width), y = Double(i / width)
            let a = Double(direction[i]) * 2
            var m = groups[root, default: Moments()]
            m.n += 1; m.sx += x; m.sy += y
            m.sxx += x * x; m.syy += y * y; m.sxy += x * y
            m.c += cos(a); m.s += sin(a)
            groups[root] = m
        }
        let longEdge = Double(max(width, height))
        let minimumLength = max(12, longEdge * 0.04)
        var segments: [PerspectiveLineSegment] = []
        for (_, m) in groups where m.n >= minimumLength * 0.6 {
            let mx = m.sx / m.n, my = m.sy / m.n
            let cxx = m.sxx / m.n - mx * mx
            let cyy = m.syy / m.n - my * my
            let cxy = m.sxy / m.n - mx * my
            let trace = cxx + cyy
            let root = ((cxx - cyy) * (cxx - cyy) / 4 + cxy * cxy).squareRoot()
            let major = trace / 2 + root, minor = max(trace / 2 - root, 0)
            guard major > 0 else { continue }
            let angle = 0.5 * atan2(2 * cxy, cxx - cyy)
            let length = (12 * major).squareRoot()        // 균일 분포의 길이 = √(12·분산)
            let thickness = (12 * minor).squareRoot()
            // 방향이 고른가: 화소 방향의 평균 결과 벡터 길이(이중 각).
            let coherence = (m.c * m.c + m.s * m.s).squareRoot() / m.n
            guard length >= minimumLength,
                  length >= 6 * max(thickness, 1),
                  coherence >= 0.8 else { continue }
            let dx = cos(angle) * length / 2, dy = sin(angle) * length / 2
            segments.append(PerspectiveLineSegment(
                start: CGPoint(x: (mx - dx) / Double(width), y: (my - dy) / Double(height)),
                end: CGPoint(x: (mx + dx) / Double(width), y: (my + dy) / Double(height)),
                length: length
            ))
        }
        segments.sort { $0.length > $1.length }
        return Array(segments.prefix(maximumSegments))
    }

    /// 기울기 크기의 85 백분위와 고정 바닥(감마 밝기 0.08/화소) 중 큰 값. 대비가 낮은 사진에서
    /// 잡음까지 선으로 잡지 않게 바닥을 둔다.
    static func edgeThreshold(_ magnitude: [Float]) -> Float {
        var histogram = [Int](repeating: 0, count: 1024)
        var total = 0
        for m in magnitude where m > 0 {
            histogram[min(Int(m / 4 * 1023), 1023)] += 1
            total += 1
        }
        guard total > 0 else { return 0 }
        var seen = 0
        var percentile: Float = 0
        for (bin, value) in histogram.enumerated() {
            seen += value
            if Double(seen) >= Double(total) * 0.85 {
                percentile = Float(bin) / 1023 * 4
                break
            }
        }
        return max(percentile, 0.08 * 4)
    }

    /// 3×3 가우시안(1-2-1). 경계는 가장자리 화소를 되풀이한다.
    static func blur(_ input: [Float], width: Int, height: Int) -> [Float] {
        var horizontal = [Float](repeating: 0, count: input.count)
        for y in 0..<height {
            for x in 0..<width {
                let l = input[y * width + max(x - 1, 0)]
                let c = input[y * width + x]
                let r = input[y * width + min(x + 1, width - 1)]
                horizontal[y * width + x] = (l + 2 * c + r) / 4
            }
        }
        var output = [Float](repeating: 0, count: input.count)
        for y in 0..<height {
            for x in 0..<width {
                let u = horizontal[max(y - 1, 0) * width + x]
                let c = horizontal[y * width + x]
                let d = horizontal[min(y + 1, height - 1) * width + x]
                output[y * width + x] = (u + 2 * c + d) / 4
            }
        }
        return output
    }
}
