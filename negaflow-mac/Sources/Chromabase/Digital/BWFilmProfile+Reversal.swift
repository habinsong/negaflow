import Foundation

// MARK: - 흑백 반전(슬라이드) 유제
//
// 흑백 반전은 흑백 네거티브를 흑백으로 바꾼 것이 아니다. 네거티브는 인화지가 뒤를 받쳐
// 대비를 되살려 주지만, 반전은 필름 자체가 최종물이라 받쳐 줄 매체가 없다. 그래서
//
//   • 밀도 범위가 훨씬 넓고(깊은 검정), 대비가 컬러 슬라이드급으로 선다
//   • 관용도가 좁아 과노출이 빨리 하얗게 날아간다
//   • 토우와 숄더가 급하다 — 양 끝의 계조 여유가 거의 없다
//
// 컬러에서 슬라이드와 네거티브를 나눈 것과 정확히 같은 근거다.

public extension BWFilmProfile {

    /// AGFA SCALA 200X. 흑백 반전 중 유일하게 1차 데이터시트가 확보된 유제다.
    ///   - "contrast matched to AGFACHROME RSX 100" — 즉 대비 기준이 흑백 네거티브가 아니라
    ///     **컬러 슬라이드**다. 이 한 문장이 CI 를 네거티브 계열의 0.55 대가 아니라 0.8 대에
    ///     두는 근거이며, 이 필름이 흑백 슬라이드다운 이유 전부이기도 하다.
    ///   - RMS 11(D=1.0, visual filter), 해상력 120 lp/mm(1000:1) / 50 lp/mm(1.6:1) — 모두 A등급.
    ///   - 분광: 표준 팬크로.
    static let scala200X = BWFilmProfile(
        spectralWeights: SIMD3(0.28, 0.34, 0.38),
        contrastIndex: 0.82,
        toeSoftness: 0.24,
        shoulderSoftness: 0.22,
        latitudeStops: 4.5,
        dmaxMultiplier: 1.85,
        grainAmplitude: 0.028,
        grainSize: 1.22,
        grainProvenance: .datasheet,
        acutance: (1.1, 0.17),
        scatterStrength: 0.016,
        halationStrength: 0.007,
        halationRadiusRatio: 0.0032,
        isReversal: true
    )

    /// ROLLEI SUPERPAN 200. 확장 적감이면서 반전 현상을 지원하는 드문 유제.
    ///   - "higher film speed in IR than Rollei IR 820/400" 이 데이터시트의 표현이므로
    ///     적감이 SFX 200 과 Infrared 400 사이에 놓인다.
    ///   - 여기서는 반전 현상 기준으로 모델링한다(흑백 슬라이드 그룹에 두는 이유). 다만
    ///     본래 네거티브 설계라 Scala 만큼 대비가 서지는 않아 관용도를 조금 더 남긴다.
    ///   - Rollei 계열 공통으로 베이스가 투명해 헐레이션이 크다.
    static let rolleiSuperpan = BWFilmProfile(
        spectralWeights: SIMD3(0.42, 0.31, 0.27),
        contrastIndex: 0.72,
        toeSoftness: 0.32,
        shoulderSoftness: 0.30,
        latitudeStops: 5.5,
        dmaxMultiplier: 1.60,
        grainAmplitude: 0.024,
        grainSize: 1.26,
        grainProvenance: .inferred,
        acutance: (1.05, 0.14),
        scatterStrength: 0.019,
        halationStrength: 0.026,
        halationRadiusRatio: 0.0058,
        isReversal: true
    )
}
