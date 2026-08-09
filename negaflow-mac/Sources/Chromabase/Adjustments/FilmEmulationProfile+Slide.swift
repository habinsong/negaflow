import Foundation

// MARK: - 슬라이드(E-6) 프로파일
//
// 슬라이드는 필름 자체가 최종 관측 대상이라 데이터시트 곡선이 곧 응답이다. 세 필름의 상대 위치는
// 제조사 문구가 그대로 순서를 정해 준다: E100(중립·저대비) < Provia 100F(중간) < Velvia 50(최대 채도).

extension FilmEmulationProfile {

    /// Kodak EKTACHROME E100 (E-4000).
    /// "low contrast tonal scale", "matched color records for a neutral tone scale", "consistent
    /// gray scale rendition throughout the tonal range", "moderately enhanced color saturation",
    /// "pleasing natural skin". 저대비·넓은 관용도·중립.
    ///   - 톤: 낮은 대비, 채널 균등(전 계조 뉴트럴). 섀도우 살짝 리프트(관용도).
    ///   - 매트릭스: 절제된 채도(대각 ~1.055). 스킨 보호 위해 R 은 특히 약하게.
    ///   - 크로스오버: 미세 쿨. E100 의 "약간 쿨/클린".
    static let ektachromeE100 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.20, black: -0.014, white: 1.0, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.20, black: -0.014, white: 1.0, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.21, black: -0.012, white: 1.0, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.055, -0.030, -0.025),
        mG: SIMD3(-0.020,  1.055, -0.035),
        mB: SIMD3(-0.018, -0.032,  1.050),
        shadowTint: SIMD3(-0.004, 0.000, 0.009),
        highlightTint: SIMD3(-0.003, 0.000, 0.005),
        iie: 0.08,
        //        R     Y     G     C     B     M
        iieHue: [0.00, 0.00, 0.03, 0.05, 0.05, 0.00],
        acutance: (1.0, 0.12)
    )

    /// FUJICHROME PROVIA 100F Professional [RDPIII] (AF3-036E).
    /// "ultra-high-quality", "the finest grain (RMS 8) among ISO 100 color reversal films",
    /// "extremely high sharpness", "rich gradation", "vivid and faithful color reproduction",
    /// "well-controlled gradation balance". E100 보다 채도·대비가 있고 Velvia 보다 훨씬 절제됐다.
    ///   - 톤: 중간 대비. 슬라이드지만 관용도가 E100 보다 조금 낫다는 평가라 토우를 과하게 안 막는다.
    ///   - 매트릭스: 중간 채도(대각 ~1.10). "faithful" 이라 hue 회전은 최소.
    ///   - 크로스오버: 거의 중립 + 아주 옅은 쿨 섀도우(데이라이트 밸런스).
    ///   - acutance: RMS 8 + 초고선예도라 슬라이드 중 상위(단 Velvia 만큼 거칠게 밀지 않는다).
    static let provia100F = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.30, black: 0.012, white: 0.995, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.30, black: 0.012, white: 0.995, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.31, black: 0.013, white: 0.993, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.105, -0.058, -0.047),
        mG: SIMD3(-0.042,  1.100, -0.058),
        mB: SIMD3(-0.035, -0.065,  1.100),
        shadowTint: SIMD3(-0.005, 0.000, 0.010),
        highlightTint: SIMD3(0.002, 0.000, -0.002),
        iie: 0.16,
        //        R     Y     G     C     B     M
        iieHue: [0.03, 0.00, 0.10, 0.05, 0.10, 0.02],
        acutance: (1.1, 0.20)
    )

    /// FUJICHROME Velvia 50 [RVP50] (AF3-0221E2).
    /// "world's highest color saturation", 고대비·딥 섀도우, 그린·레드 강조 + 블루 극대화 + 마젠타
    /// 부가, 스킨 마젠타 경향, 섀도우 쿨. MTF 100% 초과.
    ///   - 톤: 강한 대비, 딥 블랙. 색 크로스오버는 톤이 아니라 아래 틴트로 제어. 블루만 살짝 대비↑.
    ///   - 매트릭스: 강한 채도(대각 ~1.20~1.22) + hue 회전. G 는 블루를 더 빼 옐로-그린(시그니처),
    ///     B 는 그린을 더 빼 퓨어/딥 블루, R 은 딥 레드.
    ///   - 크로스오버: 쿨 섀도우 + 웜 하이라이트(Velvia 시그니처).


    /// FUJICHROME Velvia 100 [RVP100] (AF3-131E).
    /// Velvia 50 보다 중립적이고 자연스러운 채도. Provia 보다는 높고 Velvia 50 보다는 낮은 포지션.
    ///   - 톤: 중상 대비, Velvia 50 보다 완만.
    ///   - 매트릭스: 중상 채도(대각 ~1.14).
    ///   - 크로스오버: 약한 쿨 섀도우 + 웜 하이라이트(Velvia 시그니처 약화판).
    static let velvia100 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.40, black: 0.024, white: 0.992, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.40, black: 0.024, white: 0.992, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.42, black: 0.025, white: 0.990, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.145, -0.080, -0.065),
        mG: SIMD3(-0.055,  1.140, -0.085),
        mB: SIMD3(-0.040, -0.110,  1.150),
        shadowTint: SIMD3(-0.008, -0.002, 0.014),
        highlightTint: SIMD3(0.010, 0.003, -0.008),
        iie: 0.24,
        iieHue: [0.08, 0.00, 0.15, 0.04, 0.18, 0.10],
        acutance: (1.15, 0.20)
    )

    /// Kodak EKTACHROME E100VS (E-163, 단종).
    /// "most vivid, saturated colors available in 100-speed transparency film".
    /// Velvia 50 와 비슷한 채도 지향이지만 Kodak 계열의 색 방향(더 중립적 베이스에 채도 추가).
    ///   - 톤: 강한 대비, 딥 블랙. Velvia 만큼 극단적이지는 않음.
    ///   - 매트릭스: 강한 채도(대각 ~1.18).
    ///   - 크로스오버: Kodak 슬라이드의 쿨 시그니처.
    ///   - 상반칙불궤: 1/10,000s~10s 무보정 (A등급).
    static let e100VS = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.42, black: 0.028, white: 0.99, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.42, black: 0.028, white: 0.99, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.44, black: 0.030, white: 0.988, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.180, -0.100, -0.080),
        mG: SIMD3(-0.065,  1.175, -0.110),
        mB: SIMD3(-0.045, -0.135,  1.180),
        shadowTint: SIMD3(-0.008, 0.000, 0.014),
        highlightTint: SIMD3(0.012, 0.003, -0.008),
        iie: 0.26,
        iieHue: [0.10, 0.00, 0.14, 0.06, 0.18, 0.10],
        acutance: (1.1, 0.18)
    )

    /// FUJICHROME Astia 100F (단종).
    /// 인물·패션용 저대비·저채도 슬라이드. "soft skin tones" 가 설계 목표.
    ///   - 톤: 슬라이드 중 가장 낮은 대비, 가장 넓은 관용도.
    ///   - 매트릭스: 절제된 채도(대각 ~1.06). R/G/B 균형이 가장 중립적.
    ///   - 크로스오버: 거의 중립.
    static let astia100F = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.16, black: -0.010, white: 1.0, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.16, black: -0.010, white: 1.0, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.17, black: -0.008, white: 1.0, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.060, -0.034, -0.026),
        mG: SIMD3(-0.024,  1.058, -0.034),
        mB: SIMD3(-0.020, -0.036,  1.056),
        shadowTint: SIMD3(-0.003, 0.000, 0.006),
        highlightTint: SIMD3(0.004, 0.001, -0.002),
        iie: 0.06,
        iieHue: [0.00, 0.00, 0.02, 0.03, 0.03, 0.00],
        acutance: (1.0, 0.14)
    )

    /// Kodachrome 64 (단종, K-14).
    /// 전설적인 아카이브 필름. 강한 대비, 깊은 적색·청색, 중립적 스킨.
    ///   - 톤: 중상 대비, 깊은 블랙.
    ///   - 매트릭스: 고유한 색 분리(비매트릭스, K-14의 첨가 색 시스템).
    ///     데이터시트가 없으므로 반복 관측되는 성질만 반영.
    static let kodachrome64 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.38, black: 0.022, white: 0.99, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.38, black: 0.022, white: 0.99, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.40, black: 0.024, white: 0.988, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.160, -0.090, -0.070),
        mG: SIMD3(-0.060,  1.150, -0.090),
        mB: SIMD3(-0.040, -0.120,  1.160),
        shadowTint: SIMD3(-0.010, -0.003, 0.018),
        highlightTint: SIMD3(0.008, 0.002, -0.006),
        iie: 0.20,
        iieHue: [0.10, 0.00, 0.06, 0.02, 0.18, 0.08],
        acutance: (1.2, 0.22)
    )

    static let velvia50 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.50, black: 0.034, white: 0.99,  lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.50, black: 0.034, white: 0.99,  lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.53, black: 0.036, white: 0.985, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.220, -0.120, -0.100),
        mG: SIMD3(-0.080,  1.205, -0.125),
        mB: SIMD3(-0.055, -0.165,  1.220),
        shadowTint: SIMD3(-0.012, -0.004, 0.020),
        highlightTint: SIMD3(0.016, 0.004, -0.012),
        iie: 0.32,
        //        R     Y     G     C     B     M
        iieHue: [0.12, 0.00, 0.20, 0.06, 0.24, 0.14],
        acutance: (1.2, 0.22)
    )
}
