import Foundation

// MARK: - 네거티브(C-41) 프로파일
//
// 네거티브는 필름 자체가 최종 결과물이 아니다. 그래서 여기 계수는 "그 필름을 정상 노출로 찍어
// 인화/스캔했을 때의 렌더된 응답"을 모델링한다. 슬라이드 대비 공통 성질:
//   • 대비가 낮다 — 데이터시트 특성곡선의 straight-line gamma 자체가 반전 필름보다 완만하다.
//   • 토우가 들려 있다(black < 0) — 긴 toe = 넓은 섀도우 관용도. 관용도가 넓다고 서술된 필름일수록
//     더 들린다(Portra 800 "best-in-class underexposure latitude" > Portra 400 > ColorPlus).
//   • 채도가 절제돼 있다 — 인화 단계에서 올리는 것을 전제로 설계된다. 예외가 Ektar(고채도 지향).

extension FilmEmulationProfile {

    /// KODAK PROFESSIONAL PORTRA 160 (E-4051).
    /// "significantly finer grain structure for improved scanning and enlargement capability",
    /// "smooth and natural skin tone reproduction", 인물/패션/상업용. Portra 3형제 중 가장 낮은
    /// 대비·채도이고 입자가 가장 곱다.
    ///   - 톤: 매우 낮은 대비 + 리프트된 토우.
    ///   - 매트릭스: 거의 중립(대각 ~1.015). 스킨 보호가 설계 목표라 R 행을 가장 덜 건드린다.
    ///   - 크로스오버: 하이라이트만 아주 옅게 웜(Kodak 계열 공통), 섀도우는 중립에 가깝게.
    ///   - acutance: Portra 3형제 중 가장 높다(가장 고운 입자).
    static let portra160 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.06, black: -0.020, white: 0.995, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.06, black: -0.020, white: 0.995, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.06, black: -0.019, white: 0.995, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.015, -0.009, -0.006),
        mG: SIMD3(-0.007,  1.016, -0.009),
        mB: SIMD3(-0.006, -0.010,  1.016),
        shadowTint: SIMD3(-0.002, 0.000, 0.004),
        highlightTint: SIMD3(0.006, 0.002, -0.004),
        iie: 0.03,
        //        R     Y     G     C     B     M
        iieHue: [0.00, 0.02, 0.02, 0.00, 0.00, 0.00],
        acutance: (1.0, 0.08)
    )

    /// KODAK PROFESSIONAL PORTRA 400 (E-4050).
    /// 인물·패션 표준. VISION Film Technology 기반이고, 자연스러운 색 재현에 스킨을 위해 웜 쪽으로
    /// 살짝 기운다는 것이 일관된 서술이다. 넓은 노출 관용도.
    ///   - 톤: 160 보다 아주 조금 높은 대비, 토우는 더 들림(관용도가 더 넓다).
    ///   - 매트릭스: 여전히 절제된 채도(대각 ~1.025).
    ///   - 크로스오버: 하이라이트 웜(160 보다 명확).
    static let portra400 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.09, black: -0.024, white: 0.995, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.09, black: -0.024, white: 0.995, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.09, black: -0.022, white: 0.995, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.025, -0.014, -0.011),
        mG: SIMD3(-0.011,  1.026, -0.015),
        mB: SIMD3(-0.009, -0.016,  1.025),
        shadowTint: SIMD3(-0.002, 0.000, 0.004),
        highlightTint: SIMD3(0.009, 0.003, -0.007),
        iie: 0.04,
        //        R     Y     G     C     B     M
        iieHue: [0.00, 0.03, 0.02, 0.00, 0.00, 0.00],
        acutance: (1.0, 0.05)
    )

    /// KODAK PROFESSIONAL PORTRA 800 (E-4040).
    /// "well balanced color saturation", "very fine grain", "best-in-class underexposure latitude",
    /// "natural skin tone reproduction and enhanced color in the most difficult lighting".
    /// Portra 400 보다 대비·채도가 조금 높고 노란기가 더 있다는 것이 일관된 관측이다.
    ///   - 톤: Portra 중 가장 높은 대비 + 가장 많이 들린 토우(언더 관용도 최고).
    ///   - 매트릭스: 대각 ~1.055 로 Portra 중 가장 높지만 여전히 Ektar 보다 훨씬 낮다.
    ///   - 크로스오버: 하이라이트 웜/옐로가 뚜렷.
    ///   - acutance: 감도가 가장 높아 입자가 굵다 → 엣지 강조를 가장 약하게.
    static let portra800 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.13, black: -0.028, white: 0.993, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.13, black: -0.028, white: 0.993, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.13, black: -0.026, white: 0.993, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.055, -0.032, -0.023),
        mG: SIMD3(-0.024,  1.054, -0.030),
        mB: SIMD3(-0.020, -0.034,  1.054),
        shadowTint: SIMD3(0.002, 0.000, 0.002),
        highlightTint: SIMD3(0.015, 0.006, -0.013),
        iie: 0.07,
        //        R     Y     G     C     B     M
        iieHue: [0.02, 0.05, 0.02, 0.00, 0.00, 0.00],
        acutance: (1.0, 0.03)
    )

    /// KODAK PROFESSIONAL EKTAR 100 (E-4046).
    /// "world's finest grain color negative film", "high saturation and ultra-vivid color",
    /// Micro-Structure Optimized T-GRAIN(스캔 지향), DIR 커플러. 용도에서 인물이 빠져 있다.
    /// 섀도우 관용도가 Portra 보다 좁고, 언더노출 시 블루-시안 캐스트가 잘 뜬다는 관측이 일관된다.
    ///   - 톤: 네거티브 중 가장 높은 대비, 토우를 들지 않는다(관용도가 좁다).
    ///   - 매트릭스: 네거티브 중 최고 채도(대각 ~1.135). 블루·레드를 특히 세운다.
    ///   - 크로스오버: 섀도우 블루-시안(필름 고유 특성이자 사용자가 실제로 마주치는 얼굴).
    ///   - acutance: "finest grain" 이라 네거티브 중 가장 강하게.
    static let ektar100 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.26, black: 0.006, white: 0.99, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.26, black: 0.006, white: 0.99, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.27, black: 0.007, white: 0.99, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.135, -0.078, -0.057),
        mG: SIMD3(-0.060,  1.130, -0.070),
        mB: SIMD3(-0.045, -0.095,  1.140),
        shadowTint: SIMD3(-0.011, 0.000, 0.019),
        highlightTint: SIMD3(-0.002, 0.000, 0.004),
        iie: 0.16,
        //        R     Y     G     C     B     M
        iieHue: [0.10, 0.00, 0.10, 0.06, 0.16, 0.04],
        acutance: (1.0, 0.16)
    )

    /// KODAK ULTRAMAX 400 (E-7023).
    /// "fine grain, vivid color saturation, sharp detail, consistent color reproduction",
    /// "wide exposure latitude", T-GRAIN + optimized color precision, 스킨톤 최적화. 소비자용
    /// 이라 Portra 보다 확실히 채도가 높고 웜하다. 과노출 시 옐로로 기우는 경향이 보고된다.
    ///   - 톤: 중간 대비 + 넓은 관용도(토우 리프트).
    ///   - 매트릭스: 중상 채도(대각 ~1.085).
    ///   - 크로스오버: 하이라이트 웜-옐로가 Portra 보다 강하다.
    ///   - acutance: ISO 400 소비자용이라 입자가 굵다 → 약하게.
    static let ultramax400 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.15, black: -0.014, white: 0.993, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.15, black: -0.014, white: 0.993, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.15, black: -0.013, white: 0.993, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.085, -0.050, -0.035),
        mG: SIMD3(-0.040,  1.080, -0.040),
        mB: SIMD3(-0.032, -0.053,  1.085),
        shadowTint: SIMD3(0.003, 0.000, 0.002),
        highlightTint: SIMD3(0.015, 0.008, -0.015),
        iie: 0.10,
        //        R     Y     G     C     B     M
        iieHue: [0.04, 0.08, 0.03, 0.00, 0.02, 0.00],
        acutance: (1.0, 0.04)
    )

    /// Kodak ColorPlus 200.
    /// 제조사 기술 데이터시트가 공개되지 않은 보급형이라, 여기 계수는 제품 정보와 반복 관측되는
    /// 성질만 반영한다: UltraMax 보다 곱은 입자, 좁은 노출 관용도, 따뜻하고 클래식한 색.
    ///   - 톤: 중간 대비, 관용도가 좁아 토우를 조금만 든다.
    ///   - 매트릭스: 중간 채도(대각 ~1.055) — UltraMax 보다 낮게.
    ///   - 크로스오버: 웜 하이라이트 + 살짝 웜하게 들린 섀도우(빈티지한 인상의 실체).
    static let colorPlus200 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.13, black: -0.010, white: 0.99, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.13, black: -0.010, white: 0.99, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.13, black: -0.009, white: 0.99, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.055, -0.033, -0.022),
        mG: SIMD3(-0.026,  1.052, -0.026),
        mB: SIMD3(-0.022, -0.035,  1.057),
        shadowTint: SIMD3(0.007, 0.002, 0.000),
        highlightTint: SIMD3(0.014, 0.006, -0.011),
        iie: 0.07,
        //        R     Y     G     C     B     M
        iieHue: [0.03, 0.06, 0.02, 0.00, 0.00, 0.00],
        acutance: (1.0, 0.07)
    )

    /// FUJICOLOR C200 (AF3-0249E).
    /// "excellent grain quality", "wide exposure latitude", 사진·처리 특성은 SUPERIA 200 과
    /// 거의 같다고 제조사가 명시. Fuji 계열 공통으로 Kodak 보다 쿨하고 그린이 확장되며, 중간톤~
    /// 하이라이트가 마젠타로 기운다는 관측이 반복된다.
    ///   - 톤: 중간 대비 + 넓은 관용도.
    ///   - 매트릭스: 중간 채도. G 행 대각을 가장 높여 그린을 확장한다(Fuji 시그니처).
    ///   - 크로스오버: 쿨-그린 섀도우 + 마젠타 하이라이트.
    static let fujicolorC200 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.16, black: -0.012, white: 0.992, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.16, black: -0.012, white: 0.992, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.17, black: -0.011, white: 0.992, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.070, -0.042, -0.028),
        mG: SIMD3(-0.030,  1.085, -0.055),
        mB: SIMD3(-0.028, -0.050,  1.078),
        shadowTint: SIMD3(-0.007, 0.006, 0.006),
        highlightTint: SIMD3(0.008, -0.005, 0.009),
        iie: 0.09,
        //        R     Y     G     C     B     M
        iieHue: [0.02, 0.00, 0.14, 0.06, 0.08, 0.06],
        acutance: (1.0, 0.06)
    )

    /// FUJICOLOR PRO 400H (AF3-176E).
    /// "faithful reproduction of neutral grays ... over a wide exposure range from under- to
    /// over-exposure", "superb skin tones with smoothly continuous gradation from highlights to
    /// shadows". RGB 3층에 시안/마젠타 감광 4번째 층을 더한 것이 이 필름의 정체성이고, 2021 년
    /// 단종 사유도 그 층의 재료였다. 연조·저채도·중립이 핵심이며 하이라이트가 민트로 기운다.
    ///   - 톤: 목록에서 가장 낮은 대비 + 넓게 들린 토우.
    ///   - 매트릭스: 거의 중립(대각 ~1.005) — "neutral grays" 를 문자 그대로 지킨다.
    ///   - 크로스오버: 하이라이트 쿨-그린(민트), 섀도우는 중립.
    static let pro400H = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.05, black: -0.026, white: 0.99, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.05, black: -0.026, white: 0.99, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.05, black: -0.026, white: 0.99, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.005, -0.003, -0.002),
        mG: SIMD3(-0.002,  1.005, -0.003),
        mB: SIMD3(-0.002, -0.004,  1.006),
        shadowTint: .zero,
        highlightTint: SIMD3(-0.003, 0.002, 0.001),
        iie: 0.02,
        //        R     Y     G     C     B     M
        iieHue: [0.00, 0.00, 0.04, 0.04, 0.02, 0.00],
        acutance: (1.0, 0.04)
    )
}
