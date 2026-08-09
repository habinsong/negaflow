import Foundation

// MARK: - 흑백 네거티브 유제
//
// 네 갈래로 나뉜다. 갈래가 다르면 같은 장면이 다른 그레이로 떨어진다.
//
//   전통 큐빅(Tri-X·HP5·FP4·Kentmere)  긴 토우, 늦게 눕는 숄더, 굵은 입자
//   Core-Shell(Delta)                  곧은 토우, 미세 입자, 높은 선예도
//   T-GRAIN(T-Max)                     Kodak 이 청색 감도를 낮춘 유일한 계열
//   특수 분광(Ortho·SFX·Infrared)      분광 감도 자체가 룩인 유제
//
// 대비(contrastIndex)로 필름을 가르려는 유혹이 있지만 그것은 절반만 맞다. 일반 촬영용
// 네거티브는 표준 현상에서 대개 CI 0.55 부근으로 수렴한다 — 인화지 grade 2 가 그 기울기를
// 정상으로 렌더하도록 만들어졌기 때문이다. 필름을 실제로 가르는 것은 **곡선의 모양**과
// **분광 감도**다. 그래서 아래 값들은 CI 를 좁게 두고 toe/shoulder/가중치를 넓게 벌린다.
//
// 그레인 진폭은 데이터시트 RMS(D=1.0, 48 µm 개구, 12 배 판독)를 그대로 옮긴다. 컬러 반전
// 필름의 RMS 도 같은 조건으로 측정되므로 두 목록이 한 자에 놓인다 — Ektachrome E100 의
// RMS 8 이 진폭 0.026 인 자리에 T-Max 100 의 RMS 8 도 같은 값으로 앉는다.
// Ilford 는 RMS 를 아예 발행하지 않는다(전 제품 문서에서 확인). 그 필름들은 같은 세대·같은
// 감도대의 Kodak 실측치에서 유추하고 `provenance` 로 그 사실을 드러낸다.

public extension BWFilmProfile {

    // MARK: 전통 큐빅 입자

    /// KODAK PROFESSIONAL TRI-X 400 (F-4017).
    ///   - 대비: 권장 현상이 **contrast index 0.56** 을 목표로 한다(데이터시트 명시).
    ///   - 분광: 표준 팬크로. T-Max 계열과 달리 청색 감도를 낮췄다는 언급이 **없다** —
    ///     그래서 맨눈보다 하늘이 밝게 떨어지는 쪽에 남는다.
    ///   - 그레인: RMS **17**(HC-110 B 기준, 데이터시트). 목록의 팬크로 중 굵은 편이다.
    ///   - 해상력은 현행·구판 데이터시트 모두 싣지 않는다 → acutance 는 계열 유추.
    static let triX400 = BWFilmProfile(
        spectralWeights: SIMD3(0.28, 0.32, 0.40),
        contrastIndex: 0.56,
        toeSoftness: 0.72,
        shoulderSoftness: 0.68,
        latitudeStops: 10.0,
        dmaxMultiplier: 1.0,
        grainAmplitude: 0.056,
        grainSize: 1.55,
        grainProvenance: .datasheet,
        acutance: (0.9, 0.05),
        scatterStrength: 0.024,
        halationStrength: 0.012,
        halationRadiusRatio: 0.0040,
        isReversal: false
    )

    /// ILFORD HP5 PLUS 400.
    ///   - 상반칙불궤 Ta = Tm^**1.31**(데이터시트) — 목록에서 가장 큰 지수이고, 그만큼 유제가
    ///     약한 빛에서 느리게 반응한다. 토우를 Tri-X 보다 길게 두는 근거.
    ///   - 베이스: clear acetate + **현상 중 탈색되는 안티할레이션 백킹**(120 기준 명시).
    ///   - RMS 미공개 → Tri-X 실측 17 에서 유추(같은 감도대의 전통 큐빅).
    static let hp5Plus = BWFilmProfile(
        spectralWeights: SIMD3(0.28, 0.33, 0.39),
        contrastIndex: 0.55,
        toeSoftness: 0.75,
        shoulderSoftness: 0.72,
        latitudeStops: 10.5,
        dmaxMultiplier: 1.0,
        grainAmplitude: 0.053,
        grainSize: 1.50,
        grainProvenance: .inferred,
        acutance: (0.9, 0.05),
        scatterStrength: 0.023,
        halationStrength: 0.009,
        halationRadiusRatio: 0.0038,
        isReversal: false
    )

