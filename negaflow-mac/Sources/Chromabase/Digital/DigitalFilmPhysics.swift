import Foundation

// MARK: - DigitalFilmPhysics (디지털 소스 전용 필름 물리 파라미터)
//
// 디지털 사진에는 필름의 물성이 하나도 들어 있지 않다. 스캔본에는 이미 픽셀 안에 있는
// 것들 — 노출 관용도, 밀도 응답, 층간 억제, 산란/헐레이션, 그레인 — 을 디지털 경로에서는
// 전부 계산으로 만들어야 한다. 이 파일은 그 계산에 필요한 필름별 상수만 모은다.
//
// **필름 스캔 경로는 이 파일을 쓰지 않는다.** 스캔 결과에 이 값을 얹으면 이미 필름을 통과한
// 신호에 필름 응답을 두 번 먹이는 것이 된다.
//
// 근거 자료:
//   • FUJICHROME Velvia 50 [RVP50] Data Guide — diffuse RMS granularity 9
//     (48 µm 개구, Dmin+1.0 밀도에서 측정)
//   • FUJICHROME PROVIA 100F [RDP III] (AF3-036E) — RMS 8
//   • KODAK PROFESSIONAL EKTACHROME Film E100 (E-4000) — diffuse rms granularity 8
//     ("extremely fine", 48 µm 개구, gross diffuse visual density 1.0)
//   • FUJICOLOR PRO 400H (AF3-176E) — diffuse RMS granularity 4.
//     데이터시트가 "측정 조건이 달라 반전 필름과 비교 불가"라고 명시한다.
//   • KODAK PROFESSIONAL EKTAR 100 (E-4046) / PORTRA 160 (E-4051) / 400 (E-4050)
//     — Kodak 은 C-41 컬러 네거티브에 RMS 를 쓰지 않고 Print Grain Index(E-58)를 쓴다.
//       35mm 4×6 인화 기준 Ektar 100 < 25, Portra 160 = 28, Portra 400 = 37.
//       PGI 25 가 육안 식별 문턱이며 낮을수록 미세하다.
//   • 컬러 네거티브 카메라 필름 감마 ≈ 0.6, RA-4 인화지 감마 ≈ 1.6–1.8 (공개 문헌 다수)
//
// 척도가 셋(반전 RMS / 네거티브 RMS / PGI)이고 제조사가 상호 비교 불가를 명시하므로,
// 그룹 안에서만 데이터시트 순위를 쓰고 그룹 사이는 별도 앵커로 잇는다. 이 앵커는 측정값이
// 아니라 렌더링 결정이며, `GrainScale.provenance` 로 그 사실을 드러낸다.

/// 그레인 수치의 출처. 값을 실측처럼 보이게 하지 않기 위해 명시한다.
public enum DigitalFilmDataProvenance: String, Sendable {
    /// 제조사 데이터시트가 공개한 수치를 그대로 쓴다.
    case datasheet
    /// 데이터시트에 수치가 없어 같은 제조사·같은 세대·같은 감도대 제품에서 유추했다.
    case inferred
}

/// 필름 한 종의 물리 파라미터. 전부 디지털 소스 전용이다.
public struct DigitalFilmPhysics: Sendable {

    // MARK: 노출/밀도 응답

    /// 채널별 특성곡선 기울기(감마). 네거티브는 0.5~0.65, 반전은 1.5~2.2 대.
    public var gamma: SIMD3<Double>
    /// 노출 관용도(스톱). 곡선이 직선 구간을 유지하는 폭 — 넓을수록 명부가 늦게 눕는다.
    public var latitudeStops: Double
    /// 토우 부드러움(0 = 급격, 1 = 매우 완만). 네거티브의 긴 토우가 섀도우 관용도를 만든다.
    public var toeSoftness: Double
    /// 숄더 부드러움. 명부가 Dmax 로 눕는 속도.
    public var shoulderSoftness: Double

