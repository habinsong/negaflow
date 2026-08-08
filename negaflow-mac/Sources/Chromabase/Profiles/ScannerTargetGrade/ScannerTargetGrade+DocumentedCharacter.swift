import Foundation

extension ScannerTargetGrade {
    // MARK: 스캐너 절대 개성 (documented + measured device character)
    //
    // 실측 차분(scannerSignature)은 두 스캐너의 **절반 차이**만 남겨 공유 개성("스캐너다움")을
    // 상쇄한다 → NORITSU/FUJI 가 MAIN 과 median ΔE<1 로 구별되지 않았다. 이 단계는 각 스캐너의
    // **절대 개성**을 MAIN 위에 bounded 하게 얹어 시각적으로 구별되게 한다.
    //
    //  • FUJI SP-3000: **실측 캘리브레이션**. 같은 컬러 네거티브를 SP-3000(실기)과 OpticFilm+negaflow
    //    로 각각 스캔한 6쌍을 히스토그램 매칭(입력값 도메인 톤 전이) + Lab 중립축/대역 채도로 비교해
    //    공통 변환을 도출했다(6쌍 median/일관성, 특정 컷 아님). 결과: 미드 리프트 + 명부 숄더,
    //    하이라이트 채도↑, 섀도 약한 그린(MAIN 대비 덜 빨감), 스킨 미세 골든.
    //    실측엔 섀도 탈채도도 있었으나 섀도 탈색을 유발해 의도적으로 미적용(사용자 지시, 2026-07-20).
    //  • HS-1800 스타일: 설계 캐릭터(자체 정의, 2026-07-23 전면 재설계) — 공개 랩 문헌
    //    다수가 수렴하는 방향(저대비 + 섀도 개방 + 명부 보존, 중립 섀도 + 웜-피치 미드,
    //    핑크 스킨, 미드 중심 색 에너지 + 파스텔 명부)을 bounded 로 얹는다. 과거의
    //    쿨-뉴트럴 + 전역 뮤트 설계는 MAIN(플랫/뉴트럴 담당)과 정체성이 겹쳐 median ΔE 가
    //    지각 임계 아래였고, 사용자 지시로 폐기했다. 상세는 noritsuDocumentedProfile 주석 참조.
    //  • F135 스타일: 설계 캐릭터(자체 정의, 2026-07-23 신설) — 소비자 미니랩 인화 룩.
    //    인화 S 톤(깊은 블랙 + 미드 펀치 + 명부 리텐션), 웜-골드 미드, 레드/옐로 풍부,
    //    헬시 골든 스킨, 경쾌한 채도. 상세는 f135DocumentedProfile 주석 참조.
    //  • HR 스타일: 설계 캐릭터(자체 정의, 2026-07-23 신설) — 프로 랩 정밀 인화 룩.
    //    솔리드 블랙 + 양끝 리텐션 + 노출 규율 미드, 거의 중립 그레이, 리치 딥 블루,
    //    충실 스킨, 절제된 채도. 상세는 hr500DocumentedProfile 주석 참조.
    //
    // 필름 타입 전체 적용: 스캐너 색·대비 시그니처는 광원/센서/처리에서 오는 장치 속성이라 필름
    // 타입과 무관하게 같은 방향으로 나타난다. 포지티브(슬라이드)는 직접 디지털화라 개입이 작으므로
    // documentedPositiveScale 로 축소한다. 흑백은 색을 버리고 톤만 남긴다.
    // gamut/단조/결정성은 기존 cube(reciprocal+sharedRelativeGamutScale)와 boundedRelativeGrade 가 보장.

    /// 스킨 hue 앵커 중심(Lab, Caucasian 스킨 실측 ≈ 54~62°, 여기선 55° 채택).
    static let documentedSkinHueDegrees = 55.0
    /// 포지티브(슬라이드) 개입 축소 배율. 직접 디지털화(반전 해석 없음) + 이미 고대비/고채도인
    /// E-6 과보정 방지. 방향은 네거티브와 동일(장치 시그니처), 크기만 줄인다.
    static let documentedPositiveScale = 0.5