    /// ILFORD FP4 PLUS 125.
    ///   - 관용도: "overexposed by as much as **six stops**, or underexposed by **two stops**"
    ///     (데이터시트 명문). 목록에서 가장 넓은 과노출 관용도이므로 숄더를 가장 길게 둔다.
    ///   - "exceptionally fine grain, medium speed". RMS 미공개.
    static let fp4Plus = BWFilmProfile(
        spectralWeights: SIMD3(0.27, 0.34, 0.39),
        contrastIndex: 0.52,
        toeSoftness: 0.70,
        shoulderSoftness: 0.78,
        latitudeStops: 11.0,
        dmaxMultiplier: 1.0,
        grainAmplitude: 0.032,
        grainSize: 1.15,
        grainProvenance: .inferred,
        acutance: (1.0, 0.11),
        scatterStrength: 0.018,
        halationStrength: 0.007,
        halationRadiusRatio: 0.0035,
        isReversal: false
    )

    /// KENTMERE PAN 400 (Harman 보급 라인).
    ///   - 전통 큐빅 입자. Delta 와 대비되는 지점이다.
    ///   - 데이터시트에 분광 감도 곡선도, 입상성·해상력 수치도 **없다**. 헐레이션을 크게 잡을
    ///     근거 역시 없으므로, 같은 제조사(Harman)의 Ilford 계열과 같은 수준으로 둔다 —
    ///     "염가 설계일 테니 발광이 심할 것"은 추측이지 데이터가 아니다.
    static let kentmere400 = BWFilmProfile(
        spectralWeights: SIMD3(0.29, 0.32, 0.39),
        contrastIndex: 0.60,
        toeSoftness: 0.62,
        shoulderSoftness: 0.56,
        latitudeStops: 8.5,
        dmaxMultiplier: 1.0,
        grainAmplitude: 0.060,
        grainSize: 1.62,
        grainProvenance: .inferred,
        acutance: (0.85, 0.03),
        scatterStrength: 0.027,
        halationStrength: 0.012,
        halationRadiusRatio: 0.0042,
        isReversal: false
    )

    // MARK: Core-Shell (Ilford Delta)

    /// ILFORD DELTA 100 PROFESSIONAL.
    ///   - 상반칙불궤 Ta = Tm^**1.26** — HP5 Plus(1.31)보다 작다. 곧은 토우와 같은 방향의 증거.
    ///   - 특성곡선 기준 현상: ID-11 stock 8½분 / 20 °C.
    ///   - Core-Shell 입자: 미세하고 선예도가 높다. RMS 미공개 → T-Max 100 실측 8 에서 유추.
    static let delta100 = BWFilmProfile(
        spectralWeights: SIMD3(0.28, 0.36, 0.36),
        contrastIndex: 0.54,
        toeSoftness: 0.40,
        shoulderSoftness: 0.46,
        latitudeStops: 8.5,
        dmaxMultiplier: 1.0,
        grainAmplitude: 0.029,
        grainSize: 1.08,
        grainProvenance: .inferred,
        acutance: (1.15, 0.20),
        scatterStrength: 0.015,
        halationStrength: 0.006,
        halationRadiusRatio: 0.0032,
        isReversal: false
    )

    /// ILFORD DELTA 400 PROFESSIONAL. 고감도 Core-Shell.
    ///   - 특성곡선 기준 현상: ID-11 stock 8분 / 24 °C.
    static let delta400 = BWFilmProfile(
        spectralWeights: SIMD3(0.28, 0.36, 0.36),
        contrastIndex: 0.56,
        toeSoftness: 0.42,
        shoulderSoftness: 0.48,
        latitudeStops: 9.0,
        dmaxMultiplier: 1.0,
        grainAmplitude: 0.037,
        grainSize: 1.32,
        grainProvenance: .inferred,
        acutance: (1.05, 0.14),
        scatterStrength: 0.020,
        halationStrength: 0.008,
        halationRadiusRatio: 0.0038,
        isReversal: false
    )