    // MARK: 감광층별 차이 (필름의 색이 밝기대별로 갈리는 진짜 출처)
    //
    // 컬러 필름은 R/G/B 세 채널이 아니라 청감(황색 형성)·녹감(마젠타 형성)·적감(시안 형성)
    // 세 감광층이 겹쳐진 구조다. 제조사는 층마다 감도를 일부러 어긋나게 설계하고(그래야 층
    // 사이 D-logE 곡선이 겹치지 않아 색 분리가 된다), 층이 도달하는 최대 밀도도 같지 않다 —
    // RA-4 인화지 실측에서 적감층이 나머지 둘보다 뚜렷하게 높은 Dmax 로 눕는다.
    //
    // 감마만 채널별로 다르게 두면 밝기대에 따라 색이 갈리는 폭이 좁다. 곡선을 노출 축에서
    // 어긋나게 두고 도달 밀도까지 달리해야 실제 필름에서 관측되는 크로스오버 — 그림자는
    // 서늘하고 명부는 따뜻해지는 그 갈림 — 이 나온다.
    //
    // 데이터시트는 이 값을 표로 싣지 않고 곡선으로만 보여주므로, 아래 값은 공개 곡선과 반복
    // 관측되는 크로스오버 서술에서 옮긴 방향이다. 절대값이 아니라 층 사이의 상대 관계다.

    /// 층별 감도 오프셋(스톱). 양수면 그 층이 더 빨리 밀도를 올린다.
    public var layerSpeed: SIMD3<Double>
    /// 층별 최대 밀도 배율. 적감(시안) 층이 가장 높다.
    public var layerDmax: SIMD3<Double>

    // MARK: 층간 억제(DIR 커플러 / inter-image effect)

    /// 층간 억제 행렬 강도. 한 층의 밀도가 이웃 층 현상을 억제하는 비율(R/G/B 순서로
    /// "이 층이 받는 억제"의 총량). 중립축은 보존되고 유채색만 분리되어 채도가 오른다.
    ///
    /// Agfa 특허(US 4,830,954)가 제시하는 목표치 — yellow ≥10%, magenta ≥25%, cyan ≥15% —
    /// 를 층 대응(yellow=B, magenta=G, cyan=R)으로 옮긴 크기 순서를 따른다.
    public var interImage: SIMD3<Double>

    // MARK: 산란/헐레이션

    /// 에멀전 내부 산란 비율(R/G/B). 작은 반경, 전 채널에 걸친다.
    public var scatterStrength: SIMD3<Double>
    /// 베이스 반사 헐레이션 비율(R/G/B). 붉은 층이 되돌아오는 빛을 먼저 받으므로 R ≫ G > B.
    public var halationStrength: SIMD3<Double>
    /// 헐레이션 1차 바운스 반경(필름 폭 대비 비율). 실제 크기는 이미지 크기에 비례시킨다.
    public var halationRadiusRatio: Double

    // MARK: 그레인

    public struct GrainScale: Sendable {
        /// 밀도 1.0 에서의 그레인 진폭(밀도 단위). 데이터시트 RMS/PGI 를 렌더 진폭으로 옮긴 값.
        public var amplitude: Double
        /// 색 그레인 비율. 컬러 필름은 층이 따로 뭉치므로 채널이 독립적으로 흔들린다.
        public var chromaRatio: Double
        /// 그레인 입자 크기(픽셀). 고감도일수록 크다.
        public var size: Double
        public var provenance: DigitalFilmDataProvenance

        public init(amplitude: Double, chromaRatio: Double, size: Double,
                    provenance: DigitalFilmDataProvenance) {
            self.amplitude = amplitude
            self.chromaRatio = chromaRatio
            self.size = size
            self.provenance = provenance
        }
    }

    public var grain: GrainScale

    /// 반전(E-6)이면 true — 필름 자체가 최종물이라 인화 단계를 거치지 않는다.
    public var isReversal: Bool

    public init(
        gamma: SIMD3<Double>,
        latitudeStops: Double,
        toeSoftness: Double,
        shoulderSoftness: Double,
        layerSpeed: SIMD3<Double>,
        layerDmax: SIMD3<Double>,
        interImage: SIMD3<Double>,
        scatterStrength: SIMD3<Double>,
        halationStrength: SIMD3<Double>,
        halationRadiusRatio: Double,
        grain: GrainScale,
        isReversal: Bool
    ) {
        self.gamma = gamma
        self.latitudeStops = latitudeStops
        self.toeSoftness = toeSoftness
        self.shoulderSoftness = shoulderSoftness
        self.layerSpeed = layerSpeed
        self.layerDmax = layerDmax
        self.interImage = interImage
        self.scatterStrength = scatterStrength
        self.halationStrength = halationStrength
        self.halationRadiusRatio = halationRadiusRatio
        self.grain = grain
        self.isReversal = isReversal
    }
}

// MARK: - 필름별 파라미터

public extension DigitalFilmPhysics {

