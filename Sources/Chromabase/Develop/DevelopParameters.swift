import Foundation

/// 사용자가 조절하는 현상 파라미터. plan §8.7/§8.8.
public enum DevelopTarget: String, Codable, Sendable, CaseIterable {
    case main
    case print
    case noritsu
    case sp3000 = "sp-3000"
    case f135
    case hr
    case rescue

    public var displayName: String {
        switch self {
        case .main: return "MAIN"
        case .print: return "PRINT"
        case .noritsu: return "HS"
        case .sp3000: return "SP"
        case .f135: return "F135"
        case .hr: return "HR"
        case .rescue: return "EXPIRED"
        }
    }

    /// 실기 미니랩 스캐너 재현 타겟인지. true 면 네거티브 파이프라인이 main 그레이드 대신
    /// ScannerTargetGrade(실측 프로파일 기반 독자 베이스)를 쓴다.
    public var isScannerEmulation: Bool {
        switch self {
        case .noritsu, .sp3000, .f135, .hr: return true
        case .main, .print, .rescue: return false
        }
    }
}

public struct DevelopParameters: Codable, Sendable, Equatable {
    // Base
    public var filmType: FilmType = .colorNegative
    public var developTarget: DevelopTarget = .main
    public var scannerProfileID: String?
    public var baseEstimationMode: BaseMode = .auto
    public var manualBaseRGB: SIMD3<Double>? = nil   // 수동 base picker 결과
    public var filmStockDminID: String? = nil   // 필름 Dmin/Dmax 프리셋(제조사 데이터시트). preset 모드에서 사용.
    /// 스캔 광원 프로파일(LightSourceProfileRegistry id). 실측 base가 없을 때 필름 프리셋 Dmin에
    /// 채널별 트림을 적용한다. nil = 중립(보정 없음).
    public var lightSourceProfileID: String? = nil

    // 장면 적응(자동) 보정 — 명시적으로 켰을 때만 동작한다(opt-in).
    // 반전 자체(Dmin/dmaxNorm 밀도 정규화)는 결정적이며 여기 포함되지 않는다.
    /// 반전 후 채널별 black/white 히스토그램 스트레치(AutoLevels). 장면 의존적 자동 레벨.
    public var autoLevels: Bool = false
    /// 반전 후 gray-world 미드톤 중립화(NeutralBalance). 장면 의존적 자동 컬러 밸런스.
    public var autoNeutralBalance: Bool = false

    // Tone (plan §8.7) — 기본 UI
    public var exposure: Double = 0.0        // stops
    public var contrast: Double = 0.0
    public var density: Double = 0.0         // -1...1
    public var highlight: Double = 0.0       // -1...1 (roll-off)
    public var shadow: Double = 0.0          // -1...1 (black softness)
    public var whites: Double = 0.0
    public var blacks: Double = 0.0
    public var curveHighlights: Double = 0.0
    public var curveLights: Double = 0.0
    public var curveDarks: Double = 0.0
    public var curveShadows: Double = 0.0

    // Color (plan §8.8) — 기본 UI
    public var warmth: Double = 0.0          // -1...1
    public var tint: Double = 0.0            // -1...1
    public var colorDepth: Double = 0.0      // -1...1 (saturation)
    public var vibrance: Double = 0.0
    public var saturation: Double = 0.0
    public var redPrimary: Double = 0.0
    public var greenPrimary: Double = 0.0
    public var bluePrimary: Double = 0.0

    // 고급 색/톤 — 기능별 서브구조체
    public var pointCurves = PointCurves()       // 포인트 톤 커브 DR/R/G/B
    public var colorMixer = ColorMixer()         // HSL 8색
    public var colorGrading = ColorGrading()     // 색보정 3영역 휠
    public var calibration = CalibrationAdjust() // Calibration primary Hue/Sat
    public var bwToning = BWToning()

    // 슬라이드 필름 특성 룩(좌측 Film 탭). 현상 원본(플랫) 위에 데이터시트 유도 룩을 얹는 특수 기능.
    public var filmEmulation: FilmEmulation = .none
    public var filmEmulationIntensity: Double = 1.0   // 0...1

    // Texture
    public var grain: Double = 0.0           // 0...1
    public var sharpness: Double = 0.0       // 0...1
    public var halation: Double = 0.0        // 0...1
    public var clarity: Double = 0.0
    public var vignette: Double = 0.0
    public var imageTransform: ImageTransform = .identity

    // 소프트웨어 결함 제거 (먼지/스크래치 제거). IR 없이 RGB-only로 동작.
    public var defectRemoval: Double = 0.0   // 0...1 (0 = off, strength)