    struct DocumentedProfile {
        /// 톤 knot 입력 위치(감마 도메인). nil = designToneXs(percentile 앵커).
        var toneXs: [Double]?
        /// toneXs 위치에 더할 감마 도메인 톤 델타(±). 적용 효과 = tone − toneXs.
        var toneDelta: [Double]
        var neutralBins: [NeutralBin]           // 중립축 드리프트(Lab)
        var hueAnchors: [HueAnchor]             // 스킨 등 hue별 채도/회전
        var chromaBands: [ChromaBand]           // 대역 채도 배율
        /// 전역 개성 강도. FUJI(실측)·NORITSU(문서 유효값 직접 기술) 모두 1.0 —
        /// 포지티브 감쇠(documentedPositiveScale)에만 배율이 곱해진다.
        var strength: Double
    }

    static func documentedCharacter(
        target: DevelopTarget,
        filmType: FilmType,
        monochrome: Bool
    ) -> Signature? {
        guard let profile = documentedProfile(for: target) else { return nil }
        // 포지티브(슬라이드)는 같은 방향을 약하게, 네거티브는 온전히 적용한다.
        let positive = filmType == .colorPositive || filmType == .bwPositive
        let scale = profile.strength * (positive ? documentedPositiveScale : 1.0)
        let knots = profile.toneXs ?? designToneXs

        // 톤: knot 입력 위치에 델타를 더한다. preparedSignature 가 ±0.25 클램프 + 단조 강제.
        let tone = zip(knots, profile.toneDelta).map { x, delta in
            clamp(x + delta * scale, 0.002, 0.998)
        }

        // 흑백은 luma 붕괴라 색 성분 무의미 → 톤(대비)만 남긴다.
        guard !monochrome else {
            return Signature(toneXs: knots, tone: tone,
                             neutralBins: [], hueAnchors: [], chromaBands: [])
        }

        let neutralBins = profile.neutralBins.map {
            NeutralBin(luma: $0.luma,
                       a: clamp($0.a * scale, -4.0, 4.0),
                       b: clamp($0.b * scale, -4.0, 4.0))
        }
        let hueAnchors = profile.hueAnchors.map {
            HueAnchor(
                hueDegrees: $0.hueDegrees,
                // 배율은 log 도메인에서 scale 해야 역수 대칭(reciprocal)과 정합한다.
                chromaGain: clamp(pow($0.chromaGain, scale),
                                  hueChromaGainRange.lowerBound, hueChromaGainRange.upperBound),
                rotateDegrees: clamp($0.rotateDegrees * scale, -hueRotateLimit, hueRotateLimit)
            )
        }
        let chromaBands = profile.chromaBands.map {
            ChromaBand(luma: $0.luma,
                       gain: clamp(pow($0.gain, scale),
                                   chromaBandGainRange.lowerBound, chromaBandGainRange.upperBound))
        }
        return Signature(toneXs: knots, tone: tone,
                         neutralBins: neutralBins, hueAnchors: hueAnchors, chromaBands: chromaBands)
    }

    private static func documentedProfile(for target: DevelopTarget) -> DocumentedProfile? {
        switch target {
        case .sp3000: return fujiMeasuredProfile
        case .noritsu: return noritsuDocumentedProfile
        case .f135: return f135DocumentedProfile
        case .hr: return hr500DocumentedProfile
        case .main, .print, .rescue: return nil
        }
    }