    /// ILFORD DELTA 3200 PROFESSIONAL.
    ///   - 실제 감도는 **ISO 1000/31°**(데이터시트 명문)이고 권장 EI 가 3200 이다. 즉 이 필름의
    ///     정체는 "매우 빠른 필름"이 아니라 "증감 현상을 전제로 설계된 필름"이고, 그래서 대비가
    ///     서고 관용도가 좁다.
    ///   - **Ilford 제품 중 유일하게 안티할레이션 백킹 서술이 없다**(35mm·120 모두 베이스만 기술).
    ///     이 유제에서만 명부 번짐이 두드러지는 관측과 맞물린다 — 목록에서 헐레이션을 크게
    ///     잡는 근거가 있는 몇 안 되는 필름이다.
    static let delta3200 = BWFilmProfile(
        spectralWeights: SIMD3(0.29, 0.35, 0.36),
        contrastIndex: 0.64,
        toeSoftness: 0.34,
        shoulderSoftness: 0.40,
        latitudeStops: 7.0,
        dmaxMultiplier: 1.0,
        grainAmplitude: 0.055,
        grainSize: 1.95,
        grainProvenance: .inferred,
        acutance: (0.8, 0.02),
        scatterStrength: 0.030,
        halationStrength: 0.028,
        halationRadiusRatio: 0.0058,
        isReversal: false
    )

    // MARK: T-GRAIN (Kodak T-Max) — 청색 감도를 낮춘 유일한 계열

    /// KODAK PROFESSIONAL T-MAX 100.
    ///   - Kodak 데이터시트 명문: 청색 감도가 다른 팬크로보다 낮아 "response … closer to the
    ///     response of the human eye" 이며 "**blues may be recorded as slightly darker tones**".
    ///     이 문장이 T-Max 계열만 가중치를 Rec.709 쪽으로 기울이는 유일한 근거다. 노란 필터를
    ///     끼운 것과 같은 방향이라 하늘이 다른 흑백 필름보다 어둡게 떨어진다.
    ///   - 그레인 RMS **8**(D-76), 해상력 **200 lines/mm**(1000:1) / 63(1.6:1) — 목록 최고.
    static let tmax100 = BWFilmProfile(
        spectralWeights: SIMD3(0.30, 0.44, 0.26),
        contrastIndex: 0.55,
        toeSoftness: 0.34,
        shoulderSoftness: 0.42,
        latitudeStops: 8.5,
        dmaxMultiplier: 1.0,
        grainAmplitude: 0.026,
        grainSize: 1.02,
        grainProvenance: .datasheet,
        acutance: (1.25, 0.26),
        scatterStrength: 0.013,
        halationStrength: 0.005,
        halationRadiusRatio: 0.0030,
        isReversal: false
    )

    /// KODAK PROFESSIONAL T-MAX 400.
    ///   - RMS **10**(D-76), 해상력 **200 lines/mm**(1000:1) / 50(1.6:1).
    ///   - EI 800 까지 정상 현상으로 품질을 유지한다(데이터시트).
    static let tmax400 = BWFilmProfile(
        spectralWeights: SIMD3(0.30, 0.43, 0.27),
        contrastIndex: 0.57,
        toeSoftness: 0.36,
        shoulderSoftness: 0.44,
        latitudeStops: 9.0,
        dmaxMultiplier: 1.0,
        grainAmplitude: 0.033,
        grainSize: 1.28,
        grainProvenance: .datasheet,
        acutance: (1.25, 0.24),
        scatterStrength: 0.018,
        halationStrength: 0.007,
        halationRadiusRatio: 0.0036,
        isReversal: false
    )

    /// KODAK PROFESSIONAL T-MAX P3200.
    ///   - 실제 감도는 **EI 800~1000**(현상액에 따라)이고 표기가 3200 이다. Delta 3200 과 같은
    ///     성격이지만 입자가 굵고 대비가 더 선다.
    ///   - RMS **18**(D-76) — 목록에서 가장 굵다. 해상력 125 / 40 으로 가장 낮다.
    static let tmaxP3200 = BWFilmProfile(
        spectralWeights: SIMD3(0.30, 0.42, 0.28),
        contrastIndex: 0.66,
        toeSoftness: 0.30,
        shoulderSoftness: 0.36,
        latitudeStops: 6.5,
        dmaxMultiplier: 1.0,
        grainAmplitude: 0.059,
        grainSize: 2.05,
        grainProvenance: .datasheet,
        acutance: (0.9, 0.06),
        scatterStrength: 0.032,
        halationStrength: 0.014,
        halationRadiusRatio: 0.0050,
        isReversal: false
    )

