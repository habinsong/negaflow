import Foundation

/// `basicTone` 커널의 단계별 스칼라 판(인코딩 휘도, Double). 커널과 같은 순서·식이다:
/// 대비 → 농도 → 명부 → 암부 → 흰색 → 검정, 단계마다 앞 단계의 출력에 건다.
/// 자동 톤(AutoAdjust.autoTone)은 이 순서대로 앞 단계를 적용한 값에서 다음 단계의 양을 역산한다.
enum BasicToneModel {
    private static func s(_ lo: Double, _ hi: Double, _ x: Double) -> Double { AutoAdjust.smoothstep(lo, hi, x) }
    private static func unit(_ v: Double) -> Double { min(max(v, -1), 1) }

    static func contrast(_ t: Double, _ amount: Double) -> Double {
        let c = unit(amount)
        guard abs(c) > 1e-4 else { return t }
        let pivot = 0.46, e = pow(2, c * (c > 0 ? 0.9 : 0.7))
        let curved = t < pivot ? pivot * pow(t / pivot, e) : 1 - (1 - pivot) * pow((1 - t) / (1 - pivot), e)
        let blend = c > 0 ? 1 : s(0.12, 0.30, t)
        return t + (curved - t) * blend
    }

    static func densityMask(_ t: Double) -> Double { s(0.18, 0.36, t) * (1 - s(0.58, 0.76, t)) }
    static func density(_ t: Double, _ amount: Double) -> Double { t - unit(amount) * 0.10 * densityMask(t) }

    static func highlightMask(_ t: Double) -> Double { s(0.55, 0.80, t) }
    static func highlight(_ t: Double, _ amount: Double) -> Double { t + unit(amount) * 0.10 * highlightMask(t) }

    /// 암부를 올리는 쪽의 마스크(자동 톤은 올리기만 한다).
    static func shadowLiftMask(_ t: Double) -> Double { s(0.02, 0.08, t) * (1 - s(0.30, 0.46, t)) }
    static func shadow(_ t: Double, _ amount: Double) -> Double {
        let a = unit(amount)
        let rise = a > 0 ? s(0.02, 0.08, t) : s(0, 0.20, t)
        return t + a * 0.10 * rise * (1 - s(0.30, 0.46, t))
    }

    static func whitesMask(_ t: Double) -> Double { s(0.68, 0.92, t) }
    static func whites(_ t: Double, _ amount: Double) -> Double {
        let w = min(max(amount, -2), 2), first = unit(w)
        let once = t + first * 0.12 * whitesMask(t)
        return once + (w - first) * 0.12 * whitesMask(once)
    }

    /// 검정 한 단계의 마스크. 올리는 쪽은 smoothstep 상승, 내리는 쪽은 0~0.03 선형 상승이다.
    static func blacksMask(_ t: Double, lifting: Bool) -> Double {
        (lifting ? s(0, 0.03, t) : min(1, max(t, 0) / 0.03)) * (1 - s(0.14, 0.30, t))
    }
    static func blacksStep(_ t: Double, _ amount: Double) -> Double {
        amount >= 0 ? t + amount * 0.06 * blacksMask(t, lifting: true)
            : max(t + amount * 0.06 * blacksMask(t, lifting: false), 0)
    }
    static func blacks(_ t: Double, _ amount: Double) -> Double {
        let b = min(max(amount, -2), 2), first = unit(b)
        return blacksStep(blacksStep(t, first), b - first)
    }

    /// 커널 전체(끝의 [0,1] 고정 포함).
    static func apply(_ g: Double, contrast c: Double = 0, density d: Double = 0, highlight h: Double = 0,
                      shadow sh: Double = 0, whites w: Double = 0, blacks b: Double = 0) -> Double {
        var t = contrast(g, c)
        t = density(t, d)
        t = highlight(t, h)
        t = shadow(t, sh)
        t = whites(t, w)
        t = blacks(t, b)
        return min(max(t, 0), 1)
    }
}