    // MARK: FUJI SP-3000 — 실측 캘리브레이션(6쌍 SP-3000 vs negaflow MAIN 히스토그램 매칭)
    //
    // 톤: 입력값 도메인 히스토그램 매칭 커브(미드 리프트 + 명부 숄더). 커스텀 knot 위치 사용.
    // 중립: 섀도~미드 a*− (MAIN 대비 덜 빨감), 하이라이트 a*+ 미세. b* 는 6쌍에서 비일관 → 0.
    //   섀도 a*− 는 필름/현상 의존이 커 실측 median 을 0.7× 로 완화(과적합 방지).
    // 채도: 하이라이트 채도↑(bounded). 실측의 섀도 탈채도는 섀도 탈색 방지를 위해 미적용(gain 1.0 핀).
    // 스킨: 미세 골든(+회전).
    private static var fujiMeasuredProfile: DocumentedProfile {
        DocumentedProfile(
            toneXs: [0.08, 0.16, 0.28, 0.40, 0.52, 0.64, 0.76, 0.86, 0.94],
            // 실측 히스토그램 매칭 델타의 0.85× — 밝은 장면 명부 워시아웃(과다 리프트) 방지 마진.
            toneDelta: [0.020, 0.006, 0.014, 0.045, 0.094, 0.115, 0.112, 0.082, 0.015],
            neutralBins: [
                NeutralBin(luma: 0.13, a: -3.2, b: 0.0),
                NeutralBin(luma: 0.27, a: -3.2, b: 0.0),
                NeutralBin(luma: 0.41, a: -3.0, b: 0.0),
                NeutralBin(luma: 0.55, a: -1.5, b: 0.0),
                NeutralBin(luma: 0.69, a: 0.1, b: 0.0),
                NeutralBin(luma: 0.83, a: 1.4, b: 0.0),
            ],
            hueAnchors: fujiSkinAnchors,
            chromaBands: [
                ChromaBand(luma: 0.165, gain: 1.00),    // 섀도 채도 유지(실측 탈채도 미적용 — 탈색 금지)
                ChromaBand(luma: 0.495, gain: 1.25),    // 미드 채도↑
                ChromaBand(luma: 0.83, gain: 1.60),     // 하이라이트 채도↑(실측 ~2.5, cap 클램프)
            ],
            strength: 1.0
        )
    }

