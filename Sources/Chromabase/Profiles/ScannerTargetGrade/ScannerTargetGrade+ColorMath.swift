import Foundation
import simd

extension ScannerTargetGrade {
    // MARK: 수치 유틸 (실측 스크립트 analyze_lut_target.py 와 동일 정의)

    static func srgbEncode(_ v: Double) -> Double {
        v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1.0 / 2.4) - 0.055
    }

    static func srgbDecode(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static let d65 = SIMD3(0.95047, 1.0, 1.08883)

    static func srgbToLab(r: Double, g: Double, b: Double) -> (l: Double, a: Double, b: Double) {
        let lr = srgbDecode(r), lg = srgbDecode(g), lb = srgbDecode(b)
        let x = (0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb) / d65.x
        let y = (0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb) / d65.y
        let z = (0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb) / d65.z
        let fx = labF(x), fy = labF(y), fz = labF(z)
        return (116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))
    }

    static func labToSRGB(l: Double, a: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        let extended = labToExtendedSRGB(l: l, a: a, b: b)
        return (
            clamp(extended.r, 0.0, 1.0),
            clamp(extended.g, 0.0, 1.0),
            clamp(extended.b, 0.0, 1.0)
        )
    }

    /// Lab 후보가 sRGB gamut 밖으로 얼마나 나가는지 보존한다. LUT 작성기는 정방향과
    /// reciprocal 후보를 함께 보고 공통 감쇠율을 계산한 뒤에만 unit cube로 되돌린다.
    static func labToExtendedSRGB(l: Double, a: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        let fy = (l + 16.0) / 116.0
        let fx = fy + a / 500.0
        let fz = fy - b / 200.0
        let x = labFInverse(fx) * d65.x
        let y = labFInverse(fy) * d65.y
        let z = labFInverse(fz) * d65.z
        let lr = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let lg = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let lb = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        return (
            srgbEncode(lr),
            srgbEncode(lg),
            srgbEncode(lb)
        )
    }

    private static func labF(_ t: Double) -> Double {
        let delta = 6.0 / 29.0
        return t > delta * delta * delta ? cbrt(t) : t / (3.0 * delta * delta) + 4.0 / 29.0
    }

    private static func labFInverse(_ t: Double) -> Double {
        let delta = 6.0 / 29.0
        return t > delta ? t * t * t : 3.0 * delta * delta * (t - 4.0 / 29.0)
    }

    static func smoothstep(_ lo: Double, _ hi: Double, _ v: Double) -> Double {
        let t = clamp((v - lo) / max(hi - lo, 1e-9), 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)
    }

    static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }
}