    static func of(_ emulation: FilmEmulation) -> DigitalFilmPhysics? {
        switch emulation {
        case .none:           return nil
        case .ektachromeE100: return ektachromeE100
        case .provia100F:     return provia100F
        case .velvia50:       return velvia50
        case .velvia100:       return velvia100
        case .e100VS:          return e100VS
        case .astia100F:       return astia100F
        case .kodachrome64:    return kodachrome64
        case .portra160:      return portra160
        case .portra400:      return portra400
        case .portra800:      return portra800
        case .ektar100:       return ektar100
        case .ultramax400:    return ultramax400
        case .colorPlus200:   return colorPlus200
        case .fujicolorC200:  return fujicolorC200
        case .pro400H:        return pro400H
        case .gold200:         return gold200
        case .proImage100:     return proImage100
        case .superia400:      return superia400
        case .superiaPremium400: return superiaPremium400
        case .superia200:      return superia200
        case .reala100:        return reala100
        case .industrial100:   return industrial100
        case .lomoCn800:       return lomoCn800
        case .vision3_500T:    return vision3_500T
        case .vision3_250D:    return vision3_250D
        case .vision3_50D:     return vision3_50D
        case .vision3_200T:    return vision3_200T
        // 흑백 케이스: nil 반환
        case .triX400, .hp5Plus, .fp4Plus, .delta100, .delta400, .delta3200,
             .tmax100, .tmax400, .tmaxP3200, .kentmere400, .orthoPlus,
             .sfx200, .rolleiIR, .scala200X, .rolleiSuperpan:
            return nil
        }
    }

    // MARK: 반전(E-6)
    //
    // 반전 필름은 관용도가 좁고(Provia 100F 데이터시트 ±½ stop) 감마가 높다. 명부가 급격히
    // 눕고 암부는 깊게 떨어진다 — 슬라이드의 "딥 블랙 + 날아가는 하이라이트"가 여기서 나온다.
    // 산란/헐레이션은 네거티브보다 약하게 잡는다(반전 스톡은 일반적으로 헐레이션 억제가 강하다).

    /// E100 — 데이터시트가 "low-contrast tone scale", "neutral color balance",
    /// "moderately enhanced saturation", rms 8 로 서술하는 절제된 반전 필름.
    static let ektachromeE100 = DigitalFilmPhysics(
        gamma: SIMD3(1.552, 1.600, 1.668),
        latitudeStops: 5.2,
        toeSoftness: 0.34,
        shoulderSoftness: 0.30,
        layerSpeed: SIMD3(-0.030, 0.0, 0.042),
        layerDmax: SIMD3(1.06, 1.00, 0.95),
        interImage: SIMD3(0.055, 0.065, 0.045),
        scatterStrength: SIMD3(0.020, 0.014, 0.010),
        halationStrength: SIMD3(0.030, 0.011, 0.004),
        halationRadiusRatio: 0.0038,
        grain: GrainScale(amplitude: 0.026, chromaRatio: 0.34, size: 1.15,
                          provenance: .datasheet),          // rms 8 (E-4000)
        isReversal: true
    )

    /// Provia 100F — rms 8, 초고선예도. E100 보다 대비가 한 단계 높다.
    static let provia100F = DigitalFilmPhysics(
        gamma: SIMD3(1.668, 1.720, 1.792),
        latitudeStops: 4.8,
        toeSoftness: 0.30,
        shoulderSoftness: 0.26,
        layerSpeed: SIMD3(-0.028, 0.0, 0.038),
        layerDmax: SIMD3(1.05, 1.00, 0.96),
        interImage: SIMD3(0.070, 0.085, 0.060),
        scatterStrength: SIMD3(0.018, 0.012, 0.009),
        halationStrength: SIMD3(0.028, 0.010, 0.004),
        halationRadiusRatio: 0.0034,
        grain: GrainScale(amplitude: 0.026, chromaRatio: 0.32, size: 1.10,
                          provenance: .datasheet),          // RMS 8 (AF3-036E)
        isReversal: true
    )

    /// Velvia 50 — RMS 9 로 같은 감도대 반전 중 오히려 거칠고, 대비·채도는 가장 높다.
    static let velvia50 = DigitalFilmPhysics(
        gamma: SIMD3(2.008, 2.060, 2.132),
        latitudeStops: 4.0,
        toeSoftness: 0.24,
        shoulderSoftness: 0.20,
        layerSpeed: SIMD3(-0.022, 0.0, 0.030),
        layerDmax: SIMD3(1.04, 1.00, 0.97),
        interImage: SIMD3(0.085, 0.100, 0.070),
        scatterStrength: SIMD3(0.016, 0.011, 0.008),
        halationStrength: SIMD3(0.026, 0.009, 0.003),
        halationRadiusRatio: 0.0032,
        grain: GrainScale(amplitude: 0.029, chromaRatio: 0.30, size: 1.20,
                          provenance: .datasheet),          // RMS 9 (RVP50 Data Guide)
        isReversal: true
    )