    // MARK: HS-1800 스타일 — 설계 캐릭터 직접 기술(2026-07-23 전면 재설계, 유효값 = strength 1.0)
    //
    // 이 타겟이 지향하는 톤/색 캐릭터(자체 설계 — 특정 제3자 문서/프로파일의 복제가 아니며,
    // 방향만 공개 랩 문헌 다수의 수렴 서술에서 가져와 크기는 합성 테스트로 bounded 보정):
    //  • 톤(존 분할) — ① 토우: 블랙포인트는 고정하되 빠르게 상승(젠틀 블랙, 순흑 endpoint
    //    계약 보존). ② 섀도: 개방 리프트 + 섀도 분리 소폭 증가(문헌의 "섀도 디테일" 방향).
    //    ③ 미드: 완만한 저대비(슬로프 ≈0.88~0.93), photometric mid 노출은 구 설계와 동일하게
    //    유지해 실기 상대 계약(SP 미드 > NOR 미드)을 보존. ④ 명부: 음수 숄더 = highlight
    //    retention. 합성 히스토그램상 "미드 집중 + 양끝 완만 롤오프 + 클리핑 최소" 형태.
    //  • 중립축 — 섀도는 모노크로매틱 중립(그림자가 색으로 흩어지지 않음), 미드는 웜-피치
    //    (b*+ 웜 우세 + a*+ 미세 마젠타), 명부로 갈수록 완만히 중립 복귀. 문헌 다수가 수렴하는
    //    "웜 렌더링, 마젠타-그린 축 중심" 방향이며, 과거의 쿨-뉴트럴(소수 서술)은 MAIN 과
    //    정체성이 겹쳐 폐기. warmGate 가 섀도의 웜 성분을 자동 0 화해 ①의 중립 섀도를 보강한다.
    //  • hue — 스킨은 핑크/피치 쪽 소폭 회전(FUJI 골든과 정반대 정체성), 그린은 옐로-그린
    //    쪽 소폭 회전(내추럴 폴리지 — 블루 쪽으로 미는 룩과 반대), 블루는 미세 소프트.
    //    나머지 hue 는 중립 앵커로 고정해 전역 회전을 막는다.
    //  • 채도 — 미드 중심 색 에너지(소폭↑) + 파스텔 명부(뮤트). FUJI(명부 1.60 블레이즈)와
    //    반대 정체성. 섀도 채도는 유지(탈색 금지 계약).
    //  • 톤 적용은 큐브가 L*(휘도) 도메인으로 수행해 색상/채도를 건드리지 않는다.
    //  • 로컬 대비·샤픈·그레인은 반경/강도 실측이 없어 여전히 미적용(provenance 계약,
    //    장치 샤픈 질감만 applyDocumentedTexture 가 별도 재현).
    // 실기 실측 쌍 확보 시 FUJI 처럼 측정 캘리브레이션으로 교체 예정.
    private static var noritsuDocumentedProfile: DocumentedProfile {
        DocumentedProfile(
            toneXs: nil,
            // percentile 앵커(designToneXs ≈ [0.10, 0.25, 0.35, 0.54, 0.74, 0.88, 0.96, 0.98, 1.00])
            // 기준 감마 도메인 델타.
            //  p1→p5 리프트 증가 = 섀도 분리↑(디테일), p5 정점 후 미드로 감쇠 = 개방 섀도.
            //  photometric mid(≈0.46) 델타 ≈ +0.033(+0.21 스탑) — SP 미드(+0.44 스탑)와의
            //  실측 계약(SP>NOR, 갭≥0.2)을 유지하는 상한. p75 부근 중립 교차, p90~p95
            //  −0.018 숄더 = retention, p99 −0.007 로 순백 endpoint 에 완만 복귀.
            toneDelta: [0.058, 0.070, 0.048, 0.022, 0.006, -0.008, -0.018, -0.018, -0.007],
            neutralBins: [
                // 섀도 중립(명시적 0 앵커 = 미드 웜의 하향 번짐 차단, warmGate 와 이중 방어).
                // 미드 웜-피치 무게중심(0.52) — a*+ 비중이 커 F135 의 골드(옐로 축)와
                // 직교하는 피치 축이다. 명부로 완만 감쇠(픽셀 taper 가 0.90 위를 0 으로).
                NeutralBin(luma: 0.16, a: 0.0, b: 0.0),
                NeutralBin(luma: 0.34, a: 1.6, b: 1.2),
                NeutralBin(luma: 0.52, a: 3.0, b: 2.0),
                NeutralBin(luma: 0.70, a: 2.4, b: 1.6),
                NeutralBin(luma: 0.86, a: 0.9, b: 0.7),
            ],
            hueAnchors: noritsuHueAnchors,
            chromaBands: [
                // 섀도 채도 유지(탈색 금지 계약), 미드부터 완만한 뮤트 → 파스텔 명부.
                // 문헌의 "softer/muted" 정체성 — F135 펀치(1.22/1.12)·FUJI 블레이즈(1.60)와
                // 정반대 축이라 세 타겟이 채도축에서 상쇄되지 않는다(2026-07-23 QA 증폭).
                ChromaBand(luma: 0.165, gain: 1.00),
                ChromaBand(luma: 0.495, gain: 0.98),
                ChromaBand(luma: 0.83, gain: 0.88),
            ],
            strength: 1.0
        )
    }

