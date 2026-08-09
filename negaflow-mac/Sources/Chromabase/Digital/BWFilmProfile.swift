import Foundation

// MARK: - BWFilmProfile (흑백 유제 파라미터 — 디지털 소스 전용)
//
// 컬러 필름과 축이 다르므로 자료형을 공유하지 않는다. 컬러에서 룩을 만드는 것들 — 층별 감도
// 오프셋, 층간 억제, 염료 매트릭스, 색 그레인 — 은 흑백 유제에 아예 존재하지 않는다.
// 대신 컬러에는 없는 축이 하나 생기고, 그것이 흑백 필름 룩의 8할이다: **분광 감도**.
//
// 같은 장면을 찍어도 유제가 어느 파장을 얼마나 받았는지에 따라 그레이 값이 갈린다. 오소는
// 붉은 것을 검게 떨구고, 확장 적감은 잎사귀를 하얗게 띄운다. 그래서 RGB→그레이 가중치는
// 필름마다 달라야 하며, Rec.709 휘도 하나로 고정하는 순간 모든 흑백 필름이 같아진다.
//
// **필름 스캔 경로는 이 파일을 쓰지 않는다.** 스캔본은 이미 그 유제를 통과했다.
//
// 근거 자료(제조사 데이터시트 우선):
//   • KODAK PROFESSIONAL TRI-X 400 (F-4017) — 표준 팬크로, 전통 큐빅 입자
//   • KODAK PROFESSIONAL T-MAX 100 / 400 / P3200 (F-4016 계열) — T-GRAIN.
//     Kodak 이 청색 감도를 낮췄다고 명시한다("blue sensitivity slightly less …
//     closer to that of the human eye"). 이 문장이 T-Max 가중치의 직접 근거다.
//   • ILFORD HP5 Plus / FP4 Plus / DELTA 100·400·3200 / ORTHO PLUS / SFX 200
//     — FP4 Plus 관용도 +6/−2 스톱, Delta 100 상반칙불궤 Ta=Tm^1.26, HP5 Plus Ta=Tm^1.31
//   • AGFA SCALA 200X — RMS 11, 해상력 120 lp/mm(1000:1) / 50 lp/mm(1.6:1),
//     "contrast matched to AGFACHROME RSX 100"(즉 컬러 슬라이드 대비)
//   • ROLLEI INFRARED 400 — RMS 11.0, 820 nm 까지 감도, 해상력 160 lp/mm
//   • ROLLEI SUPERPAN 200 — 확장 적감, 반전 현상 가능
//   • KENTMERE PAN 400 — Harman 보급 라인, 전통 큐빅
//
// 데이터시트가 숫자로 싣지 않는 값은 `provenance` 로 유추임을 드러낸다. 특히 분광 감도는
// 제조사가 wedge spectrogram(로그 감도 그림)으로만 공개하므로, 아래 가중치는 그 그림에서
// 읽은 **상대 관계**이지 실측 계수가 아니다.

public struct BWFilmProfile: Sendable {

    // MARK: 분광 감도 → RGB→그레이 가중치
    //
    /// 분광 감도에서 유도한 RGB→그레이 가중치. 합 = 1.
    ///
    /// 기준선은 Rec.709 휘도(0.2126 / 0.7152 / 0.0722)가 **아니다**. 사람 눈은 녹색에 크게
    /// 치우쳐 있지만 은염 유제는 그렇지 않다 — 브롬화은 자체가 청색 영역을 강하게 흡수하고,
    /// 색증감(sensitizing dye)은 그 위에 녹·적 감도를 얹는 방식이라 청색이 여전히 높다.
    /// 흑백 촬영에서 노란 필터(K2)가 사실상 표준 액세서리인 것이 이 청색 과감의 실물 증거다
    /// (필터로 눌러야 비로소 하늘이 사람 눈처럼 보인다).
    ///
    /// 그래서 표준 팬크로는 B 가중치가 Rec.709 의 다섯 배 가까이 잡히고, 오소는 x≈0,
    /// 확장 적감·적외는 x 가 가장 큰 항이 된다.
    public var spectralWeights: SIMD3<Double>

    // MARK: 특성곡선
    //
    /// 제조사 표준 현상에서의 콘트라스트 인덱스(평균 기울기).
    ///
    /// 일반 촬영용 흑백 네거티브는 표준 현상에서 대개 CI 0.55 부근에 맞춰져 있다 — 인화지
    /// grade 2 가 그 기울기를 정상으로 렌더하도록 설계되었기 때문이다. 따라서 이 값 자체보다
    /// **기준선에서 얼마나 벗어났는지**가 룩을 만든다.
    public var contrastIndex: Double