    // MARK: 네거티브(C-41)
    //
    // 네거티브는 감마가 0.5~0.65 로 낮고 관용도가 넓다. 낮은 감마로 장면을 넓게 담고,
    // 인화지의 높은 감마(1.6~1.8)가 대비를 되살린다 — 이 2단 구조가 네거티브 특유의
    // "명부가 늦게 눕고 암부가 살아 있는" 응답을 만든다. 인화 단계는 DigitalPrintPaper 가 맡는다.

    /// Portra 160 — PGI 28(35mm 4×6). 인물용 연조·저채도.
    static let portra160 = DigitalFilmPhysics(
        gamma: SIMD3(0.526, 0.550, 0.584),
        latitudeStops: 9.0,
        toeSoftness: 0.62,
        shoulderSoftness: 0.66,
        layerSpeed: SIMD3(-0.045, 0.0, 0.060),
        layerDmax: SIMD3(1.09, 1.00, 0.93),
        interImage: SIMD3(0.080, 0.130, 0.055),
        scatterStrength: SIMD3(0.030, 0.021, 0.015),
        halationStrength: SIMD3(0.045, 0.017, 0.006),
        halationRadiusRatio: 0.0042,
        grain: GrainScale(amplitude: 0.020, chromaRatio: 0.42, size: 1.25,
                          provenance: .datasheet),          // PGI 28 (E-4051)
        isReversal: false
    )

    /// Portra 400 — PGI 37. 160 보다 굵고 관용도가 조금 더 넓다.
    static let portra400 = DigitalFilmPhysics(
        gamma: SIMD3(0.534, 0.560, 0.596),
        latitudeStops: 9.5,
        toeSoftness: 0.64,
        shoulderSoftness: 0.68,
        layerSpeed: SIMD3(-0.050, 0.0, 0.068),
        layerDmax: SIMD3(1.10, 1.00, 0.92),
        interImage: SIMD3(0.085, 0.135, 0.060),
        scatterStrength: SIMD3(0.033, 0.023, 0.016),
        halationStrength: SIMD3(0.050, 0.019, 0.007),
        halationRadiusRatio: 0.0046,
        grain: GrainScale(amplitude: 0.027, chromaRatio: 0.44, size: 1.40,
                          provenance: .datasheet),          // PGI 37 (E-4050)
        isReversal: false
    )

    /// Portra 800 — Kodak 이 PGI 를 공개하지 않는다. 같은 계열 400 위 감도로 유추.
    static let portra800 = DigitalFilmPhysics(
        gamma: SIMD3(0.552, 0.580, 0.622),
        latitudeStops: 9.0,
        toeSoftness: 0.60,
        shoulderSoftness: 0.66,
        layerSpeed: SIMD3(-0.055, 0.0, 0.075),
        layerDmax: SIMD3(1.11, 1.00, 0.91),
        interImage: SIMD3(0.090, 0.140, 0.065),
        scatterStrength: SIMD3(0.036, 0.025, 0.018),
        halationStrength: SIMD3(0.056, 0.021, 0.008),
        halationRadiusRatio: 0.0052,
        grain: GrainScale(amplitude: 0.034, chromaRatio: 0.46, size: 1.60,
                          provenance: .inferred),
        isReversal: false
    )

    /// Ektar 100 — PGI < 25(육안 문턱 아래). 네거티브 중 가장 미세하고 대비·채도가 높다.
    static let ektar100 = DigitalFilmPhysics(
        gamma: SIMD3(0.578, 0.610, 0.658),
        latitudeStops: 7.6,
        toeSoftness: 0.46,
        shoulderSoftness: 0.54,
        layerSpeed: SIMD3(-0.062, 0.0, 0.085),
        layerDmax: SIMD3(1.12, 1.00, 0.90),
        interImage: SIMD3(0.125, 0.175, 0.095),
        scatterStrength: SIMD3(0.026, 0.018, 0.013),
        halationStrength: SIMD3(0.040, 0.015, 0.005),
        halationRadiusRatio: 0.0038,
        grain: GrainScale(amplitude: 0.015, chromaRatio: 0.36, size: 1.10,
                          provenance: .datasheet),          // PGI < 25 (E-4046)
        isReversal: false
    )