    /// HS 색상 앵커: 스킨(55°)은 핑크/피치 쪽(−회전), 그린(135°)은 옐로-그린 쪽(−회전,
    /// 내추럴 폴리지), 블루(265°)는 미세 소프트. 사이사이 중립 앵커가 전역 회전을 막는다
    /// (fujiSkinAnchors 와 같은 pin 패턴). 회전·게인 모두 bounded(±4° 미만, 0.96~1.05)로
    /// 스킨/하늘 왜곡 없이 방향만 싣는다.
    private static var noritsuHueAnchors: [HueAnchor] {
        [
            HueAnchor(hueDegrees: 20, chromaGain: 1.0, rotateDegrees: 0),
            HueAnchor(hueDegrees: documentedSkinHueDegrees, chromaGain: 1.03, rotateDegrees: -4.0),
            HueAnchor(hueDegrees: 95, chromaGain: 1.0, rotateDegrees: 0),
            HueAnchor(hueDegrees: 135, chromaGain: 1.05, rotateDegrees: -4.0),
            HueAnchor(hueDegrees: 200, chromaGain: 1.0, rotateDegrees: 0),
            HueAnchor(hueDegrees: 265, chromaGain: 0.94, rotateDegrees: 0),
            HueAnchor(hueDegrees: 330, chromaGain: 1.0, rotateDegrees: 0),
        ]
    }

    // MARK: F135 — 컴팩트 미니랩 스타일 설계 캐릭터(2026-07-23 신설, 유효값 = strength 1.0)
    //
    // 이 타겟이 지향하는 톤/색 캐릭터(자체 설계 — 특정 제3자 소프트웨어/프로파일의 복제가
    // 아니며, 방향만 공개 문헌의 수렴 서술에서 가져왔다). 문헌 방향: "박스에서 바로 인쇄
    // 가능한 색", 명부·암부 모두 디테일 풍부, 스킨 톤 최상급, 정확하되 즐거운(print-ready)
    // 발색, 강한 자동 노출/색 정규화 — 2000년대 소비자 미니랩 인화지 룩의 디지털 해석.
    //  • 톤(존 분할) — 인화 스타일 S: ① 토우 깊은 블랙(인화지 밀도감) 직후 빠른 섀도 분리
    //    (문헌 "shadows heavy with detail" — 크러시 아님), ② 하부-미드 펀치(슬로프 >1),
    //    ③ 밝고 경쾌한 상부 미드(인화 밝기), ④ 명부 숄더(문헌 "highlights heavy with
    //    detail" — 클리핑 지양). photometric mid ≈ +0.014(+0.09 스탑)로 노출은 온건.
    //  • 중립축 — 웜-골드 미드(옐로 우세 b*+, 미세 a*+ — HS 의 피치(63°)보다 옐로 쪽 무게),
    //    깊은 섀도와 종이 화이트는 클린 중립(인화지 베이스 화이트).
    //  • hue — 레드/옐로 풍부(소비자 인화의 원색 경쾌함), 스킨은 헬시 웜-골든(+회전 소폭
    //    + 채도 소폭 — 문헌 "스킨 톤 최상급"), 그린 미세 웜, 블루 온건.
    //  • 채도 — 전 대역 경쾌한 리치(미드 1.16/명부 1.12) — SP 명부 블레이즈(1.60)보다
    //    온건하고 HS 뮤트와 반대 방향.
    //  • 문헌의 결함 서술(레드 과다 장면의 시안 드리프트, 일부 프레임 플랫)은 결함이므로
    //    에뮬레이션하지 않는다.
    private static var f135DocumentedProfile: DocumentedProfile {
        DocumentedProfile(
            toneXs: nil,
            // percentile 앵커 기준 감마 도메인 델타. 토우 −0.022(깊은 블랙, 순흑 endpoint
            // 계약 보존) → 섀도 분리 슬로프 >1 → 하부-미드 펀치 → 상부-미드 +0.034(경쾌한
            // 인화 밝기) → 명부 숄더(−0.004/−0.002, retention).
            // p10 부터 양수 전환 = 미니랩 오토 덴시티의 "블랙 위는 밝게" — 어두운 장면에서도
            // 개성이 소멸하지 않는다(2026-07-23 lowkey 감사에서 medΔE 0.94 → 보강).
            toneDelta: [-0.030, -0.020, 0.006, 0.030, 0.042, 0.022, 0.002, -0.005, -0.002],
            neutralBins: [
                // 골드 축(b* 우세, a* 소량) — HS 피치(a* 비중 큼)와 직교. 웜이 명부까지
                // 확장(인화 글로우)되는 것도 미드 중심 HS 와의 차별점(2026-07-23 QA 증폭).
                NeutralBin(luma: 0.16, a: 0.0, b: 0.0),
                NeutralBin(luma: 0.36, a: 0.5, b: 1.8),
                NeutralBin(luma: 0.55, a: 0.8, b: 3.2),
                NeutralBin(luma: 0.72, a: 0.8, b: 3.0),
                NeutralBin(luma: 0.88, a: 0.5, b: 2.2),
            ],
            hueAnchors: f135HueAnchors,
            chromaBands: [
                ChromaBand(luma: 0.165, gain: 1.00),
                ChromaBand(luma: 0.495, gain: 1.22),
                ChromaBand(luma: 0.83, gain: 1.12),
            ],
            strength: 1.0
        )
    }