    /// 토우 부드러움(0 = 곧게 떨어짐, 1 = 매우 완만).
    ///
    /// 전통 큐빅 유제(Tri-X·HP5)의 긴 토우는 암부 계조를 서서히 살려 "필름 같은" 검정을
    /// 만들고, T-GRAIN·Core-Shell(T-Max·Delta)의 직선 토우는 암부를 곧게 떨궈 더 또렷하다.
    public var toeSoftness: Double

    /// 숄더 부드러움. 명부가 최대 밀도로 눕는 속도.
    public var shoulderSoftness: Double

    /// 노출 관용도(스톱). 곡선이 계조를 유지하는 폭.
    public var latitudeStops: Double

    /// 최대 밀도 배율(중간 회색 기준 상대). 반전은 인화지가 뒤를 받쳐 주지 않으므로 1 보다 크다.
    public var dmaxMultiplier: Double

    // MARK: 그레인 (은염 — chroma 성분이 없다)
    //
    /// 밀도 1.0 에서의 그레인 진폭. 데이터시트 RMS 를 렌더 진폭으로 옮긴 값.
    public var grainAmplitude: Double
    /// 입자 크기(픽셀 기준). 고감도일수록 크다.
    public var grainSize: Double
    public var grainProvenance: DigitalFilmDataProvenance

    // MARK: MTF acutance
    //
    /// 엣지 응답. T-GRAIN·Core-Shell 유제와 얇은 유제가 높다.
    public var acutance: (radius: Double, intensity: Double)

    // MARK: 산란 / 헐레이션
    //
    /// 유제 내부 산란 비율. 흑백은 층이 하나라 채널이 갈리지 않는다.
    public var scatterStrength: Double
    /// 베이스 반사 헐레이션 비율. 안티할레이션 백킹이 있는 유제는 작고, 투명 베이스 유제는 크다.
    public var halationStrength: Double
    /// 헐레이션 반경(이미지 짧은 변 대비 비율).
    public var halationRadiusRatio: Double

    // MARK: 반전 여부
    //
    /// 반전(흑백 슬라이드)이면 true. 필름 자체가 최종물이라 인화지가 뒤를 받치지 않는다 —
    /// Dmax 가 깊고 관용도가 좁으며 토우/숄더가 급하다.
    public var isReversal: Bool

    public init(
        spectralWeights: SIMD3<Double>,
        contrastIndex: Double,
        toeSoftness: Double,
        shoulderSoftness: Double,
        latitudeStops: Double,
        dmaxMultiplier: Double,
        grainAmplitude: Double,
        grainSize: Double,
        grainProvenance: DigitalFilmDataProvenance,
        acutance: (radius: Double, intensity: Double),
        scatterStrength: Double,
        halationStrength: Double,
        halationRadiusRatio: Double,
        isReversal: Bool
    ) {
        // 가중치는 합 1 로 정규화해 보관한다. 밝기 앵커가 유제마다 흔들리면 필름을 바꿀 때마다
        // 노출이 달라 보이고, 그것은 유제의 성격이 아니라 구현의 실수다.
        let sum = spectralWeights.x + spectralWeights.y + spectralWeights.z
        self.spectralWeights = sum > 1e-6 ? spectralWeights / sum : SIMD3(0.2126, 0.7152, 0.0722)
        self.contrastIndex = contrastIndex
        self.toeSoftness = toeSoftness
        self.shoulderSoftness = shoulderSoftness
        self.latitudeStops = latitudeStops
        self.dmaxMultiplier = dmaxMultiplier
        self.grainAmplitude = grainAmplitude
        self.grainSize = grainSize
        self.grainProvenance = grainProvenance
        self.acutance = acutance
        self.scatterStrength = scatterStrength
        self.halationStrength = halationStrength
        self.halationRadiusRatio = halationRadiusRatio
        self.isReversal = isReversal
    }

    // MARK: - Lookup

    /// 흑백 유제가 아닌 필름은 nil. 컬러 케이스가 흑백 테이블을 스치지 않게 하는 유일한 문이다.
    public static func of(_ emulation: FilmEmulation) -> BWFilmProfile? {
        switch emulation {
        case .triX400:        return triX400
        case .hp5Plus:        return hp5Plus
        case .fp4Plus:        return fp4Plus
        case .delta100:       return delta100
        case .delta400:       return delta400
        case .delta3200:      return delta3200
        case .tmax100:        return tmax100
        case .tmax400:        return tmax400
        case .tmaxP3200:      return tmaxP3200
        case .kentmere400:    return kentmere400
        case .orthoPlus:      return orthoPlus
        case .sfx200:         return sfx200
        case .rolleiIR:       return rolleiIR
        case .scala200X:      return scala200X
        case .rolleiSuperpan: return rolleiSuperpan
        default:              return nil
        }
    }
}