    /// UltraMax 400 — 소비자용 T-GRAIN. 공개 그레인 수치가 없어 같은 감도 전문가용에서 유추한다.
    static let ultramax400 = DigitalFilmPhysics(
        gamma: SIMD3(0.564, 0.590, 0.630),
        latitudeStops: 8.6,
        toeSoftness: 0.58,
        shoulderSoftness: 0.62,
        layerSpeed: SIMD3(-0.052, 0.0, 0.070),
        layerDmax: SIMD3(1.10, 1.00, 0.92),
        interImage: SIMD3(0.100, 0.150, 0.070),
        scatterStrength: SIMD3(0.034, 0.024, 0.017),
        halationStrength: SIMD3(0.052, 0.020, 0.007),
        halationRadiusRatio: 0.0048,
        grain: GrainScale(amplitude: 0.032, chromaRatio: 0.48, size: 1.50,
                          provenance: .inferred),
        isReversal: false
    )

    /// ColorPlus 200 — 제조사 기술 데이터시트가 없다. 구세대 보급형 유제로 유추한다.
    static let colorPlus200 = DigitalFilmPhysics(
        gamma: SIMD3(0.552, 0.580, 0.622),
        latitudeStops: 8.0,
        toeSoftness: 0.56,
        shoulderSoftness: 0.60,
        layerSpeed: SIMD3(-0.048, 0.0, 0.064),
        layerDmax: SIMD3(1.11, 1.00, 0.92),
        interImage: SIMD3(0.095, 0.140, 0.065),
        scatterStrength: SIMD3(0.034, 0.024, 0.017),
        halationStrength: SIMD3(0.054, 0.021, 0.008),
        halationRadiusRatio: 0.0048,
        grain: GrainScale(amplitude: 0.030, chromaRatio: 0.50, size: 1.45,
                          provenance: .inferred),
        isReversal: false
    )

    /// Fujicolor C200 — Fuji 는 소비자용 유제의 RMS 를 싣지 않는다. 같은 세대 보급형에서 유추.
    static let fujicolorC200 = DigitalFilmPhysics(
        gamma: SIMD3(0.556, 0.580, 0.614),
        latitudeStops: 8.2,
        toeSoftness: 0.58,
        shoulderSoftness: 0.62,
        layerSpeed: SIMD3(-0.040, 0.0, 0.052),
        layerDmax: SIMD3(1.07, 1.00, 0.95),
        interImage: SIMD3(0.090, 0.135, 0.070),
        scatterStrength: SIMD3(0.032, 0.023, 0.017),
        halationStrength: SIMD3(0.048, 0.019, 0.007),
        halationRadiusRatio: 0.0046,
        grain: GrainScale(amplitude: 0.029, chromaRatio: 0.46, size: 1.42,
                          provenance: .inferred),
        isReversal: false
    )

    /// PRO 400H — RMS 4(네거티브 측정 조건). 4번째 감광층, 중립 그레이·연조.


    /// Velvia 100 — ISO 100, high saturation slide. RVP100 datasheet (AF3-131E).
    static let velvia100 = DigitalFilmPhysics(
        gamma: SIMD3(1.752, 1.820, 1.892),
        latitudeStops: 4.4,
        toeSoftness: 0.26,
        shoulderSoftness: 0.22,
        layerSpeed: SIMD3(-0.025, 0.0, 0.034),
        layerDmax: SIMD3(1.05, 1.00, 0.97),
        interImage: SIMD3(0.078, 0.095, 0.065),
        scatterStrength: SIMD3(0.017, 0.012, 0.009),
        halationStrength: SIMD3(0.027, 0.010, 0.004),
        halationRadiusRatio: 0.0033,
        grain: GrainScale(amplitude: 0.026, chromaRatio: 0.31, size: 1.15, provenance: .datasheet),
        isReversal: true
    )

    /// E100VS — ISO 100, most vivid slide. E-163 datasheet.
    static let e100VS = DigitalFilmPhysics(
        gamma: SIMD3(1.772, 1.830, 1.912),
        latitudeStops: 4.2,
        toeSoftness: 0.28,
        shoulderSoftness: 0.22,
        layerSpeed: SIMD3(-0.026, 0.0, 0.038),
        layerDmax: SIMD3(1.05, 1.00, 0.96),
        interImage: SIMD3(0.082, 0.098, 0.068),
        scatterStrength: SIMD3(0.017, 0.011, 0.009),
        halationStrength: SIMD3(0.029, 0.010, 0.004),
        halationRadiusRatio: 0.0035,
        grain: GrainScale(amplitude: 0.036, chromaRatio: 0.33, size: 1.18, provenance: .datasheet),
        isReversal: true
    )