    // MARK: 특수 분광

    /// ILFORD ORTHO PLUS 80. 오소크로매틱 — 적색 무감도.
    ///   - 적색 암실등을 켜 둘 수 있을 만큼 적색에 반응하지 않는다. 그 사실이 곧 가중치다:
    ///     R ≈ 0. 붉은 입술·벽돌·단풍이 검게 떨어지고 푸른 하늘은 하얗게 뜬다.
    ///   - 데이터시트 명문: "**Gbar 0.62–0.70 이 in-camera 정상 대비**"(ID-11). 목록에서 대비의
    ///     정상 범위가 숫자로 주어진 몇 안 되는 필름이라 CI 를 그 하단에 맞춘다.
    ///   - ISO 80 주광 / ISO 40 텅스텐 — 광원에 따라 감도가 갈리는 것 자체가 오소의 증거다.
    static let orthoPlus = BWFilmProfile(
        spectralWeights: SIMD3(0.02, 0.42, 0.56),
        contrastIndex: 0.62,
        toeSoftness: 0.46,
        shoulderSoftness: 0.50,
        latitudeStops: 7.0,
        dmaxMultiplier: 1.0,
        grainAmplitude: 0.027,
        grainSize: 1.06,
        grainProvenance: .inferred,
        acutance: (1.15, 0.19),
        scatterStrength: 0.014,
        halationStrength: 0.006,
        halationRadiusRatio: 0.0033,
        isReversal: false
    )

    /// ILFORD SFX 200. 확장 적감.
    ///   - 데이터시트 명문: "peak red sensitivity at **720 nm**, extended red sensitivity up to
    ///     **740 nm**". 하늘이 어둡게 가라앉고 잎사귀가 밝게 뜬다(Wood 효과의 약한 형태).
    ///   - 베이스: "**grey acetate base which gives good halation protection**" — Ilford 제품 중
    ///     유일하게 회색 베이스를 명시한다. 확장 적감 유제인데도 발광이 적은 이유이고,
    ///     Rollei 계열과 갈리는 지점이다.
    static let sfx200 = BWFilmProfile(
        spectralWeights: SIMD3(0.46, 0.30, 0.24),
        contrastIndex: 0.54,
        toeSoftness: 0.52,
        shoulderSoftness: 0.56,
        latitudeStops: 8.0,
        dmaxMultiplier: 1.0,
        grainAmplitude: 0.034,
        grainSize: 1.30,
        grainProvenance: .inferred,
        acutance: (1.0, 0.11),
        scatterStrength: 0.020,
        halationStrength: 0.005,
        halationRadiusRatio: 0.0038,
        isReversal: false
    )

    /// ROLLEI INFRARED 400.
    ///   - 분광: 데이터시트 표제가 "special infrared film up to **820 nm**" 인데, 현행 제품
    ///     페이지는 "hyperpanchromatic, **650–750 nm**" 라고 적는다. 제조사 안에서 수치가
    ///     엇갈리므로 적감이 목록에서 가장 크다는 **순위만** 쓴다.
    ///   - 대비: 현상표가 **평균 대비 γ = 0.65**(20 °C)를 기준으로 짜여 있다.
    ///   - RMS **11.0**, 해상력 **160 Lp/mm**.
    ///   - 베이스가 "crystal-clear synthetic carrier" 이고 데이터시트가 아예
    ///     "**Special AURA effects by over exposing film**" 을 표제로 내건다. 즉 헐레이션 발광이
    ///     결함이 아니라 제조사가 공인한 이 필름의 서명이다 — 목록에서 가장 크게 잡는다.
    static let rolleiIR = BWFilmProfile(
        spectralWeights: SIMD3(0.60, 0.22, 0.18),
        contrastIndex: 0.65,
        toeSoftness: 0.54,
        shoulderSoftness: 0.58,
        latitudeStops: 7.5,
        dmaxMultiplier: 1.0,
        grainAmplitude: 0.036,
        grainSize: 1.35,
        grainProvenance: .datasheet,
        acutance: (1.1, 0.16),
        scatterStrength: 0.022,
        halationStrength: 0.040,
        halationRadiusRatio: 0.0072,
        isReversal: false
    )
}
