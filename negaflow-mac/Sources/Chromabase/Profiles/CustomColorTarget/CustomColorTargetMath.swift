import Foundation

struct CustomColorTargetProfile: Sendable {
    let target: DevelopTarget
    let tone: [Double]
    let slopes: [Double]
    let gain: [Double]
    let density: [Double]
    let hueShadow: [Double]
    let hueMid: [Double]
    let hueHigh: [Double]
    let highlightHue: [Double]
    // q, A, B, M
    let controls: SIMD4<Double>
    let tintShadow: SIMD2<Double>
    let tintMid: SIMD2<Double>
    let tintHigh: SIMD2<Double>

    init(target: DevelopTarget, tone: [Double], gain: [Double], density: [Double],
         hueShadow: [Double], hueMid: [Double], hueHigh: [Double], highlightHue: [Double],
         controls: SIMD4<Double>, tintShadow: SIMD2<Double>, tintMid: SIMD2<Double>,
         tintHigh: SIMD2<Double>) {
        precondition(tone.count == 10)
        precondition([gain, density, hueShadow, hueMid, hueHigh, highlightHue].allSatisfy { $0.count == 8 })
        self.target = target
        self.tone = tone
        self.slopes = CustomColorTargetMath.tangents(tone)
        self.gain = gain
        self.density = density
        self.hueShadow = hueShadow
        self.hueMid = hueMid
        self.hueHigh = hueHigh
        self.highlightHue = highlightHue
        self.controls = controls
        self.tintShadow = tintShadow
        self.tintMid = tintMid
        self.tintHigh = tintHigh
    }
}

enum CustomColorTargetMath {
    static let knots: [Double] = [0, 5, 10, 20, 35, 50, 65, 80, 90, 100]
    static let chromaStart = 48.0
    static let chromaRange = 48.0

    static func tangents(_ values: [Double]) -> [Double] {
        let widths = (0..<9).map { knots[$0 + 1] - knots[$0] }
        let secants = (0..<9).map { (values[$0 + 1] - values[$0]) / widths[$0] }
        var slopes = [Double](repeating: 0, count: 10)
        for i in 1..<9 where secants[i - 1] * secants[i] > 0 {
            let w1 = 2 * widths[i] + widths[i - 1]
            let w2 = widths[i] + 2 * widths[i - 1]
            slopes[i] = (w1 + w2) / (w1 / secants[i - 1] + w2 / secants[i])
        }
        func endpoint(_ h0: Double, _ h1: Double, _ d0: Double, _ d1: Double) -> Double {
            let value = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
            if value * d0 <= 0 { return 0 }
            if d0 * d1 < 0, abs(value) > 3 * abs(d0) { return 3 * d0 }
            return value
        }
        slopes[0] = endpoint(widths[0], widths[1], secants[0], secants[1])
        slopes[9] = endpoint(widths[8], widths[7], secants[8], secants[7])
        return slopes
    }

    static func tone(_ l: Double, profile p: CustomColorTargetProfile) -> Double {
        if l <= 0 { return p.tone[0] + l * p.slopes[0] }
        if l >= 100 { return p.tone[9] + (l - 100) * p.slopes[9] }
        let i = (0..<9).first { l < knots[$0 + 1] } ?? 8
        let dx = knots[i + 1] - knots[i]
        let z = (l - knots[i]) / dx
        let z2 = z * z, z3 = z2 * z
        return (2 * z3 - 3 * z2 + 1) * p.tone[i]
            + (z3 - 2 * z2 + z) * dx * p.slopes[i]
            + (-2 * z3 + 3 * z2) * p.tone[i + 1]
            + (z3 - z2) * dx * p.slopes[i + 1]
    }

    static func chromaRolloff(_ value: Double) -> Double {
        guard value > chromaStart else { return value }
        let excess = value - chromaStart
        return chromaStart + excess / (1 + excess / chromaRange)
    }

    static func evaluate(_ lab: ColorTargetLab, profile p: CustomColorTargetProfile) -> ColorTargetLab {
        let l = lab.l, c = hypot(lab.a, lab.b)
        let h = c == 0 ? 0 : (atan2(lab.b, lab.a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let t = tone(l, profile: p) / 100
        let k = sample(p.density, hue: h) * c / (c + 24)
        let dense = t < 0 ? t / (1 + k) : (t > 1 ? 1 + (1 + k) * (t - 1) : t / (1 + k * (1 - t)))
        let lout = 100 * dense
        let colorWeight = smooth(c, 2, 10)
        let gain = 1 + (sample(p.gain, hue: h) - 1) * colorWeight
        let shadow = p.controls.x + (1 - p.controls.x) * smooth(l, 0, 28)
        let base = chromaRolloff(c * gain * shadow)
        let drive = (1 - p.controls.w) * l + p.controls.w * lout
        let v = max((drive - p.controls.y) / (100 - p.controls.y), 0)
        let cout = base / (1 + p.controls.z * v * v * (1 + base / 80))
        let loss = base == 0 ? 0 : max(0, min(1, (base - cout) / base))
        let rotation: Double
        if l < 50 {
            rotation = mix(sample(p.hueShadow, hue: h), sample(p.hueMid, hue: h), clamp((l - 20) / 30))
        } else {
            rotation = mix(sample(p.hueMid, hue: h), sample(p.hueHigh, hue: h), clamp((l - 50) / 30))
        }
        let radians = (h + (rotation + sample(p.highlightHue, hue: h) * loss) * colorWeight) * .pi / 180
        let tint: SIMD2<Double>
        if l < 20 {
            tint = p.tintShadow * clamp(l / 20)
        } else if l < 50 {
            let amount = (l - 20) / 30
            tint = p.tintShadow * (1 - amount) + p.tintMid * amount
        } else if l < 80 {
            let amount = (l - 50) / 30
            tint = p.tintMid * (1 - amount) + p.tintHigh * amount
        } else {
            tint = p.tintHigh * (1 - clamp((l - 80) / 20))
        }
        let neutral = 1 - smooth(c, 25, 75)
        return ColorTargetLab(l: lout, a: cout * cos(radians) + tint.x * neutral,
                              b: cout * sin(radians) + tint.y * neutral)
    }

    static func rgb(_ rgb: SIMD3<Double>, profile: CustomColorTargetProfile) -> SIMD3<Double> {
        ColorTargetColorimetry.labD50ToLinearSRGB(
            evaluate(ColorTargetColorimetry.linearSRGBToLabD50(rgb), profile: profile)
        )
    }

    private static func sample(_ values: [Double], hue: Double) -> Double {
        let index = hue / 45
        let lower = Int(index) % 8
        return mix(values[lower], values[(lower + 1) % 8], index - floor(index))
    }

    private static func clamp(_ x: Double) -> Double { max(0, min(1, x)) }
    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private static func smooth(_ x: Double, _ a: Double, _ b: Double) -> Double {
        let t = clamp((x - a) / (b - a))
        return t * t * (3 - 2 * t)
    }
}
