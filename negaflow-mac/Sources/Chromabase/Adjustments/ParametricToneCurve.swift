import Foundation

/// 파라메트릭 톤 커브(밝은 영역·밝은 톤·어두운 톤·어두운 영역). 인코딩(sRGB 감마) 휘도 위의 단조 곡선이다.
///
/// 네 슬라이더는 매듭 하나씩을 움직인다. 매듭은 장면 휘도의 10·35·65·90 백분위(네 영역의 가운데)에 두고,
/// 슬라이더 ±1 은 그 매듭을 이웃 매듭까지 거리의 `reach` 배만큼 올리거나 내린다. 양 끝(0·1)은 고정이다.
/// 곡선은 매듭 사이를 Fritsch–Carlson 단조 3차 Hermite 로 잇는다(Fritsch & Carlson 1980, SIAM J. Numer.
/// Anal. 17(2)). `reach` < 0.5 라 마주 움직이는 두 매듭도 엇갈리지 않고, 매듭 값이 증가하면 이 보간은
/// 단조라서 어떤 슬라이더 조합에서도 톤이 뒤집히지 않는다.
///
/// 예전 식(영역 마스크 × 고정 크기 덧셈, 선형 휘도)은 마스크 경계의 기울기가 커서 ±1 에서 톤이 뒤집혔다.
/// 사용자 카탈로그 198장 실측(2026-11-08): 슬라이더 하나 ±1 에서 화소 중앙값 10~36% 가 역전, 어두운 톤
/// −1 은 중앙값 25%(최대 77%)를 검정으로 잘랐다. 같은 분포에서 이 곡선은 역전 0, 매듭 이동은 중앙값
/// 0.06~0.12(인코딩)로 기본 톤 슬라이더(최대 0.10)와 같은 크기다.
public struct ParametricToneCurve: Sendable, Equatable {
    /// 매듭 위치(인코딩 휘도). 양 끝 0·1 을 포함해 여섯 개.
    public let x: [Double]
    /// 매듭 값.
    public let y: [Double]
    /// 매듭 기울기(Fritsch–Carlson).
    public let tangent: [Double]

    /// 매듭이 양 끝과 떨어져야 하는 최소 거리, 매듭끼리의 최소 간격(인코딩). 둘이 같아 어떤 장면에서도
    /// 슬라이더 ±1 이 매듭을 적어도 reach × 0.10 = 0.045 움직인다(밝은 장면의 밝은 영역 매듭이 흰색에
    /// 붙어 +1 이 0.02 밖에 못 움직이던 것을 막는다).
    static let edgeMargin = 0.10
    static let minimumGap = 0.10
    /// 슬라이더 ±1 이 매듭을 움직이는 비율(이웃 매듭까지 거리 대비). 0.5 미만이어야 매듭 순서가 유지된다.
    static let reach = 0.45
    /// 측정을 못 할 때의 매듭 — Lightroom 기본 분할(25·50·75%)로 나눈 네 영역의 가운데.
    static let fallbackKnots: [Double] = [0.125, 0.375, 0.625, 0.875]

    /// `percentiles` — 장면 선형 휘도의 10·35·65·90 백분위. nil 이면 기본 매듭을 쓴다.
    public init(percentiles: [Double]?, highlights: Double, lights: Double, darks: Double, shadows: Double) {
        let inner = Self.knots(percentiles: percentiles)
        let xs = [0.0] + inner + [1.0]
        var ys = xs
        for (i, amount) in [shadows, darks, lights, highlights].enumerated() {
            let k = i + 1
            let a = min(max(amount.isFinite ? amount : 0, -1), 1)
            let span: Double = a > 0 ? xs[k + 1] - xs[k] : xs[k] - xs[k - 1]
            ys[k] = xs[k] + a * Self.reach * span
        }
        x = xs
        y = ys
        tangent = Self.monotoneTangents(xs, ys)
    }

    /// 안쪽 매듭 네 개. 백분위를 인코딩해 양 끝에서 `edgeMargin`, 서로 `minimumGap` 이상 떨어뜨린다.
    static func knots(percentiles: [Double]?) -> [Double] {
        guard let p = percentiles, p.count == 4, p.allSatisfy(\.isFinite) else { return fallbackKnots }
        let q: [Double] = p.map { (value: Double) -> Double in AutoAdjust.srgbEncode(min(max(value, 0), 1)) }
        let low = edgeMargin, high = 1 - edgeMargin
        var k = [Double](repeating: 0, count: 4)
        k[0] = min(max(q[0], low), high - 3 * minimumGap)
        for i in 1..<4 { k[i] = max(q[i], k[i - 1] + minimumGap) }
        if k[3] > high {
            k[3] = high
            for i in stride(from: 2, through: 0, by: -1) { k[i] = min(k[i], k[i + 1] - minimumGap) }
        }
        return k
    }

    static func monotoneTangents(_ xs: [Double], _ ys: [Double]) -> [Double] {
        let n = xs.count
        var d = [Double](repeating: 0, count: n - 1)
        for k in 0..<(n - 1) {
            let rise: Double = ys[k + 1] - ys[k]
            let run: Double = xs[k + 1] - xs[k]
            d[k] = rise / run
        }
        var m = [Double](repeating: 0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        for i in 1..<(n - 1) {
            let left: Double = d[i - 1], right: Double = d[i]
            m[i] = left * right <= 0 ? 0 : (left + right) / 2
        }
        for i in 0..<(n - 1) {
            let slope: Double = d[i]
            guard slope > 0 else { m[i] = 0; m[i + 1] = 0; continue }
            let a: Double = m[i] / slope
            let b: Double = m[i + 1] / slope
            let s: Double = a * a + b * b
            if s > 9 {
                let t: Double = 3 / s.squareRoot()
                m[i] = t * a * slope
                m[i + 1] = t * b * slope
            }
        }
        return m
    }

    /// 인코딩 휘도 g 의 곡선 값. 커널 `parametricToneCurve` 와 같은 식이다.
    public func value(_ g: Double) -> Double {
        var i = 0
        while i < x.count - 2, g >= x[i + 1] { i += 1 }
        let h = x[i + 1] - x[i]
        let t: Double = min(max((g - x[i]) / h, 0), 1)
        let t2: Double = t * t, t3: Double = t2 * t
        let h00: Double = 2 * t3 - 3 * t2 + 1, h10: Double = t3 - 2 * t2 + t
        let h01: Double = -2 * t3 + 3 * t2, h11: Double = t3 - t2
        return h00 * y[i] + h10 * h * tangent[i] + h01 * y[i + 1] + h11 * h * tangent[i + 1]
    }
}
