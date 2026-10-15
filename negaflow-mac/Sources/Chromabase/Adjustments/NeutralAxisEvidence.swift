import Foundation

// MARK: - NeutralAxisEvidence
//
// 장면의 중립축 증거 — 무채색이어야 할 화소들의 채널 캐스트를 휘도대별로 모은다. 자동 색상
// (NeutralBalance)과 자동 화이트밸런스가 함께 쓴다.
//
// 반전은 채널별 Dmax 정규화로 이미 거의 중립이므로 남은 캐스트는 작다고 본다: 중립에서 0.5 스톱
// 안의 화소만 후보로 잡고(숲의 초록·노을 같은 지배색은 그보다 멀어 빠진다), 후보의 중앙 캐스트
// 주위로 두 번 좁혀 고른다. 그리고 휘도대(1 스톱)마다 중앙값을 따로 낸다 — 한 휘도대를 차지한
// 따뜻한 조명 면이 전체 평균을 끌고 가지 못하게 한다(2026-10-14 실측: 화면 15% 의 웜 영역 때문에
// 자동 WB 가 진짜 중립을 R/B 0.90 으로 식혔다).
struct NeutralAxisEvidence: Sendable, Equatable {
    struct Band: Sendable, Equatable {
        /// 대역 화소의 ln(기하평균 휘도) 중앙값.
        var logLuminance: Double
        /// ln c − ln Ȳ 의 채널별 중앙값(합 ≈ 0). 0 이면 중립.
        var cast: SIMD3<Double>
        var count: Int
    }

    var bands: [Band]
    /// 중립 후보로 고른 화소 비율.
    var selectedFraction: Double
    /// 중립 근처에 후보가 거의 없어 장면 중앙 캐스트 주위에서 고른 경우(고전 gray-world).
    /// 장면이 정말 한 색일 수 있으므로 쓰는 쪽이 보정을 줄인다.
    var isFallback = false

    /// 대역 중앙값의 중앙값 — 대역마다 한 표(면적이 큰 대역이 지배하지 않는다).
    var medianCast: SIMD3<Double> {
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return 0 }
            let mid = sorted.count / 2
            return sorted.count % 2 == 0 ? 0.5 * (sorted[mid - 1] + sorted[mid]) : sorted[mid]
        }
        return SIMD3(median(bands.map(\.cast.x)), median(bands.map(\.cast.y)), median(bands.map(\.cast.z)))
    }
}

enum NeutralAxisEstimator {
    /// 중립 후보의 첫 창(ln, ≈0.5 스톱)과 좁힌 창(≈0.25 스톱).
    static let initialWindow = 0.35
    static let refinedWindow = 0.17
    /// 화소가 의미 있는 색을 가지려면 모든 채널이 이 값을 넘어야 한다(인화 토우 0.001 의 4배 —
    /// 그 아래는 양자화·잡음이 비율을 지배한다). 위쪽은 클리핑 근처를 뺀다.
    static let minimumChannel = 0.004
    static let maximumLuminance = 0.90
    static let bandWidth = log(2.0)

    static func measure(_ pixels: [SIMD3<Double>]) -> NeutralAxisEvidence? {
        var logs: [(luminance: Double, cast: SIMD3<Double>)] = []
        logs.reserveCapacity(pixels.count)
        for p in pixels {
            guard p.x > minimumChannel, p.y > minimumChannel, p.z > minimumChannel,
                  0.2126 * p.x + 0.7152 * p.y + 0.0722 * p.z < maximumLuminance else { continue }
            let l = SIMD3(log(p.x), log(p.y), log(p.z))
            let mean = (l.x + l.y + l.z) / 3
            logs.append((mean, l - SIMD3(repeating: mean)))
        }
        guard logs.count >= 64 else { return nil }

        func select(around center: SIMD3<Double>, window: Double) -> [Int] {
            logs.indices.filter {
                let d = logs[$0].cast - center
                return max(abs(d.x), max(abs(d.y), abs(d.z))) < window
            }
        }
        func medianCast(_ indices: [Int]) -> SIMD3<Double> {
            func median(_ values: [Double]) -> Double {
                let sorted = values.sorted()
                return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
            }
            return SIMD3(median(indices.map { logs[$0].cast.x }),
                         median(indices.map { logs[$0].cast.y }),
                         median(indices.map { logs[$0].cast.z }))
        }

        var selected = select(around: .zero, window: initialWindow)
        var isFallback = false
        if selected.count < max(32, logs.count / 20) {
            // 중립 근처 후보가 5% 미만 — 캐스트가 0.5 스톱보다 크거나 장면이 한 색이다.
            selected = select(around: medianCast(Array(logs.indices)), window: initialWindow)
            isFallback = true
        }
        guard selected.count >= 32 else { return nil }
        for _ in 0..<2 {
            selected = select(around: medianCast(selected), window: refinedWindow)
            guard selected.count >= 32 else { return nil }
        }

        // 휘도대(1 스톱)별 중앙값. 표본이 너무 적은 대역은 버린다.
        let minimumBandCount = max(8, selected.count / 200)
        var byBand: [Int: [Int]] = [:]
        for index in selected {
            byBand[Int((logs[index].luminance / bandWidth).rounded(.down)), default: []].append(index)
        }
        let bands = byBand.keys.sorted().compactMap { key -> NeutralAxisEvidence.Band? in
            guard let members = byBand[key], members.count >= minimumBandCount else { return nil }
            let lum = members.map { logs[$0].luminance }.sorted()
            return .init(logLuminance: lum[lum.count / 2], cast: medianCast(members), count: members.count)
        }
        guard !bands.isEmpty else { return nil }
        return NeutralAxisEvidence(bands: bands, selectedFraction: Double(selected.count) / Double(pixels.count),
                                   isFallback: isFallback)
    }
}