    // 사용자 노이즈 제거. 0 = off. 토글로 켜면 기본 강도 적용.
    // multi-scale shrinkage(FilmScanDenoise) — 필름 타입별 luma/chroma 노이즈만 수축,
    // base band(평균 색·채도)는 불변이라 탈색/뭉갬 없음.
    public var noiseReduction: Double = 0.0  // 0...1 (0 = off, strength)

    // NR 축 분리(일반적 휘도/색/디테일 축 관례) — noiseReduction(마스터 강도)에 대한
    // 축별 밸런스. 0.5 = 기준(기존 단일 슬라이더와 동일 출력), 0 = 해당 축 끔, 1 = 2배.
    public var noiseReductionLuma: Double = 0.5      // 휘도 노이즈 축
    public var noiseReductionChroma: Double = 0.5    // 색 노이즈 축
    public var noiseReductionDarkTone: Double = 0.5  // 암부(dark-tone) 노이즈 축
    public var noiseReductionDetail: Double = 0.5    // 디테일 보존 축(높을수록 구조 보호↑)
    // grain 보호 축 — 필름 grain(미드톤의 무채색 미세 질감)을 노이즈로 취급하지 않고 남긴다.
    // 0 = 보호 없음(기존과 동일), 1 = 미드톤 grain 최대 보존. chroma 노이즈 제거는 유지된다.
    public var noiseReductionGrainProtect: Double = 0.0

    public var localDodgeBurn: [LocalDodgeBurnAdjustment] = []

    public enum BaseMode: String, Codable, Sendable { case auto, manual, preset }

    public init() {}

    enum CodingKeys: String, CodingKey {
        case filmType, developTarget, scannerProfileID, baseEstimationMode, manualBaseRGB, filmStockDminID
        case lightSourceProfileID, autoLevels, autoNeutralBalance
        case exposure, contrast, density, highlight, shadow, whites, blacks
        case curveHighlights, curveLights, curveDarks, curveShadows
        case warmth, tint, colorDepth, vibrance, saturation
        case redPrimary, greenPrimary, bluePrimary
        case pointCurves, colorMixer, colorGrading, calibration, bwToning
        case filmEmulation, filmEmulationIntensity
        case grain, sharpness, halation, clarity, vignette, imageTransform
        case defectRemoval
        case noiseReduction
        case noiseReductionLuma, noiseReductionChroma, noiseReductionDarkTone
        case noiseReductionDetail, noiseReductionGrainProtect
        case localDodgeBurn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filmType = try c.decodeIfPresent(FilmType.self, forKey: .filmType) ?? .colorNegative
        developTarget = try c.decodeIfPresent(DevelopTarget.self, forKey: .developTarget) ?? .main
        scannerProfileID = try c.decodeIfPresent(String.self, forKey: .scannerProfileID)
        baseEstimationMode = try c.decodeIfPresent(BaseMode.self, forKey: .baseEstimationMode) ?? .auto
        manualBaseRGB = try c.decodeIfPresent(SIMD3<Double>.self, forKey: .manualBaseRGB)
        filmStockDminID = try c.decodeIfPresent(String.self, forKey: .filmStockDminID)
        lightSourceProfileID = try c.decodeIfPresent(String.self, forKey: .lightSourceProfileID)
        autoLevels = try c.decodeIfPresent(Bool.self, forKey: .autoLevels) ?? false
        autoNeutralBalance = try c.decodeIfPresent(Bool.self, forKey: .autoNeutralBalance) ?? false
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        density = try c.decodeIfPresent(Double.self, forKey: .density) ?? 0
        highlight = try c.decodeIfPresent(Double.self, forKey: .highlight) ?? 0
        shadow = try c.decodeIfPresent(Double.self, forKey: .shadow) ?? 0
        whites = try c.decodeIfPresent(Double.self, forKey: .whites) ?? 0
        blacks = try c.decodeIfPresent(Double.self, forKey: .blacks) ?? 0
        curveHighlights = try c.decodeIfPresent(Double.self, forKey: .curveHighlights) ?? 0
        curveLights = try c.decodeIfPresent(Double.self, forKey: .curveLights) ?? 0
        curveDarks = try c.decodeIfPresent(Double.self, forKey: .curveDarks) ?? 0
        curveShadows = try c.decodeIfPresent(Double.self, forKey: .curveShadows) ?? 0
        warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        colorDepth = try c.decodeIfPresent(Double.self, forKey: .colorDepth) ?? 0
        vibrance = try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        redPrimary = try c.decodeIfPresent(Double.self, forKey: .redPrimary) ?? 0
        greenPrimary = try c.decodeIfPresent(Double.self, forKey: .greenPrimary) ?? 0
        bluePrimary = try c.decodeIfPresent(Double.self, forKey: .bluePrimary) ?? 0
        pointCurves = try c.decodeIfPresent(PointCurves.self, forKey: .pointCurves) ?? PointCurves()
        colorMixer = try c.decodeIfPresent(ColorMixer.self, forKey: .colorMixer) ?? ColorMixer()
        colorGrading = try c.decodeIfPresent(ColorGrading.self, forKey: .colorGrading) ?? ColorGrading()
        calibration = try c.decodeIfPresent(CalibrationAdjust.self, forKey: .calibration) ?? CalibrationAdjust()
        bwToning = try c.decodeIfPresent(BWToning.self, forKey: .bwToning) ?? BWToning()
        filmEmulation = try c.decodeIfPresent(FilmEmulation.self, forKey: .filmEmulation) ?? .none
        filmEmulationIntensity = try c.decodeIfPresent(Double.self, forKey: .filmEmulationIntensity) ?? 1.0
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        halation = try c.decodeIfPresent(Double.self, forKey: .halation) ?? 0
        clarity = try c.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        vignette = try c.decodeIfPresent(Double.self, forKey: .vignette) ?? 0
        imageTransform = try c.decodeIfPresent(ImageTransform.self, forKey: .imageTransform) ?? .identity
        defectRemoval = try c.decodeIfPresent(Double.self, forKey: .defectRemoval) ?? 0
        noiseReduction = try c.decodeIfPresent(Double.self, forKey: .noiseReduction) ?? 0
        noiseReductionLuma = try c.decodeIfPresent(Double.self, forKey: .noiseReductionLuma) ?? 0.5
        noiseReductionChroma = try c.decodeIfPresent(Double.self, forKey: .noiseReductionChroma) ?? 0.5
        noiseReductionDarkTone = try c.decodeIfPresent(Double.self, forKey: .noiseReductionDarkTone) ?? 0.5
        noiseReductionDetail = try c.decodeIfPresent(Double.self, forKey: .noiseReductionDetail) ?? 0.5
        noiseReductionGrainProtect = try c.decodeIfPresent(Double.self, forKey: .noiseReductionGrainProtect) ?? 0
        localDodgeBurn = try c.decodeIfPresent([LocalDodgeBurnAdjustment].self, forKey: .localDodgeBurn) ?? []
    }

