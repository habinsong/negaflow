import Foundation

extension ScannerTargetGrade {
    // MARK: 포지티브(슬라이드/흑백 양화) 시그니처 — 항등 기준 상대 이식
    //
    // 절대 percentile은 롤 장면 내용을 강제하므로 쓰지 않는다. 같은 filmKey만으로도 부족하며,
    // 두 실기의 source roll-label set이 정확히 같을 때만 중점 기준 대칭 차이를 적용한다.
    // 현재 번들 슬라이드는 이 조건을 만족하는 pair가 없으므로 nil/no-op이다. 네거티브 hue를
    // 슬라이드에 재사용하는 교차 타입 prior도 측정 근거가 없으므로 제거한다.

    /// 같은 필름 쌍 톤 차이의 앵커별 클램프 — 포지티브는 충실 재현에서 크게 벗어나지 않는다.
    static let positiveToneDeltaLimit = 0.10
    /// 같은 필름 쌍 중립축 차이 클램프(Lab) — cube 쪽 ±4.0 보다 보수적으로 잡는다.
    static let positiveNeutralDeltaLimit = 3.0

    static func pairedScanner(of scanner: String) -> String? {
        switch scanner {
        case "NORITSU": return "SP-3000"
        case "SP-3000": return "NORITSU"
        default: return nil
        }
    }

    /// 포지티브 시그니처. roll-label matched slide pair가 없으면 nil(패스스루)을 돌려준다.
    static func positiveSignature(
        scanner: String,
        profiles: [ScannerProfile]
    ) -> Signature? {
        let pairs = matchedProfilePairs(scanner: scanner, kind: "color slide", profiles: profiles)
        guard !pairs.isEmpty else { return nil }

        var toneXs = designToneXs
        var tone = toneXs
        // percentile index별 중점과 절반 차이. 여러 pair가 방향을 달리하면 해당 성분은 항등.
        toneXs = (0..<toneKeys.count).map { index in
            let fallback = srgbEncode(designPercentiles[index])
            return clamp(median(pairs.map { pair in
                let mine = clamp(pair.mine.tone[toneKeys[index]]?.median ?? fallback, 0.002, 0.998)
                let other = clamp(pair.other.tone[toneKeys[index]]?.median ?? fallback, 0.002, 0.998)
                return (mine + other) / 2.0
            }) ?? fallback, 0.002, 0.998)
        }
        tone = (0..<toneKeys.count).map { index in
            let fallback = srgbEncode(designPercentiles[index])
            let delta = consistentRelativeMedian(pairs.map { pair in
                let mine = clamp(pair.mine.tone[toneKeys[index]]?.median ?? fallback, 0.002, 0.998)
                let other = clamp(pair.other.tone[toneKeys[index]]?.median ?? fallback, 0.002, 0.998)
                return (mine - other) / 2.0
            })
            return clamp(
                toneXs[index] + clamp(delta, -positiveToneDeltaLimit, positiveToneDeltaLimit),
                0.002,
                0.998
            )
        }

        let neutralBins = relativeNeutralBins(from: pairs).map {
            NeutralBin(
                luma: $0.luma,
                a: clamp($0.a, -positiveNeutralDeltaLimit, positiveNeutralDeltaLimit),
                b: clamp($0.b, -positiveNeutralDeltaLimit, positiveNeutralDeltaLimit)
            )
        }
        let hueAnchors = relativeHueAnchors(from: pairs)

        return Signature(
            toneXs: toneXs,
            tone: tone,
            neutralBins: neutralBins,
            hueAnchors: hueAnchors
        )
    }

}
