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
public struct DevelopParameters: Codable, Sendable, Equatable {
    // Base
    public var filmType: FilmType = .colorNegative
    public var baseEstimationMode: BaseMode = .auto
    public var manualBaseRGB: SIMD3<Double>? = nil   // 수동 base picker 결과

    // Tone (plan §8.7) — 기본 UI
    public var exposure: Double = 0.0        // stops
    public var density: Double = 0.0         // -1...1
    public var highlight: Double = 0.0       // -1...1 (roll-off)
    public var shadow: Double = 0.0          // -1...1 (black softness)

    // Color (plan §8.8) — 기본 UI
    public var warmth: Double = 0.0          // -1...1
    public var tint: Double = 0.0            // -1...1
    public var colorDepth: Double = 0.0      // -1...1 (saturation)

    // Texture
    public var grain: Double = 0.0           // 0...1
    public var sharpness: Double = 0.0       // 0...1
    public var halation: Double = 0.0        // 0...1
    public var imageTransform: ImageTransform = .identity

    public enum BaseMode: String, Codable, Sendable { case auto, manual }

    public init() {}

    /// LookPreset의 값을 얹은 뒤 사용자 조절을 적용한다.
    public init(preset: LookPreset, overrides: DevelopParameters) {
        self = preset.baseParameters
        // preset 값에 사용자 델타를 더한다.
        exposure   += overrides.exposure
        density    += overrides.density
        highlight  += overrides.highlight
        shadow     += overrides.shadow
        warmth     += overrides.warmth
        tint       += overrides.tint
        colorDepth += overrides.colorDepth
        grain      = max(grain, overrides.grain)
        sharpness  = max(sharpness, overrides.sharpness)
        halation   = max(halation, overrides.halation)
        imageTransform = overrides.imageTransform
        filmType   = overrides.filmType
        baseEstimationMode = overrides.baseEstimationMode
        manualBaseRGB = overrides.manualBaseRGB
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

    private let ci = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: NSNull(),   // 결과 색공간은 출력 시 명시
    ])

    /// 원본을 로드하고 FilmBase를 추정한다.
    public func estimateFilmBase(at url: URL, mode: DevelopParameters.BaseMode,
                                 manual: SIMD3<Double>? = nil) -> FilmBase? {
        guard let img = loadImage(url) else { return nil }
        switch mode {
        case .manual:
            if let m = manual { return FilmBase(rgb: m, source: .manual) }
            fallthrough
        case .auto:
            return FilmBaseEstimator.estimate(from: img)
        }
    }

    /// 전체 현상 파이프라인을 돌려 결과 CIImage를 반환한다.
    public func develop(image input: CIImage, base: FilmBase?, params: DevelopParameters) -> CIImage {
        var img = ImageTransformStage.apply(to: input, transform: params.imageTransform)
        let extent = img.extent

        if params.filmType.requiresInversion {
            // ─── 네거티브 계열: 오렌지 마스크 제거 + 반전 (plan §8.4) ───
            // 2. Film base 추정(없으면 자동).
            let fb = base ?? FilmBaseEstimator.estimate(from: img) ??
                     FilmBase(rgb: SIMD3(0.9, 0.65, 0.45), source: .auto)
            // 3-4. 오렌지 마스크 제거 + 네거티브 반전 (density-based)
            img = NegativeInversion.apply(to: img, base: fb)
            // 5-8. 채널 균형 + 노출 + 톤 커브 + 컬러
            img = ColorModel.apply(to: img, params: params)
            img = ToneMapper.applyExposure(to: img, stops: params.exposure)
            img = ToneMapper.applyToneCurves(to: img, params: params)
        } else {
            // ─── 포지티브/슬라이드 계열: 반전 없음, 슬라이드 특성 톤/컬러 ───
            // 슬라이드는 이미 양화 상태. 높은 밀도, 선명한 컬러, 딥 블랙,
            // 하이라이트 보호가 핵심이다 (plan §8.9 Deep Slide 참고).
            img = AutoLevels.apply(to: img)
            img = PositiveDevelop.applyBaseGrade(to: img, filmType: params.filmType)
            img = ColorModel.apply(to: img, params: params)
            img = ToneMapper.applyExposure(to: img, stops: params.exposure)
            img = ToneMapper.applyToneCurves(to: img, params: params)
        }

        // 9. 텍스처
        img = TextureStage.apply(to: img, params: params)

        // 10. extent를 원본에 한정 (필터 체인이 무한 extent를 만들지 않게).
        return img.cropped(to: extent)
    }

    /// 파일 → 파일 현상 + 출력.
    public func developFile(input: URL, output: URL, format: ExportFormat,
                            base: FilmBase?, params: DevelopParameters) throws {
        guard let inputImg = loadImage(input) else {
            throw ChromabaseError.loadFailed(input.path)
        }
        let developed = develop(image: inputImg, base: base, params: params)
        try ExportEngine.write(developed, to: output, format: format, using: ci)
    }

    // MARK: helpers
    /// 파일 로드는 ImageLoader로 위임. TIFF/JPEG/PNG/DNG/RAW 모두 지원.
    public func loadImage(_ url: URL) -> CIImage? {
        ImageLoader.load(url, allowRaw: true)
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
    case tiff16
    case rawScanTIFF
}