    /// Astia 100F — ISO 100, soft skin tones, low contrast slide. AF3-129E.
    static let astia100F = DigitalFilmPhysics(
        gamma: SIMD3(1.504, 1.552, 1.616),
        latitudeStops: 5.8,
        toeSoftness: 0.38,
        shoulderSoftness: 0.34,
        layerSpeed: SIMD3(-0.032, 0.0, 0.040),
        layerDmax: SIMD3(1.04, 1.00, 0.96),
        interImage: SIMD3(0.045, 0.055, 0.038),
        scatterStrength: SIMD3(0.020, 0.014, 0.010),
        halationStrength: SIMD3(0.030, 0.011, 0.004),
        halationRadiusRatio: 0.0040,
        grain: GrainScale(amplitude: 0.023, chromaRatio: 0.33, size: 1.10, provenance: .datasheet),
        isReversal: true
    )

    /// Kodachrome 64 — ISO 64, K-14 비발색 유제. 잔류 색 마스크가 없어 깊은 그림자는 중립이다.
    static let kodachrome64 = DigitalFilmPhysics(
        gamma: SIMD3(1.682, 1.740, 1.812),
        latitudeStops: 5.0,
        toeSoftness: 0.30,
        shoulderSoftness: 0.26,
        layerSpeed: SIMD3(-0.028, 0.0, 0.036),
        layerDmax: SIMD3(1.06, 1.00, 0.94),
        interImage: SIMD3(0.062, 0.072, 0.050),
        scatterStrength: SIMD3(0.019, 0.013, 0.010),
        halationStrength: SIMD3(0.028, 0.010, 0.004),
        halationRadiusRatio: 0.0042,
        grain: GrainScale(amplitude: 0.033, chromaRatio: 0.30, size: 1.08, provenance: .datasheet),
        isReversal: true
    )

    /// Gold 200 — ISO 200, consumer negative. E-7022 (2016).
    static let gold200 = DigitalFilmPhysics(
        gamma: SIMD3(0.558, 0.586, 0.624),
        latitudeStops: 8.4,
        toeSoftness: 0.56,
        shoulderSoftness: 0.60,
        layerSpeed: SIMD3(-0.050, 0.0, 0.068),
        layerDmax: SIMD3(1.10, 1.00, 0.92),
        interImage: SIMD3(0.095, 0.140, 0.065),
        scatterStrength: SIMD3(0.034, 0.024, 0.017),
        halationStrength: SIMD3(0.053, 0.020, 0.007),
        halationRadiusRatio: 0.0048,
        grain: GrainScale(amplitude: 0.030, chromaRatio: 0.48, size: 1.45, provenance: .inferred),
        isReversal: false
    )

    /// Pro Image 100 — ISO 100, warm professional negative. E4006.
    static let proImage100 = DigitalFilmPhysics(
        gamma: SIMD3(0.538, 0.562, 0.596),
        latitudeStops: 8.8,
        toeSoftness: 0.60,
        shoulderSoftness: 0.64,
        layerSpeed: SIMD3(-0.046, 0.0, 0.062),
        layerDmax: SIMD3(1.09, 1.00, 0.93),
        interImage: SIMD3(0.085, 0.130, 0.058),
        scatterStrength: SIMD3(0.031, 0.022, 0.016),
        halationStrength: SIMD3(0.047, 0.018, 0.006),
        halationRadiusRatio: 0.0044,
        grain: GrainScale(amplitude: 0.017, chromaRatio: 0.40, size: 1.20, provenance: .inferred),
        isReversal: false
    )

    /// Superia 400 — ISO 400, Fuji 4th color layer. AF3-176E.
    static let superia400 = DigitalFilmPhysics(
        gamma: SIMD3(0.560, 0.582, 0.618),
        latitudeStops: 8.4,
        toeSoftness: 0.58,
        shoulderSoftness: 0.62,
        layerSpeed: SIMD3(-0.044, 0.0, 0.058),
        layerDmax: SIMD3(1.08, 1.00, 0.94),
        interImage: SIMD3(0.092, 0.138, 0.068),
        scatterStrength: SIMD3(0.032, 0.023, 0.016),
        halationStrength: SIMD3(0.050, 0.019, 0.007),
        halationRadiusRatio: 0.0046,
        grain: GrainScale(amplitude: 0.028, chromaRatio: 0.44, size: 1.40, provenance: .inferred),
        isReversal: false
    )

