import Foundation

// MARK: - WhiteBalanceGains
//
// 화이트밸런스(온도·틴트) 게인. Windows `white_balance.h` 와 같은 식이다.
//  • |v| ≤ 1 : 예전 선형 게인 그대로 — 온도 R 1+0.18v · G 1+0.03v · B 1−0.18v,
//    틴트 R·B 1−0.12v · G 1+0.24v. 저장된 편집의 채널비가 바뀌지 않는다.
//  • |v| > 1 : 끝점 기울기로 로그 공간에서 이어 붙인다(C1). 범위 ±4 = 온도 ±2.14 스톱.
//    예전 끝(±0.525 스톱)은 대각 sRGB 환산으로 D65 기준 약 5,240K↔8,680K 였다 — 2026-10-14
//    사용자 피드백 "색온도 끝까지 땡겨도 큰 영향이 없다"의 원인.
//  • 두 조정을 로그로 더한 뒤 Rec.709 휘도를 1 로 정규화한다. 예전에는 틴트 ±1 이 밝기를
//    ±13.7% 바꿨다 — 화이트밸런스는 색만 바꾸고 밝기는 그대로 둔다.
// 참고: 온도의 녹색 성분(+0.03)은 + 쪽에서 흑체 궤적이 요구하는 G/√(R·B)(+0.065 스톱)와 일치한다.
public enum WhiteBalanceGains {
    /// 온도·틴트 저장 범위. ±1 까지는 예전 게인, 그 너머는 로그 연장.
    public static let maximum = 4.0
    static let identityThreshold = 1e-3

    private static let warmthSlope = SIMD3<Double>(0.18, 0.03, -0.18)
    private static let tintSlope = SIMD3<Double>(-0.12, 0.24, -0.12)

    /// 채널마다 log2(1 + k·v). |v| > 1 은 끝점 기울기 k / ((1 + k·s)·ln2) 로 선형 연장한다.
    private static func channelLog(_ value: Double, slope k: SIMD3<Double>) -> SIMD3<Double> {
        let edge = min(max(value, -1), 1)
        let beyond = value - edge
        let atEdge = SIMD3<Double>(repeating: 1) + k * edge
        let base = SIMD3(log2(atEdge.x), log2(atEdge.y), log2(atEdge.z))
        return base + k / (atEdge * log(2.0)) * beyond
    }

    /// 휘도 1 로 정규화한 linear RGB 게인. 둘 다 임계 이하이면 nil(항등 — 건너뛴다).
    public static func gains(warmth: Double, tint: Double) -> SIMD3<Double>? {
        let useWarmth = abs(warmth) > identityThreshold
        let useTint = abs(tint) > identityThreshold
        guard useWarmth || useTint else { return nil }
        var sum = SIMD3<Double>(repeating: 0)
        if useWarmth { sum += channelLog(warmth, slope: warmthSlope) }
        if useTint { sum += channelLog(tint, slope: tintSlope) }
        let linear = SIMD3(exp2(sum.x), exp2(sum.y), exp2(sum.z))
        let luminance = 0.2126 * linear.x + 0.7152 * linear.y + 0.0722 * linear.z
        return linear / luminance
    }

    // MARK: 자동 화이트밸런스 역산용

    /// 온도가 만드는 log2(R/B).
    static func warmthRedBlueStops(_ warmth: Double) -> Double {
        let l = channelLog(warmth, slope: warmthSlope)
        return l.x - l.z
    }

    /// 온도가 만드는 녹색 성분 log2(G/√(R·B)).
    static func warmthGreenStops(_ warmth: Double) -> Double {
        let l = channelLog(warmth, slope: warmthSlope)
        return l.y - 0.5 * (l.x + l.z)
    }

    /// 틴트가 만드는 log2(G/√(R·B)).
    static func tintGreenStops(_ tint: Double) -> Double {
        let l = channelLog(tint, slope: tintSlope)
        return l.y - 0.5 * (l.x + l.z)
    }

    /// 단조 증가 함수의 역 — [−4, 4] 에서 이분법.
    static func solve(_ targetStops: Double, _ function: (Double) -> Double) -> Double {
        var low = -maximum, high = maximum
        if targetStops <= function(low) { return low }
        if targetStops >= function(high) { return high }
        for _ in 0..<50 {
            let middle = 0.5 * (low + high)
            if function(middle) < targetStops { low = middle } else { high = middle }
        }
        return 0.5 * (low + high)
    }
}
