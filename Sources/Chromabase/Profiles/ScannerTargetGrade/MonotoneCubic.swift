import Foundation

/// Fritsch–Carlson monotone piecewise cubic (PCHIP). 단조 데이터에서 overshoot 없이 매끄러운
/// 톤 전달함수를 만든다 — percentile 쌍 기반 톤 커브의 표준 기법(US 5,255,085 참고).
struct MonotoneCubic {
    private let xs: [Double]
    private let ys: [Double]
    private let tangents: [Double]

    init(xs: [Double], ys: [Double]) {
        precondition(xs.count == ys.count && xs.count >= 2)
        let n = xs.count
        var secants = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            secants[i] = (ys[i + 1] - ys[i]) / max(xs[i + 1] - xs[i], 1e-9)
        }
        var m = [Double](repeating: 0, count: n)
        m[0] = secants[0]
        m[n - 1] = secants[n - 2]
        for i in 1..<(n - 1) {
            m[i] = secants[i - 1] * secants[i] <= 0 ? 0 : (secants[i - 1] + secants[i]) / 2
        }
        for i in 0..<(n - 1) {
            if abs(secants[i]) < 1e-12 {
                m[i] = 0
                m[i + 1] = 0
                continue
            }
            let alpha = m[i] / secants[i]
            let beta = m[i + 1] / secants[i]
            let s = alpha * alpha + beta * beta
            if s > 9 {
                let tau = 3.0 / s.squareRoot()
                m[i] = tau * alpha * secants[i]
                m[i + 1] = tau * beta * secants[i]
            }
        }
        self.xs = xs
        self.ys = ys
        self.tangents = m
    }

    func value(_ x: Double) -> Double {
        if x <= xs[0] { return ys[0] }
        if x >= xs[xs.count - 1] { return ys[ys.count - 1] }
        var i = 0
        while i < xs.count - 2 && x > xs[i + 1] { i += 1 }
        let h = xs[i + 1] - xs[i]
        let t = (x - xs[i]) / h
        let t2 = t * t
        let t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        return h00 * ys[i] + h10 * h * tangents[i] + h01 * ys[i + 1] + h11 * h * tangents[i + 1]
    }
}
