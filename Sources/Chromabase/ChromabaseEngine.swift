import Foundation
import CoreImage
import CoreGraphics
import ImageIO

// MARK: - Chromabase color engine (plan §8)
//
// 스캔 원본(16bit linear RGB)을 현대적인 결과물로 바꾸는 색현상 엔진.
// plan §8.4 컬러 네거티브 처리 순서를 따른다.
//
//   Load → Normalize → FilmBaseEstimate → OrangeMaskRemoval
//   → NegativeInversion → ChannelBalance → Exposure
//   → Black/White soft clip → Density curve → Highlight roll-off
//   → ColorModel → LookPreset → Grain/Sharp/Halation → Output
//
// 모든 처리는 32bit float linear 영역에서 이루어진다 (plan §8.3).

/// 사용자가 조절하는 현상 파라미터. plan §8.7/§8.8.
public enum DevelopTarget: String, Codable, Sendable, CaseIterable {
    case main
    case print
    case noritsu
    case sp3000 = "sp-3000"

    public var displayName: String {
        switch self {
        case .main: return "main"
        case .print: return "print"
        case .noritsu: return "NORITSU"
        case .sp3000: return "SP-3000"
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

    // 고급 색/톤 (Lightroom 대응) — 기능별 서브구조체
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

    // 소프트웨어 ICE (먼지/스크래치 제거). IR 없이 RGB-only로 동작.
    public var defectRemoval: Double = 0.0   // 0...1 (0 = off, strength)

    // 사용자 노이즈 제거(chroma noise). 0 = off. 토글로 켜면 기본 강도 적용.
    // luma는 보존(그레인/디테일 유지), chroma residual만 비대칭(B>R)으로 제거 → 맨들거림/탈색 방지.
    public var noiseReduction: Double = 0.0  // 0...1 (0 = off, strength)

    public var localDodgeBurn: [LocalDodgeBurnAdjustment] = []

    public enum BaseMode: String, Codable, Sendable { case auto, manual, preset }

    public init() {}

    enum CodingKeys: String, CodingKey {
        case filmType, developTarget, scannerProfileID, baseEstimationMode, manualBaseRGB, filmStockDminID
        case exposure, contrast, density, highlight, shadow, whites, blacks
        case curveHighlights, curveLights, curveDarks, curveShadows
        case warmth, tint, colorDepth, vibrance, saturation
        case redPrimary, greenPrimary, bluePrimary
        case pointCurves, colorMixer, colorGrading, calibration, bwToning
        case filmEmulation, filmEmulationIntensity
        case grain, sharpness, halation, clarity, vignette, imageTransform
        case defectRemoval
        case noiseReduction
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
        localDodgeBurn = overrides.localDodgeBurn
        imageTransform = overrides.imageTransform
        filmType   = overrides.filmType
        developTarget = overrides.developTarget
        scannerProfileID = overrides.scannerProfileID
        baseEstimationMode = overrides.baseEstimationMode
        manualBaseRGB = overrides.manualBaseRGB
    }
}

public enum DevelopDebugStage: String, Codable, Sendable, CaseIterable {
    case afterInversion
    case afterAutoLevels
    case afterPrintBase
    case finalTone

    public var displayName: String {
        switch self {
        case .afterInversion: return "After Inversion"
        case .afterAutoLevels: return "After AutoLevels"
        case .afterPrintBase: return "After PrintBase"
        case .finalTone: return "Final Tone"
        }
    }
}

public struct DevelopDebugMetrics: Sendable {
    public let baseRGB: SIMD3<Double>?
    public let dmin: SIMD3<Double>?
    public let dmaxNorm: SIMD3<Double>?
    public let blackInput: SIMD3<Double>?

    public init(
        baseRGB: SIMD3<Double>?,
        dmin: SIMD3<Double>?,
        dmaxNorm: SIMD3<Double>?,
        blackInput: SIMD3<Double>?
    ) {
        self.baseRGB = baseRGB
        self.dmin = dmin
        self.dmaxNorm = dmaxNorm
        self.blackInput = blackInput
    }
}

public struct DevelopDebugFrame: @unchecked Sendable {
    public let stage: DevelopDebugStage
    public let image: CIImage
    public let metrics: DevelopDebugMetrics?

    public init(stage: DevelopDebugStage, image: CIImage, metrics: DevelopDebugMetrics?) {
        self.stage = stage
        self.image = image
        self.metrics = metrics
    }
}

/// 필름 베이스 추정 결과. plan §8.5.
public struct FilmBase: Codable, Sendable, Equatable {
    public var rgb: SIMD3<Double>     // 0...1 linear per channel
    public var source: Source
    public enum Source: String, Codable, Sendable { case auto, manual, border }
    public init(rgb: SIMD3<Double>, source: Source) { self.rgb = rgb; self.source = source }
}

// MARK: - Engine

public final class ChromabaseEngine: @unchecked Sendable {
    public init() {}

    // export(파일 쓰기) 전용 컨텍스트. 엔진은 현상 1회마다 새로 생성되므로(`DevelopFrameRenderer`),
    // 인스턴스 프로퍼티로 두면 미사용 develop 경로에서도 매번 CIContext가 할당돼 메모리가 누적된다.
    // export에서만 쓰이고 옵션이 고정이라 공유 static으로 둔다(스레드 안전).
    private static let exportContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
    ])
    private var ci: CIContext { Self.exportContext }