    /// LookPreset의 값을 얹은 뒤 사용자 조절을 적용한다.
    public init(preset: LookPreset, overrides: DevelopParameters) {
        self = preset.baseParameters
        // preset 값에 사용자 델타를 더한다.
        exposure   += overrides.exposure
        contrast   += overrides.contrast
        density    += overrides.density
        highlight  += overrides.highlight
        shadow     += overrides.shadow
        whites     += overrides.whites
        blacks     += overrides.blacks
        curveHighlights += overrides.curveHighlights
        curveLights     += overrides.curveLights
        curveDarks      += overrides.curveDarks
        curveShadows    += overrides.curveShadows
        warmth     += overrides.warmth
        tint       += overrides.tint
        colorDepth += overrides.colorDepth
        vibrance   += overrides.vibrance
        saturation += overrides.saturation
        redPrimary += overrides.redPrimary
        greenPrimary += overrides.greenPrimary
        bluePrimary += overrides.bluePrimary
        // 고급 색/톤은 프리셋이 정의하지 않으므로 사용자 값을 그대로 채택.
        pointCurves = overrides.pointCurves
        colorMixer = overrides.colorMixer
        colorGrading = overrides.colorGrading
        calibration = overrides.calibration
        bwToning = overrides.bwToning
        filmEmulation = overrides.filmEmulation
        filmEmulationIntensity = overrides.filmEmulationIntensity
        grain      = max(grain, overrides.grain)
        sharpness  = max(sharpness, overrides.sharpness)
        halation   = max(halation, overrides.halation)
        clarity    += overrides.clarity
        vignette   += overrides.vignette
        defectRemoval = max(defectRemoval, overrides.defectRemoval)
        noiseReduction = max(noiseReduction, overrides.noiseReduction)
        // NR 축은 프리셋이 정의하지 않으므로 사용자 값을 그대로 채택.
        noiseReductionLuma = overrides.noiseReductionLuma
        noiseReductionChroma = overrides.noiseReductionChroma
        noiseReductionDarkTone = overrides.noiseReductionDarkTone
        noiseReductionDetail = overrides.noiseReductionDetail
        noiseReductionGrainProtect = overrides.noiseReductionGrainProtect
        localDodgeBurn = overrides.localDodgeBurn
        imageTransform = overrides.imageTransform
        filmType   = overrides.filmType
        developTarget = overrides.developTarget
        scannerProfileID = overrides.scannerProfileID
        baseEstimationMode = overrides.baseEstimationMode
        manualBaseRGB = overrides.manualBaseRGB
        filmStockDminID = overrides.filmStockDminID
        lightSourceProfileID = overrides.lightSourceProfileID
        autoLevels = overrides.autoLevels
        autoNeutralBalance = overrides.autoNeutralBalance
    }
}
