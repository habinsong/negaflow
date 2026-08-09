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

    /// KODAK Gold 200 (E-7022).
    /// "outstanding combination of color saturation, fine grain, and high sharpness".
    /// "wide exposure latitude—from two stops underexposure to three stops overexposure".
    ///   - 톤: 중간 대비. 소비자용이라 Portra 보다 대비가 있고 토우가 덜 들림.
    ///   - 매트릭스: 중상 채도(대각 ~1.07). 따뜻하고 금빛이 도는 전형적 Kodak 소비자용.
    ///   - 크로스오버: 웜 하이라이트 + 살짝 웜 섀도우.
    static let gold200 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.12, black: -0.008, white: 0.992, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.12, black: -0.008, white: 0.992, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.12, black: -0.007, white: 0.992, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.070, -0.042, -0.028),
        mG: SIMD3(-0.032,  1.065, -0.033),
        mB: SIMD3(-0.026, -0.044,  1.070),
        shadowTint: SIMD3(0.005, 0.001, 0.001),
        highlightTint: SIMD3(0.012, 0.005, -0.009),
        iie: 0.07,
        iieHue: [0.03, 0.06, 0.02, 0.00, 0.00, 0.00],
        acutance: (1.0, 0.06)
    )

    /// KODAK Pro Image 100 (E4006).
    /// 전문가용 Kodak 컬러 네거티브. 따뜻한 톤, 정확한 스킨 재현.
    ///   - 톤: 중간 대비, Portra 160 보다 약간 높음.
    ///   - 매트릭스: 중간 채도, Portra 보다 따뜻한 방향.
    static let proImage100 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.10, black: -0.016, white: 0.994, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.10, black: -0.016, white: 0.994, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.10, black: -0.014, white: 0.994, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.040, -0.024, -0.016),
        mG: SIMD3(-0.018,  1.038, -0.020),
        mB: SIMD3(-0.014, -0.028,  1.042),
        shadowTint: SIMD3(0.003, 0.001, 0.002),
        highlightTint: SIMD3(0.010, 0.004, -0.007),
        iie: 0.05,
        iieHue: [0.01, 0.03, 0.01, 0.00, 0.00, 0.00],
        acutance: (1.0, 0.07)
    )

    /// FUJICOLOR Superia X-TRA 400.
    /// 4번째 감광층(시안) 포함. Fuji 시그니처: 쿨-그린 섀도우, 마젠타 하이라이트.
    ///   - 톤: 중간 대비, 넓은 관용도.
    ///   - 매트릭스: 중상 채도, Fuji 특유의 그린 확장.
    ///   - 크로스오버: 쿨-그린 섀도우 + 마젠타 하이라이트.
    static let superia400 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.14, black: -0.010, white: 0.993, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.14, black: -0.010, white: 0.993, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.15, black: -0.009, white: 0.993, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.075, -0.044, -0.031),
        mG: SIMD3(-0.033,  1.090, -0.057),
        mB: SIMD3(-0.030, -0.054,  1.084),
        shadowTint: SIMD3(-0.005, 0.004, 0.005),
        highlightTint: SIMD3(0.006, -0.003, 0.007),
        iie: 0.08,
        iieHue: [0.02, 0.00, 0.12, 0.05, 0.07, 0.05],
        acutance: (1.0, 0.05)
    )

    /// FUJICOLOR Superia Premium 400 (일본 내수).
    /// Superia 400 보다 더 정제된 그레인, 중립적 색.
    static let superiaPremium400 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.12, black: -0.014, white: 0.994, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.12, black: -0.014, white: 0.994, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.13, black: -0.013, white: 0.994, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.060, -0.034, -0.026),
        mG: SIMD3(-0.026,  1.072, -0.046),
        mB: SIMD3(-0.024, -0.046,  1.070),
        shadowTint: SIMD3(-0.003, 0.002, 0.003),
        highlightTint: SIMD3(0.004, -0.002, 0.005),
        iie: 0.06,
        iieHue: [0.01, 0.00, 0.08, 0.04, 0.05, 0.03],
        acutance: (1.0, 0.06)
    )

    /// FUJICOLOR Superia 200.
    /// Superia 400 의 저감도판. C200 의 상위 호환.
    static let superia200 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.11, black: -0.014, white: 0.994, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.11, black: -0.014, white: 0.994, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.12, black: -0.013, white: 0.994, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.058, -0.032, -0.026),
        mG: SIMD3(-0.024,  1.072, -0.048),
        mB: SIMD3(-0.022, -0.046,  1.068),
        shadowTint: SIMD3(-0.003, 0.002, 0.003),
        highlightTint: SIMD3(0.005, -0.002, 0.005),
        iie: 0.06,
        iieHue: [0.01, 0.00, 0.09, 0.04, 0.05, 0.03],
        acutance: (1.0, 0.08)
    )

    /// FUJICOLOR Reala 100 (단종, 4번째 감광층).
    /// "가장 정확한 색 재현" 이라는 평판. 4번째 시안 감광층 덕분에 형광등 아래서도 중립.
    ///   - 톤: 낮은 대비.
    ///   - 매트릭스: 매우 중립(대각 ~1.005). Pro 400H 와 유사하지만 더 선명.
    static let reala100 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.07, black: -0.020, white: 0.994, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.07, black: -0.020, white: 0.994, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.07, black: -0.020, white: 0.994, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.008, -0.004, -0.004),
        mG: SIMD3(-0.003,  1.008, -0.005),
        mB: SIMD3(-0.003, -0.006,  1.009),
        shadowTint: .zero,
        highlightTint: SIMD3(-0.002, 0.001, 0.001),
        iie: 0.03,
        iieHue: [0.00, 0.00, 0.03, 0.03, 0.02, 0.00],
        acutance: (1.0, 0.10)
    )

    /// FUJICOLOR Industrial 100 (일본 내수 비즈니스용).
    /// Reala 계열의 보급형. 중립적이면서 약간 쿨한 Fuji 시그니처.
    static let industrial100 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.09, black: -0.012, white: 0.993, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.09, black: -0.012, white: 0.993, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.10, black: -0.011, white: 0.993, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.045, -0.026, -0.019),
        mG: SIMD3(-0.020,  1.050, -0.030),
        mB: SIMD3(-0.018, -0.032,  1.050),
        shadowTint: SIMD3(-0.003, 0.002, 0.003),
        highlightTint: SIMD3(0.003, -0.001, 0.003),
        iie: 0.04,
        iieHue: [0.00, 0.00, 0.05, 0.03, 0.04, 0.02],
        acutance: (1.0, 0.09)
    )

    /// Lomography Color Negative 800.
    /// 고감도, 강한 채도, 거친 그레인. 저조도/액션용.
    static let lomoCn800 = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.16, black: -0.006, white: 0.99, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.16, black: -0.006, white: 0.99, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.17, black: -0.005, white: 0.99, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.100, -0.060, -0.040),
        mG: SIMD3(-0.045,  1.090, -0.045),
        mB: SIMD3(-0.036, -0.060,  1.096),
        shadowTint: SIMD3(0.004, 0.001, 0.003),
        highlightTint: SIMD3(0.010, 0.005, -0.010),
        iie: 0.10,
        iieHue: [0.04, 0.06, 0.03, 0.00, 0.02, 0.02],
        acutance: (1.0, 0.03)
    )

    /// KODAK Vision3 500T (5219, ECN-2).
    /// 현행 영화용 컬러 네거티브의 표준. 텅스텐 밸런스, 넓은 관용도, DLT + Sub-Micron.
    ///   - 톤: 매우 낮은 대비(인화 전제 저감마 마스터), 넓은 관용도.
    ///   - 매트릭스: 중립 기반, 텅스텐 밸런스의 쿨 시그니처.
    ///   - 크로스오버: 암부 블루-시안.
    static let vision3_500T = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.04, black: -0.030, white: 0.99, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.04, black: -0.030, white: 0.99, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.05, black: -0.028, white: 0.99, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.015, -0.009, -0.006),
        mG: SIMD3(-0.007,  1.015, -0.008),
        mB: SIMD3(-0.005, -0.010,  1.015),
        shadowTint: SIMD3(-0.008, 0.000, 0.014),
        highlightTint: SIMD3(0.003, 0.001, -0.002),
        iie: 0.02,
        iieHue: [0.00, 0.00, 0.02, 0.02, 0.04, 0.00],
        acutance: (1.0, 0.04)
    )

    /// KODAK Vision3 250D (5207, ECN-2).
    /// 데이라이트 밸런스, VISION3 기술 적용. 500T 의 주간 촬영 대응판.
    static let vision3_250D = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.05, black: -0.028, white: 0.99, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.05, black: -0.028, white: 0.99, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.05, black: -0.026, white: 0.99, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.020, -0.012, -0.008),
        mG: SIMD3(-0.009,  1.018, -0.009),
        mB: SIMD3(-0.006, -0.012,  1.018),
        shadowTint: SIMD3(-0.004, 0.000, 0.008),
        highlightTint: SIMD3(0.005, 0.002, -0.003),
        iie: 0.03,
        iieHue: [0.00, 0.01, 0.03, 0.02, 0.03, 0.00],
        acutance: (1.0, 0.06)
    )

    /// KODAK Vision3 50D (5203, ECN-2).
    /// "world's finest grain film". 최저감도, 최고 해상도 영화용 필름.
    static let vision3_50D = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.06, black: -0.020, white: 0.99, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.06, black: -0.020, white: 0.99, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.07, black: -0.018, white: 0.99, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.025, -0.013, -0.012),
        mG: SIMD3(-0.010,  1.022, -0.012),
        mB: SIMD3(-0.008, -0.014,  1.022),
        shadowTint: SIMD3(-0.003, 0.000, 0.006),
        highlightTint: SIMD3(0.004, 0.001, -0.002),
        iie: 0.04,
        iieHue: [0.00, 0.01, 0.04, 0.03, 0.04, 0.00],
        acutance: (1.0, 0.12)
    )

    /// KODAK Vision3 200T (5213, ECN-2).
    /// "200 speed with 100 speed image structure". 200T지만 그레인은 100T급.
    static let vision3_200T = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0.05, black: -0.026, white: 0.99, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0.05, black: -0.026, white: 0.99, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0.06, black: -0.024, white: 0.99, lift: 0, pivot: 0.5),
        mR: SIMD3( 1.018, -0.010, -0.008),
        mG: SIMD3(-0.008,  1.018, -0.010),
        mB: SIMD3(-0.006, -0.012,  1.018),
        shadowTint: SIMD3(-0.006, 0.000, 0.010),
        highlightTint: SIMD3(0.003, 0.001, -0.002),
        iie: 0.03,
        iieHue: [0.00, 0.00, 0.02, 0.02, 0.03, 0.00],
        acutance: (1.0, 0.06)
    )

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