    /// F135 색상 앵커: 레드/옐로 풍부(원색 경쾌함), 스킨 헬시 웜-골든(SP 골든 +2.85°보다
    /// 온건한 회전 + 리치 채도 — "건강한 인화 스킨"), 그린 미세 웜, 블루 온건 리치.
    private static var f135HueAnchors: [HueAnchor] {
        [
            HueAnchor(hueDegrees: 20, chromaGain: 1.10, rotateDegrees: 0),
            HueAnchor(hueDegrees: documentedSkinHueDegrees, chromaGain: 1.06, rotateDegrees: 2.2),
            HueAnchor(hueDegrees: 95, chromaGain: 1.05, rotateDegrees: 0),
            HueAnchor(hueDegrees: 135, chromaGain: 1.0, rotateDegrees: -2.0),
            HueAnchor(hueDegrees: 200, chromaGain: 1.0, rotateDegrees: 0),
            HueAnchor(hueDegrees: 265, chromaGain: 1.04, rotateDegrees: 0),
            HueAnchor(hueDegrees: 330, chromaGain: 1.0, rotateDegrees: 0),
        ]
    }

    // MARK: HR — 프로 랩 스타일 설계 캐릭터(2026-07-23 신설, 유효값 = strength 1.0)
    //
    // 이 타겟이 지향하는 톤/색 캐릭터(자체 설계 — 특정 제3자 장비/프로파일의 복제가 아니며,
    // 방향만 공개 스펙/문헌 서술에서 가져왔다). 문헌 방향: 프로(웨딩/포트레이트) 랩 파이프라인,
    // 트라이리니어 센서의 "개선된 블루 응답", 16-bit 의 매끄러운 계조 전이, 높은 최대 농도
    // (깊고 깨끗한 블랙), 컬러 매니지먼트 통합 — 정밀·충실 지향의 프로 인화 렌더링.
    //  • 톤(존 분할) — ① 토우 깊은 솔리드 블랙(높은 Dmax — 에뮬레이션 중 가장 깊음)
    //    직후 빠른 섀도 분리(턱시도 디테일), ② 미드는 노출 규율(photometric mid ≈ +0.002,
    //    거의 중립 — 프로 랩의 노출 정확성), ③ 완만한 상부 감쇠 + 명부 보존 숄더(드레스
    //    화이트 디테일). 전체적으로 "양끝 리텐션 + 깊은 블랙"의 프로 인화 DR 형태.
    //  • 중립축 — 쿨-클린(b*− 절제 드리프트). 웜 계열(HS 피치/F135 골드)과 반대 축이라
    //    그레이 온도만으로 즉시 구분되며, "개선된 블루 응답 + 클린 프로 렌더링" 방향의
    //    자체 설계 해석이다. 스킨은 hue 앵커가 충실 쪽으로 되돌린다.
    //  • hue — 블루 리치·딥(+회전, "개선된 블루 응답" — 하늘/데님의 깊고 깨끗한 블루),
    //    스킨은 충실+미세 온기(회전 최소 — 스타일화 아님), 그린 내추럴.
    //  • 채도 — 절제된 리치(미드 1.10). 과장 없는 프로 발색.
    private static var hr500DocumentedProfile: DocumentedProfile {
        DocumentedProfile(
            toneXs: nil,
            // 토우 −0.034(솔리드 블랙) → p5~p10 섀도 분리(슬로프 ≈1.1) → 미드 규율(±0.01)
            // → 명부 숄더 −0.006/−0.012(화이트 디테일 보존) → p99 −0.004 완만 복귀.
            // 토우 −0.036: 이보다 깊으면(실측 −0.045) 정상 장면 0 끝 빈이 1% 계약을 깬다.
            toneDelta: [-0.036, -0.028, -0.008, -0.002, 0.024, 0.010, -0.004, -0.012, -0.005],
            neutralBins: [
                // 쿨-클린 축(b*−) — 웜 계열(HS 피치/F135 골드)과 정반대 방향이라 세 타겟이
                // 그레이 온도축에서 즉시 구분된다(2026-07-23 QA 증폭). warmGate 는 웜(+)만
                // 게이트하므로 쿨 드리프트는 섀도까지 유지된다(딥 클린 블랙과 한 몸).
                NeutralBin(luma: 0.16, a: 0.0, b: -1.0),
                NeutralBin(luma: 0.40, a: -0.3, b: -1.8),
                NeutralBin(luma: 0.62, a: -0.4, b: -1.8),
                NeutralBin(luma: 0.88, a: -0.2, b: -1.0),
            ],
            hueAnchors: hr500HueAnchors,
            chromaBands: [
                ChromaBand(luma: 0.165, gain: 1.00),
                ChromaBand(luma: 0.495, gain: 1.12),
                ChromaBand(luma: 0.83, gain: 1.05),
            ],
            strength: 1.0
        )
    }