    /// Superia Premium 400 — 일본 시장 피부색과 넓은 노출 관용도를 겨냥한 3감광층 유제.
    static let superiaPremium400 = DigitalFilmPhysics(
        gamma: SIMD3(0.548, 0.570, 0.602),
        latitudeStops: 8.8,
        toeSoftness: 0.62,
        shoulderSoftness: 0.66,
        layerSpeed: SIMD3(-0.042, 0.0, 0.054),
        layerDmax: SIMD3(1.07, 1.00, 0.95),
        interImage: SIMD3(0.088, 0.132, 0.064),
        scatterStrength: SIMD3(0.031, 0.022, 0.016),
        halationStrength: SIMD3(0.048, 0.018, 0.007),
        halationRadiusRatio: 0.0044,
        grain: GrainScale(amplitude: 0.025, chromaRatio: 0.42, size: 1.35, provenance: .inferred),
        isReversal: false
    )

    /// Superia 200 — ISO 200.
    static let superia200 = DigitalFilmPhysics(
        gamma: SIMD3(0.546, 0.570, 0.606),
        latitudeStops: 8.6,
        toeSoftness: 0.60,
        shoulderSoftness: 0.64,
        layerSpeed: SIMD3(-0.044, 0.0, 0.056),
        layerDmax: SIMD3(1.08, 1.00, 0.94),
        interImage: SIMD3(0.090, 0.135, 0.066),
        scatterStrength: SIMD3(0.030, 0.022, 0.015),
        halationStrength: SIMD3(0.049, 0.018, 0.007),
        halationRadiusRatio: 0.0044,
        grain: GrainScale(amplitude: 0.020, chromaRatio: 0.40, size: 1.25, provenance: .inferred),
        isReversal: false
    )

    /// Reala 100 — ISO 100, 4번째 시안 감광층으로 혼합광의 녹색 캐스트를 보정한다.
    static let reala100 = DigitalFilmPhysics(
        gamma: SIMD3(0.504, 0.522, 0.548),
        latitudeStops: 9.4,
        toeSoftness: 0.66,
        shoulderSoftness: 0.70,
        layerSpeed: SIMD3(-0.038, 0.0, 0.050),
        layerDmax: SIMD3(1.07, 1.00, 0.95),
        interImage: SIMD3(0.075, 0.115, 0.058),
        scatterStrength: SIMD3(0.030, 0.021, 0.015),
        halationStrength: SIMD3(0.045, 0.017, 0.006),
        halationRadiusRatio: 0.0043,
        grain: GrainScale(amplitude: 0.015, chromaRatio: 0.38, size: 1.15, provenance: .inferred),
        isReversal: false
    )

    /// Industrial 100 — ISO 100, Japan business film.
    static let industrial100 = DigitalFilmPhysics(
        gamma: SIMD3(0.536, 0.558, 0.592),
        latitudeStops: 8.6,
        toeSoftness: 0.58,
        shoulderSoftness: 0.62,
        layerSpeed: SIMD3(-0.044, 0.0, 0.056),
        layerDmax: SIMD3(1.08, 1.00, 0.94),
        interImage: SIMD3(0.085, 0.130, 0.060),
        scatterStrength: SIMD3(0.030, 0.021, 0.015),
        halationStrength: SIMD3(0.046, 0.018, 0.006),
        halationRadiusRatio: 0.0043,
        grain: GrainScale(amplitude: 0.018, chromaRatio: 0.40, size: 1.20, provenance: .inferred),
        isReversal: false
    )

    /// Lomo CN 800 — 제조사 데이터시트가 없어 공개 설명과 비교 촬영에서 유추한 ISO 800 유제.
    static let lomoCn800 = DigitalFilmPhysics(
        gamma: SIMD3(0.576, 0.604, 0.646),
        latitudeStops: 7.8,
        toeSoftness: 0.52,
        shoulderSoftness: 0.56,
        layerSpeed: SIMD3(-0.056, 0.0, 0.078),
        layerDmax: SIMD3(1.11, 1.00, 0.91),
        interImage: SIMD3(0.105, 0.155, 0.075),
        scatterStrength: SIMD3(0.036, 0.025, 0.018),
        halationStrength: SIMD3(0.055, 0.021, 0.008),
        halationRadiusRatio: 0.0050,
        grain: GrainScale(amplitude: 0.036, chromaRatio: 0.52, size: 1.55, provenance: .inferred),
        isReversal: false
    )