    /// 원본을 로드하고 FilmBase를 추정한다.
    public func estimateFilmBase(at url: URL, mode: DevelopParameters.BaseMode,
                                 manual: SIMD3<Double>? = nil) -> FilmBase? {
        guard let img = loadImage(url) else { return nil }
        return estimateFilmBase(in: img, mode: mode, manual: manual)
    }

    public func estimateFilmBase(in image: CIImage, mode: DevelopParameters.BaseMode,
                                 manual: SIMD3<Double>? = nil,
                                 filmStockDminID: String? = nil) -> FilmBase? {
        switch mode {
        case .manual:
            if let m = manual { return FilmBase(rgb: m, source: .manual) }
            fallthrough
        case .preset:
            // 프리셋: 필름 Dmin 투과율을 베이스로. UI 미리보기에도 동일 베이스 적용.
            if let id = filmStockDminID, let preset = FilmStockDminRegistry.find(id) {
                return FilmBase(rgb: preset.dminTransmission, source: .manual)
            }
            fallthrough
        case .auto:
            return FilmBaseEstimator.estimate(from: image)
        }
    }

    /// 전체 현상 파이프라인을 돌려 결과 CIImage를 반환한다.
    public func develop(image input: CIImage, base: FilmBase?, params: DevelopParameters) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let sampleColorSpace = input.colorSpace?.name == linear.name
            ? linear
            : CGColorSpace(name: CGColorSpace.sRGB)!
        return develop(
            image: input,
            base: base,
            params: params,
            sampleColorSpace: sampleColorSpace
        )
    }

    public func developScanner(image input: CIImage, base: FilmBase?, params: DevelopParameters) -> CIImage {
        // 노이즈 감소는 반전 전 raw(오렌지 상태)가 아니라 반전 후 positive에서 수행한다.
        // raw 네거티브의 chroma/luma 분리는 의미가 없어 데이터를 망가뜨린다.
        develop(
            image: input,
            base: base,
            params: params,
            sampleColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
    }

    public func developScannerPreview(
        image input: CIImage,
        base: FilmBase?,
        params: DevelopParameters,
        maxDimension: CGFloat
    ) -> CIImage {
        developScanner(
            image: Self.scannerPreviewProxy(input, maxDimension: maxDimension),
            base: base,
            params: params
        )
    }

    public func developDebugFramesScanner(
        image input: CIImage,
        base: FilmBase?,
        params: DevelopParameters
    ) -> [DevelopDebugFrame] {
        developDebugFrames(
            image: input,
            base: base,
            params: params,
            sampleColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
    }

    public func developDebugFramesScannerPreview(
        image input: CIImage,
        base: FilmBase?,
        params: DevelopParameters,
        maxDimension: CGFloat
    ) -> [DevelopDebugFrame] {
        developDebugFramesScanner(
            image: Self.scannerPreviewProxy(input, maxDimension: maxDimension),
            base: base,
            params: params
        )
    }

    private func develop(image input: CIImage,
                         base: FilmBase?,
                         params: DevelopParameters,
                         sampleColorSpace: CGColorSpace) -> CIImage {
        var img = input
        let extent = input.extent

        if params.filmType.requiresInversion {
            // ─── 네거티브 계열: 오렌지 마스크 제거 + 반전 (plan §8.4) ───
            // 1. Film base 추정(없으면 자동). 이 값은 raw 좌표계 기준이므로
            //    반전보다 먼저 AutoLevels를 적용하면 I/base가 틀어진다.
            let fb: FilmBase
            let preset: FilmStockDmin? = (params.baseEstimationMode == .preset)
                ? params.filmStockDminID.flatMap { FilmStockDminRegistry.find($0) } : nil
            if let manual = params.manualBaseRGB, params.baseEstimationMode == .manual {
                fb = FilmBase(rgb: manual, source: .manual)
            } else if let preset {
                // 필름 Dmin/Dmax 프리셋: 제조사 특성곡선에서 읽은 필름 물성값을 그대로 쓴다.
                // 자동 추정(장면 의존적 → 보라/염료분리 딜레마)을 완전히 우회 → 보라와 염료 분리 동시 해결.
                fb = FilmBase(rgb: preset.dminTransmission, source: .manual)
            } else {
                // 베이스 추정: 명시적 base → 자동 추정 → 폴백.
                // 폴백은 절대 일어나면 안 되지만 만약을 위한 안전망. 과거엔 진한 주황 (0.9,0.65,0.45)을
                // 강제해 옅은/Fuji/ECN-2 베이스에서 큰 캐스트를 만들었다. 폴백은 더 보수적이고 베이스
                // 비율(R≥G≥B)의 합리적 중간값인 옅은 주황을 쓴다. 단, 이 값보다 장면에서 측정한
                // 최대 투과율(p99.5)이 더 신뢰 가능하면(미노광이 실제로 존재) 그 비율로 보정한다.
                if let provided = base ?? FilmBaseEstimator.estimate(from: img) {
                    fb = provided
                } else {
                    // 최후의 보루: 베이스를 못 찾으면 엣지(가장 바깥)에서만 미노광 추정.
                    fb = estimateFallbackBaseFromScene(img)
                }
            }
            // 2-3. 오렌지 마스크 제거 + 네거티브 반전 (density-based)
            // 프리셋이 있으면 장면 독립적 필름 물성 dmaxNorm을 함께 전달해 보라/염료분리를 동시 해결.
            if let preset {
                img = NegativeInversion.apply(to: img, base: fb, preset: preset)
            } else {
                img = NegativeInversion.apply(to: img, base: fb)
            }
            // 노이즈 저감은 반전 직후(정규화 전) 이미지에 적용한다. AutoLevels로 0~1 범위로
            // 좁힌 뒤 적용하면 chroma 재결합이 휘도를 밀어올려 하이라이트가 블로우아웃된다.
            img = ScannerNoiseReduction.reduceMainTargetChroma(in: img)
            img = AutoLevels.apply(to: img, sampleColorSpace: sampleColorSpace, outputWhite: 0.95)
            // 채널별 정규화가 남긴 중간톤 캐스트(실측: 빨강 부족 → 시안/틸)를 채널별 감마로
            // 중립화. 끝점은 보존하므로 명부/암부에 새 캐스트를 만들지 않는다.
            img = NeutralBalance.apply(to: img, sampleColorSpace: sampleColorSpace)
            img = applyColorNegativePrintBase(to: img, extent: extent)
            // 명부 따뜻함 제거(옵션 C): per-channel 반전/AutoLevels 가 명부에서 남긴 R>B 잔류 캐스트를
            // luma 보존한 채 중립으로 당긴다(고채도 명부는 보호). 색이 거의 확정된 printBase 직후 1회.
            img = applyHighlightDesaturation(to: img)
            // 프린트 베이스의 채도 부스트(vibrance/saturation)가 만든 out-of-gamut를 hue 보존하며
            // 정리. 이걸 안 하면 뒤의 CIColorClamp/최종 출력에서 채널별로 잘려 명부 노랑·암부/미드
            // 보라·채널 크러시가 생긴다. main/profile 모든 경로가 이 위에 얹히므로 여기서 한 번.
            img = gamutSoftClip(img)
            if let profile = scannerProfile(for: params) {
                img = ScannerProfileGrade.apply(to: img, profile: profile)
            }
            img = ScannerNoiseReduction.reducePostGradeChroma(in: img)
            if fb.source == .manual {
                // Manual/Preset 모드: 사용자가 명시한 base 를 reference 베이스 톤으로 정규화해
                // 염료 분리/채도를 보존한다. 단 과거엔 게인이 무제한(최대 1.31배)이라 base 가 reference 보다
                // 어두울 때 B 채널이 폭발해 Histogram 명부가 우측으로 확장됐다(가짜 명부). 게인을 [0.85, 1.12]로
                // 클램프해 이 가짜 명부를 막으면서 염료 분리 보존 기능은 유지.
                // Auto 모드는 이 단계를 거치지 않는다(이미 NeutralBalance 가 채널 균형 담당).
                img = applyManualBaseAdjustment(to: img, base: fb.rgb)
            }
            if params.developTarget == .print {
                img = applyFinishedPrintTarget(to: img, extent: extent)
            }
            // 5-8. 채널 균형 + 노출 + 톤 커브 + 컬러
            img = ColorModel.apply(to: img, params: params)
            img = ToneMapper.applyExposure(to: img, stops: params.exposure)
            img = ToneMapper.applyToneCurves(to: img, params: params)
        } else {
            // ─── 포지티브/슬라이드 계열: 반전 없음, 슬라이드 특성 톤/컬러 ───
            // 1. Auto Levels — SANE genesys 백엔드는 감마/노출 보정 없이 raw 데이터를
            //    내보낸다. 포지티브는 raw 직후에 데이터를 정상 범위로 편다.
            //    과거 default(white 0.70, black→0)는 슬라이드를 어둡게(-0.3EV) 만들고 암부를
            //    0으로 뭉갰다. white를 올려 노출을 회복하고 black floor를 줘 암부 계조를 남긴다.
            img = AutoLevels.apply(
                to: img,
                blackClip: 0.002,
                sampleColorSpace: sampleColorSpace,
                outputWhite: 0.86,
                outputBlack: 0.014
            )
            img = PositiveDevelop.applyBaseGrade(to: img, filmType: params.filmType)
            if let profile = scannerProfile(for: params) {
                img = ScannerProfileGrade.apply(to: img, profile: profile)
            }
            if params.developTarget == .print {
                img = applyFinishedPrintTarget(to: img, extent: extent)
            }
            img = ColorModel.apply(to: img, params: params)
            img = ToneMapper.applyExposure(to: img, stops: params.exposure)
            img = ToneMapper.applyToneCurves(to: img, params: params)
        }

        // 8.4.x 고급 색/톤(Lightroom 대응) — 포인트 커브 → HSL 믹서 → 색보정 → 캘리브레이션.
        //   톤 커브(휘도/RGB 포인트)는 색 조정 전에, 캘리브레이션은 마지막에.
        img = PointCurveStage.apply(to: img, curves: params.pointCurves)
        img = ColorMixerStage.apply(to: img, mixer: params.colorMixer)
        img = ColorGradingStage.apply(to: img, grading: params.colorGrading)
        img = CalibrationStage.apply(to: img, calibration: params.calibration)

        // 8.4.y 슬라이드 필름 특성 룩(좌측 Film 탭). 모든 사용자 색/톤 보정 뒤, 텍스처/그레인 전에
        //   얹는 창의적 최종 룩(데이터시트 유도 E100 / Velvia 50). 채도 부스트가 만든 out-of-gamut 는
        //   아래 최종 gamutSoftClip 이 hue 보존하며 정리한다.
        img = FilmEmulationStage.apply(
            to: img,
            emulation: params.filmEmulation,
            intensity: params.filmEmulationIntensity
        )

        // 8.5 소프트웨어 ICE — 먼지/스크래치 제거. positive 상태에서 적용(임계값 의미 안정).
        if params.defectRemoval > 1e-3 {
            img = SoftwareICE.apply(to: img, strength: params.defectRemoval)
        }

        // 8.6 사용자 노이즈 제거. 그레인/텍스처 **이전**에 적용.
        if params.noiseReduction > 1e-3 {
            img = ChromaDenoise.apply(to: img, strength: params.noiseReduction)
        }

        if !params.localDodgeBurn.isEmpty {
            img = LocalDodgeBurnStage.apply(to: img, adjustments: params.localDodgeBurn)
        }

        // 9. 텍스처
        img = TextureStage.apply(to: img, params: params)

        // 10. B&W 필름은 모든 컬러 그레이딩/그레인 이후 최종적으로 중립 그레이스케일로 변환한다.
        //     (그레인/텍스처가 채널별로 색 얼룩을 더하므로 반드시 마지막 단계에서 적용.)
        if params.filmType == .bwNegative || params.filmType == .bwPositive {
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]).cropped(to: extent)
            img = BWToningStage.apply(to: img, toning: params.bwToning, filmType: params.filmType)
        }

        // 최종 gamut 매핑: 프로파일 그레이드·유저 조정(채도/노출/커브)·텍스처가 민 out-of-gamut를
        // 출력 직전에 hue 보존하며 정리(하드 per-channel 출력 클립 대체).
        if params.filmType != .bwNegative && params.filmType != .bwPositive {
            img = gamutSoftClip(img)
        }

        return ImageTransformStage.apply(
            to: img.cropped(to: extent),
            transform: params.imageTransform
        )
    }

    private func developDebugFrames(
        image input: CIImage,
        base: FilmBase?,
        params: DevelopParameters,
        sampleColorSpace: CGColorSpace
    ) -> [DevelopDebugFrame] {
        guard params.filmType.requiresInversion else { return [] }
        var img = input
        let extent = input.extent
        let preset: FilmStockDmin? = (params.baseEstimationMode == .preset)
            ? params.filmStockDminID.flatMap { FilmStockDminRegistry.find($0) } : nil
        let fb: FilmBase
        if let manual = params.manualBaseRGB, params.baseEstimationMode == .manual {
            fb = FilmBase(rgb: manual, source: .manual)
        } else if let preset {
            fb = FilmBase(rgb: preset.dminTransmission, source: .manual)
        } else if let provided = base ?? FilmBaseEstimator.estimate(from: img) {
            fb = provided
        } else {
            fb = estimateFallbackBaseFromScene(img)
        }

        let stats = negativeDebugMetrics(for: img, base: fb, preset: preset)
        if let preset {
            img = NegativeInversion.apply(to: img, base: fb, preset: preset)
        } else {
            img = NegativeInversion.apply(to: img, base: fb)
        }

        var frames = [
            DevelopDebugFrame(stage: .afterInversion, image: img.cropped(to: extent), metrics: stats),
        ]

        img = ScannerNoiseReduction.reduceMainTargetChroma(in: img)
        img = AutoLevels.apply(to: img, sampleColorSpace: sampleColorSpace, outputWhite: 0.95)
        frames.append(DevelopDebugFrame(stage: .afterAutoLevels, image: img.cropped(to: extent), metrics: stats))

        img = NeutralBalance.apply(to: img, sampleColorSpace: sampleColorSpace)
        img = applyColorNegativePrintBase(to: img, extent: extent)
        img = applyHighlightDesaturation(to: img)
        img = gamutSoftClip(img)
        frames.append(DevelopDebugFrame(stage: .afterPrintBase, image: img.cropped(to: extent), metrics: stats))

        if let profile = scannerProfile(for: params) {
            img = ScannerProfileGrade.apply(to: img, profile: profile)
        }
        img = ScannerNoiseReduction.reducePostGradeChroma(in: img)
        if fb.source == .manual {
            img = applyManualBaseAdjustment(to: img, base: fb.rgb)
        }
        img = ColorModel.apply(to: img, params: params)
        img = ToneMapper.applyExposure(to: img, stops: params.exposure)
        img = ToneMapper.applyToneCurves(to: img, params: params)
        frames.append(DevelopDebugFrame(stage: .finalTone, image: img.cropped(to: extent), metrics: stats))
        return frames
    }

    private func negativeDebugMetrics(
        for image: CIImage,
        base: FilmBase,
        preset: FilmStockDmin?
    ) -> DevelopDebugMetrics {
        let stats: NegativeInversion.ChannelStats
        if let preset {
            let sampledBlackInput = NegativeInversion.sampleStats(image, base: base)?.blackInput
            stats = NegativeInversion.ChannelStats(
                dmin: base.rgb,
                dmaxNorm: preset.dmaxNorm,
                blackInput: sampledBlackInput ?? NegativeInversion.fallbackStats(base: base).blackInput
            )
        } else {
            stats = NegativeInversion.sampleStats(image, base: base)
                ?? NegativeInversion.fallbackStats(base: base)
        }
        return DevelopDebugMetrics(
            baseRGB: base.rgb,
            dmin: stats.dmin,
            dmaxNorm: stats.dmaxNorm,
            blackInput: stats.blackInput
        )
    }

    /// Constant-hue gamut soft-clip (커널). 채널별 하드 클립이 만드는 hue 틀어짐(명부 노랑,
    /// 암부/미드 보라, 채널 크러시)을 막는다. in-gamut 픽셀은 그대로 통과.
    private func gamutSoftClip(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "gamutSoftClip") else { return image }
        return kernel.apply(extent: extent, arguments: [image])?.cropped(to: extent) ?? image
    }


    /// 명부 chroma desaturation (HIGHLIGHT_TONE_REDESIGN.md §5 옵션 C).
    /// per-channel 반전/AutoLevels 가 명부에서 남긴 "명부 따뜻함"(R>B 잔류 캐스트)을 luma 보존한 채
    /// 중립으로 당긴다. 고채도 명부(의도된 색)는 커널 내부 lowChromaBias 로 보호한다.
    /// strength: 명부 chroma 축소 비율 상한. startY: 명부로 간주하는 luma 시작점.
    private func applyHighlightDesaturation(to image: CIImage,
                                            strength: Double = 0.7,
                                            startY: Double = 0.70) -> CIImage {
        let extent = image.extent
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "highlightDesaturate") else { return image }
        return kernel.apply(extent: extent, arguments: [image, Float(strength), Float(startY)])?
            .cropped(to: extent) ?? image
    }

    private func scannerProfile(for params: DevelopParameters) -> ScannerProfile? {
        guard let id = params.scannerProfileID else { return nil }
        return ScannerProfileRegistry.load(named: id)
    }

    private func applyColorNegativePrintBase(to image: CIImage, extent: CGRect) -> CIImage {
        // 명부 처리 + 페이퍼 룩. 화이트홀/채널 크러시 방지가 핵심.
        // 합성 네거티브 측정(PrintBasePipelineDiagnosticTests)으로 확인된 과거 문제:
        //   (1) 이중 감마: NegativeInversion이 이미 페이퍼 감마(1/1.3≈0.77)를 적용하는데 여기서
        //       CIGammaAdjust 0.86 을 또 걸어 실효 감마 0.66(≈+0.3 stop 과다 전역 밝힘, 암부 노이즈
        //       증폭)이 됐다. darktable negadoctor 모델에서 페이퍼 감마는 한 곳(반전 단계)이다. → 제거.
        //   (2) 채도 과부스트: Vibrance 1.0 + saturation 1.12 가 명부 주황의 낮은 채널(B/G)을 0으로
        //       크러시해 주황을 순수 노랑(측정값 R=239 G=238 B=0)으로 만들었다. negadoctor는 채도를
        //       부스트하지 않는다(색은 밀도 반전에서 자연 발생). → 전역 saturation 곱 제거(채널 클립
        //       방지), Vibrance는 약하게(0.2)만 남겨 낮은-채도 영역만 보강(높은 채도는 보존).
        // 톤 곡선은 명부를 1.0 이 아닌 0.76 숄더로 롤오프해 계조를 남긴다(유지).
        MainTargetGrade.apply(to: image)
            .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.2])
            .applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(x: 0.00, y: 0.025),
                "inputPoint1": CIVector(x: 0.25, y: 0.225),
                "inputPoint2": CIVector(x: 0.50, y: 0.500),
                "inputPoint3": CIVector(x: 0.80, y: 0.760),
                "inputPoint4": CIVector(x: 1.00, y: 1.000),
            ])
            .applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius": 2.5, "inputIntensity": 0.35,
            ])
            .cropped(to: extent)
    }

    private func applyFinishedPrintTarget(to image: CIImage, extent: CGRect) -> CIImage {
        image
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.08,
                kCIInputSaturationKey: 1.06,
                kCIInputBrightnessKey: -0.006,
            ])
            .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.16])
            .applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(x: 0.00, y: 0.018),
                "inputPoint1": CIVector(x: 0.20, y: 0.155),
                "inputPoint2": CIVector(x: 0.50, y: 0.520),
                "inputPoint3": CIVector(x: 0.82, y: 0.885),
                "inputPoint4": CIVector(x: 1.00, y: 0.990),
            ])
            .cropped(to: extent)
    }

    /// 최후의 베이스 추정 폴백. FilmBaseEstimator가 완전히 실패한 경우에만 도달.
    ///
    /// 베이스(Dmin)는 darktable negadoctor / PhotoVision 모두 "노광되지 않고 현상된 필름 영역"의
    /// 밀도로 정의한다 — 즉 **필름의 가장 바깥(엣지) 미노광**에서만 측정해야 한다. 장면 본체의
    /// 밝은 영역(흰 벽·하늘·얼굴 하이라이트)을 베이스로 쓰면 피사체를 미노광으로 오인해 큰 캐스트가
    /// 생긴다. 따라서 이 폴백은:
    ///   1. 엣지(가장 바깥 6%)에서만 R≥G≥B 단조이고 밝은 미노광 후보를 수집한다.
    ///   2. 엣지에 미노광이 충분히 있으면(32+ 후보) → 그것이 진짜 베이스.
    ///   3. 엣지에 미노광이 없으면(필름 홀더/마운트가 가리거나 풀프레임 촬영) → 장면 본체를
    ///      건드리지 않고 **필름 종류 무관 안전 기본값**으로 떨어진다. PhotoVision 권고대로 합리적
    ///      중간값(Kodak 진주황과 Fuji 황 베이스의 중간)을 써 WB 오차를 최소화한다.
    ///      장면에서 베이스를 억지로 추출하지 않는다 — 그게 피사체 오인의 원인이다.
    private func estimateFallbackBaseFromScene(_ image: CIImage) -> FilmBase {
        guard let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else {
            return FilmBase(rgb: SIMD3(0.86, 0.68, 0.50), source: .auto)
        }
        let extent = image.extent
        let targetW = max(64, min(320, Int(extent.width)))
        let scale = Double(targetW) / Double(extent.width)
        let targetH = max(1, Int(Double(extent.height) * scale))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        var bitmap = [Float](repeating: 0, count: targetW * targetH * 4)
        SamplingContextPool.context(workingColorSpace: linear).render(
            scaled,
            toBitmap: &bitmap,
            rowBytes: targetW * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
            format: .RGBAf,
            colorSpace: linear
        )
        // 엣지(가장 바깥 6%)에서만 미노광 후보 수집. 장면 본체는 절대 포함 안 함.
        let edgeFrac = 0.06
        let ex = max(1, Int(Double(targetW) * edgeFrac))
        let ey = max(1, Int(Double(targetH) * edgeFrac))
        var rVals: [Double] = [], gVals: [Double] = [], bVals: [Double] = []
        for y in 0..<targetH {
            for x in 0..<targetW {
                let isEdge = x < ex || x >= targetW - ex || y < ey || y >= targetH - ey
                guard isEdge else { continue }
                let i = (y * targetW + x) * 4
                let r = Double(bitmap[i])
                let g = Double(bitmap[i + 1])
                let b = Double(bitmap[i + 2])
                let luma = (r + g + b) / 3
                // 미노광: 밝고 R≥G≥B 단조(컬러 네거티브 베이스의 물리적 특성).
                guard luma > 0.30, luma < 0.92, r >= g - 0.01, g >= b - 0.01, (r - b) >= 0.04 else { continue }
                rVals.append(r); gVals.append(g); bVals.append(b)
            }
        }
        // 엣지에 미노광이 충분히 있으면 → 진짜 베이스. 없으면 안전 기본값(피사체 오인 방지).
        guard rVals.count >= 32 else {
            return FilmBase(rgb: SIMD3(0.86, 0.68, 0.50), source: .auto)
        }
        func pct(_ a: [Double], _ p: Double) -> Double {
            let s = a.sorted(); let idx = Int(p * Double(s.count - 1)); return s[idx]
        }
        return FilmBase(rgb: SIMD3(pct(rVals, 0.90), pct(gVals, 0.90), pct(bVals, 0.90)), source: .auto)
    }

    /// Manual/Preset 모드 전용: 사용자가 명시한 base 를 reference 베이스 톤(진한 주황)으로 정규화해
    /// 염료 분리/채도를 보존한다. 게인은 [0.85, 1.12]로 클램프 — base 가 reference 보다 어두워도
    /// B 채널이 폭발(과거 1.31배 → Histogram 명부 우측 확장/가짜 명부)하지 않게 막는다.
    /// Auto 모드는 이 단계를 거치지 않는다.
    private func applyManualBaseAdjustment(to image: CIImage, base: SIMD3<Double>) -> CIImage {
        let reference = SIMD3<Double>(0.86, 0.54, 0.34)
        let strength = 0.55
        func clampGain(_ raw: Double) -> Double { min(max(raw, 0.85), 1.12) }
        let r = clampGain(1.0 + (reference.x - base.x) / max(reference.x, 1e-3) * strength)
        let g = clampGain(1.0 + (reference.y - base.y) / max(reference.y, 1e-3) * strength)
        let b = clampGain(1.0 + (reference.z - base.z) / max(reference.z, 1e-3) * strength)
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ]).cropped(to: image.extent)
    }

    /// 파일 → 파일 현상 + 출력.
    public func developFile(input: URL, output: URL, format: ExportFormat,
                            base: FilmBase?, params: DevelopParameters,
                            metadata: ExportMeta? = nil) throws {
        guard let inputImg = loadImage(input) else {
            throw ChromabaseError.loadFailed(input.path)
        }
        let developed = develop(image: inputImg, base: base, params: params)
        try ExportEngine.write(developed, to: output, format: format, using: ci, metadata: metadata)
    }

    public func developScannerFile(input: URL, output: URL, format: ExportFormat,
                                   base: FilmBase?, params: DevelopParameters,
                                   metadata: ExportMeta? = nil) throws {
        guard let inputImg = loadScannerImage(input) else {
            throw ChromabaseError.loadFailed(input.path)
        }
        let developed = developScanner(image: inputImg, base: base, params: params)
        try ExportEngine.write(developed, to: output, format: format, using: ci, metadata: metadata)
    }

    // MARK: helpers
    /// 파일 로드는 ImageLoader로 위임. TIFF/JPEG/PNG/DNG/RAW 모두 지원.
    public func loadImage(_ url: URL) -> CIImage? {
        ImageLoader.load(url, allowRaw: true)
    }

    public func loadScannerImage(_ url: URL) -> CIImage? {
        ImageLoader.loadScannerTIFF(url)
    }

    /// 가져온 파일(사용자 이미지) 전용 로더. 카메라 RAW/DNG 데모사이크 + 임베디드 색상 프로필 존중
    /// + 프로필 없는 16bit 스캐너 raw(VueScan/SilverFast)를 linear 로 해석한다.
    public func loadImportedImage(_ url: URL) -> CIImage? {
        ImageLoader.loadImported(url)
    }

    private static func scannerPreviewProxy(_ input: CIImage, maxDimension: CGFloat) -> CIImage {
        guard maxDimension > 0 else { return input }
        let extent = input.extent.integral
        let maxSide = max(extent.width, extent.height)
        guard maxSide > maxDimension, extent.width > 0, extent.height > 0 else {
            return input
        }
        let scale = maxDimension / maxSide
        let scaledSize = CGSize(width: extent.width * scale, height: extent.height * scale)
        let normalized = input.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        return normalized
            .applyingFilter("CILanczosScaleTransform", parameters: [
                "inputScale": scale,
                "inputAspectRatio": 1.0,
            ])
            .cropped(to: CGRect(origin: .zero, size: scaledSize))
    }
}

public enum ChromabaseError: Error, LocalizedError {
    case loadFailed(String)
    case writeFailed(String)
    public var errorDescription: String? {
        switch self {
        case .loadFailed(let p):  return "Failed to load image: \(p)"
        case .writeFailed(let p): return "Failed to write image: \(p)"
        }
    }
}

public enum ExportFormat: String, Sendable {
    case jpeg
    case png
    case tiff16
    case rawScanTIFF
}