    /// HR 색상 앵커: 블루 리치·딥(+3.0° 딥 블루 방향 + 게인 1.18 — 문헌 "개선된 블루 응답"),
    /// 레드/그린도 클린 리치(과장 없는 프로 발색), 스킨 충실(+1.0° — 쿨 드리프트의 스킨
    /// 크로스톡을 상쇄해 순 이동 최소).
    private static var hr500HueAnchors: [HueAnchor] {
        [
            HueAnchor(hueDegrees: 20, chromaGain: 1.05, rotateDegrees: 0),
            HueAnchor(hueDegrees: documentedSkinHueDegrees, chromaGain: 1.04, rotateDegrees: 1.0),
            HueAnchor(hueDegrees: 95, chromaGain: 1.0, rotateDegrees: 0),
            HueAnchor(hueDegrees: 135, chromaGain: 1.06, rotateDegrees: -1.0),
            HueAnchor(hueDegrees: 200, chromaGain: 1.0, rotateDegrees: 0),
            HueAnchor(hueDegrees: 265, chromaGain: 1.18, rotateDegrees: 3.0),
            HueAnchor(hueDegrees: 330, chromaGain: 1.0, rotateDegrees: 0),
        ]
    }

    /// 골든 스킨: 스킨 hue(55°)만 옐로 쪽(+회전)으로 국소 이동(실측 dHue≈+2.85°). 나머지 hue 는 중립
    /// 앵커로 고정해 전역 회전을 막는다. 채도는 실측 dChroma≈−1.4 → 미세 감소.
    private static var fujiSkinAnchors: [HueAnchor] {
        [
            HueAnchor(hueDegrees: 20, chromaGain: 1.0, rotateDegrees: 0),
            HueAnchor(hueDegrees: documentedSkinHueDegrees, chromaGain: 0.98, rotateDegrees: 2.85),
            HueAnchor(hueDegrees: 95, chromaGain: 1.0, rotateDegrees: 0),
            HueAnchor(hueDegrees: 200, chromaGain: 1.0, rotateDegrees: 0),
            HueAnchor(hueDegrees: 320, chromaGain: 1.0, rotateDegrees: 0),
        ]
    }
}