    /// Vision3 500T — ECN-2, H-1-5219. remjet/AHU 안티할레이션으로 붉은 글로우가 억제된다.
    static let vision3_500T = DigitalFilmPhysics(
        gamma: SIMD3(0.482, 0.504, 0.534),
        latitudeStops: 10.5,
        toeSoftness: 0.72,
        shoulderSoftness: 0.76,
        layerSpeed: SIMD3(-0.040, 0.0, 0.052),
        layerDmax: SIMD3(1.05, 1.00, 0.96),
        interImage: SIMD3(0.065, 0.105, 0.050),
        scatterStrength: SIMD3(0.032, 0.023, 0.016),
        halationStrength: SIMD3(0.034, 0.013, 0.005),
        halationRadiusRatio: 0.0050,
        grain: GrainScale(amplitude: 0.022, chromaRatio: 0.36, size: 1.30, provenance: .inferred),
        isReversal: false
    )

    /// Vision3 250D — ECN-2, H-1-5207. 계열 중 대비가 가장 높다.
    static let vision3_250D = DigitalFilmPhysics(
        gamma: SIMD3(0.516, 0.538, 0.566),
        latitudeStops: 10.0,
        toeSoftness: 0.70,
        shoulderSoftness: 0.74,
        layerSpeed: SIMD3(-0.038, 0.0, 0.048),
        layerDmax: SIMD3(1.06, 1.00, 0.96),
        interImage: SIMD3(0.070, 0.110, 0.055),
        scatterStrength: SIMD3(0.030, 0.021, 0.015),
        halationStrength: SIMD3(0.031, 0.012, 0.004),
        halationRadiusRatio: 0.0046,
        grain: GrainScale(amplitude: 0.018, chromaRatio: 0.34, size: 1.20, provenance: .inferred),
        isReversal: false
    )

    /// Vision3 50D — ECN-2, H-1-5203. 계열 최미립·최고 채도이며 대비가 아니라 색이 서명이다.
    static let vision3_50D = DigitalFilmPhysics(
        gamma: SIMD3(0.494, 0.516, 0.544),
        latitudeStops: 9.6,
        toeSoftness: 0.66,
        shoulderSoftness: 0.70,
        layerSpeed: SIMD3(-0.036, 0.0, 0.046),
        layerDmax: SIMD3(1.06, 1.00, 0.97),
        interImage: SIMD3(0.075, 0.115, 0.060),
        scatterStrength: SIMD3(0.028, 0.020, 0.014),
        halationStrength: SIMD3(0.030, 0.011, 0.004),
        halationRadiusRatio: 0.0042,
        grain: GrainScale(amplitude: 0.013, chromaRatio: 0.32, size: 1.10, provenance: .inferred),
        isReversal: false
    )

    /// Vision3 200T — ECN-2, H-1-5213. 50D와 비슷한 대비의 100-speed급 이미지 구조.
    static let vision3_200T = DigitalFilmPhysics(
        gamma: SIMD3(0.495, 0.517, 0.545),
        latitudeStops: 10.2,
        toeSoftness: 0.70,
        shoulderSoftness: 0.74,
        layerSpeed: SIMD3(-0.038, 0.0, 0.050),
        layerDmax: SIMD3(1.05, 1.00, 0.96),
        interImage: SIMD3(0.068, 0.108, 0.052),
        scatterStrength: SIMD3(0.030, 0.022, 0.015),
        halationStrength: SIMD3(0.032, 0.012, 0.004),
        halationRadiusRatio: 0.0048,
        grain: GrainScale(amplitude: 0.016, chromaRatio: 0.33, size: 1.15, provenance: .inferred),
        isReversal: false
    )

    static let pro400H = DigitalFilmPhysics(
        gamma: SIMD3(0.494, 0.510, 0.534),
        latitudeStops: 10.0,
        toeSoftness: 0.68,
        shoulderSoftness: 0.72,
        layerSpeed: SIMD3(-0.035, 0.0, 0.046),
        layerDmax: SIMD3(1.06, 1.00, 0.96),
        interImage: SIMD3(0.070, 0.110, 0.055),
        scatterStrength: SIMD3(0.031, 0.022, 0.016),
        halationStrength: SIMD3(0.046, 0.018, 0.006),
        halationRadiusRatio: 0.0044,
        grain: GrainScale(amplitude: 0.024, chromaRatio: 0.40, size: 1.35,
                          provenance: .datasheet),          // RMS 4 (AF3-176E)
        isReversal: false
    )
}
