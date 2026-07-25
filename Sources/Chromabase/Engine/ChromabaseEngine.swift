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

/// 필름 베이스 추정 결과. plan §8.5.
public struct FilmBase: Codable, Sendable, Equatable {
    public var rgb: SIMD3<Double>     // 0...1 linear per channel
    public var source: Source
    public var measurementDiagnostics: FilmBaseMeasurementDiagnostics?
    public enum Source: String, Codable, Sendable { case auto, manual, border }
    public init(
        rgb: SIMD3<Double>,
        source: Source,
        measurementDiagnostics: FilmBaseMeasurementDiagnostics? = nil
    ) {
        self.rgb = rgb
        self.source = source
        self.measurementDiagnostics = measurementDiagnostics
    }
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

    /// base(Dmin)에 선택된 광원 프로파일의 채널 게인을 적용한다. neutral/미선택/흑백이면 무변경.
    /// 프리셋 경로의 단일 적용 지점 — estimateFilmBase(앱 base 소스)와 resolveFilmBase(fresh 폴백)가 공유.
    static func applyLightSourceGain(to base: FilmBase, lightSourceProfileID: String?,
                                     neutralBase: Bool) -> FilmBase {
        guard !neutralBase,
              let light = LightSourceProfileRegistry.find(lightSourceProfileID),
              light.id != LightSourceProfileRegistry.neutral.id else { return base }
        return FilmBase(rgb: light.applyGain(to: base.rgb), source: base.source)
    }

    public func estimateFilmBase(in image: CIImage, mode: DevelopParameters.BaseMode,
                                 manual: SIMD3<Double>? = nil,
                                 filmStockDminID: String? = nil,
                                 lightSourceProfileID: String? = nil,
                                 filmType: FilmType = .colorNegative) -> FilmBase? {
        let neutralBase = filmType == .bwNegative
        switch mode {
        case .manual:
            if let m = manual { return FilmBase(rgb: m, source: .manual) }
            fallthrough
        case .preset:
            // 프리셋: **실측 우선** — 스캔에서 베이스가 실측되면 그것이 Dmin 앵커(스캐너/광원/
            // 퇴색을 흡수). 프리셋의 역할은 dmaxNorm(필름 물성). 실측 불가 시에만 프리셋 Dmin
            // × 광원 트림 폴백.
            if let id = filmStockDminID, let preset = FilmStockDminRegistry.find(id) {
                // base(Dmin): 실측 우선, 없으면 프리셋 폴백.
                let resolved: FilmBase = Self.estimateBaseWithChromogenicFallback(
                    from: image, neutralBase: neutralBase, confidentOnly: true)
                    ?? FilmBase(rgb: preset.dminTransmission, source: .manual)
                // 광원 게인을 base(WB 앵커)에 적용 — 선택이 시각적으로 반영된다(실측/폴백 공통).
                // neutral/미선택=무변경. 흑백은 단일 중립 곡선이라 무의미하므로 적용하지 않는다.
                return Self.applyLightSourceGain(to: resolved, lightSourceProfileID: lightSourceProfileID,
                                                 neutralBase: neutralBase)
            }
            fallthrough
        case .auto:
            return Self.estimateBaseWithChromogenicFallback(from: image, neutralBase: neutralBase)
        }
    }

    /// 흑백 네거티브의 베이스 추정 + 크로모제닉 폴백. 전통 흑백은 중립 베이스지만,
    /// C-41 크로모제닉 흑백(Ilford XP2 등)은 오렌지/퍼플 틴트 베이스다. 중립 추정은 틴트
    /// 베이스에서 실패(nil)하거나 **장면의 저채도 영역을 베이스로 오인**(틴트 채널비를 그대로
    /// 가진 오답)할 수 있으므로, nil 뿐 아니라 결과의 채널 비율(max/min > 1.25 — 중립 베이스는
    /// 추정 노이즈를 포함해도 이보다 훨씬 균형)이 비중립이면 컬러 베이스 추정으로 재시도한다.
    /// 반전은 채널별 Dmin 정규화로 틴트를 흡수하고, 출력은 PostPipeline 이 흑백을 강제
    /// 중립화하므로 안전하다.
    static func estimateBaseWithChromogenicFallback(
        from image: CIImage, neutralBase: Bool, confidentOnly: Bool = false
    ) -> FilmBase? {
        let neutralEstimate = FilmBaseEstimator.estimate(from: image, neutralBase: neutralBase,
                                                         confidentOnly: confidentOnly)
        guard neutralBase else { return neutralEstimate }
        if let base = neutralEstimate {
            let mx = max(base.rgb.x, max(base.rgb.y, base.rgb.z))
            let mn = min(base.rgb.x, min(base.rgb.y, base.rgb.z))
            if mn > 1e-6, mx / mn <= 1.25 { return base }
        }
        // 틴트 베이스(크로모제닉) 의심 — 컬러 추정으로 재시도, 그마저 실패면 중립 결과 유지.
        return FilmBaseEstimator.estimate(from: image, neutralBase: false,
                                          confidentOnly: confidentOnly) ?? neutralEstimate
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
            img = applyNegativeFilmPipeline(
                to: img,
                base: base,
                params: params,
                sampleColorSpace: sampleColorSpace,
                extent: extent
            )
        } else {
            img = applyPositiveFilmPipeline(
                to: img,
                params: params,
                sampleColorSpace: sampleColorSpace,
                extent: extent
            )
        }

        img = applyPostPipeline(to: img, params: params, extent: extent)
        // PRINT는 완성된 MAIN 뒤의 출력 경계이며 working image에는 별도 룩을 넣지 않는다.
        return img
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
        let fb = resolveFilmBase(for: img, provided: base, preset: preset, params: params)

        let stats = negativeDebugMetrics(
            for: img, base: fb, preset: preset, filmType: params.filmType
        )
        if let preset {
            img = NegativeInversion.apply(
                to: img, base: fb, preset: preset, filmType: params.filmType
            )
        } else {
            img = NegativeInversion.applySceneRanged(to: img, base: fb, filmType: params.filmType)
        }

        var frames = [
            DevelopDebugFrame(stage: .afterInversion, image: img.cropped(to: extent), metrics: stats),
        ]

        // 측정 도메인은 본 파이프라인과 동일하게 입력 태그 무관 linear 고정.
        let measureSpace = CGColorSpace(name: CGColorSpace.linearSRGB) ?? sampleColorSpace
        if params.autoLevels {
            img = AutoLevels.apply(to: img, sampleColorSpace: measureSpace,
                                   outputWhite: 0.95,
                                   outputBlack: NegativeInversion.toeFloor)
        }
        frames.append(DevelopDebugFrame(stage: .afterAutoLevels, image: img.cropped(to: extent), metrics: stats))

        if params.autoNeutralBalance {
            img = NeutralBalance.apply(to: img, sampleColorSpace: measureSpace)
        }
        if params.developTarget.isScannerEmulation {
            img = ScannerTargetGrade.apply(to: img, target: params.developTarget, params: params)
        }
        if params.developTarget == .rescue {
            // 본 파이프라인과 동일: 검증된 중립축 증거가 있을 때만 bounded 상대 보정.
            img = RescueGrade.apply(to: img, sampleColorSpace: measureSpace,
                                    filmType: params.filmType,
                                    recoverRange: false)
        }
        // 본 파이프라인과 동일: 타겟 프로파일 밖의 고정 NR·명부 탈채도·gamut 압축 없음.
        frames.append(DevelopDebugFrame(stage: .afterPrintBase, image: img.cropped(to: extent), metrics: stats))

        if !params.developTarget.isScannerEmulation,
           params.developTarget != .rescue,
           let profile = scannerProfile(for: params) {
            img = ScannerProfileGrade.apply(to: img, profile: profile)
        }
        img = ColorModel.apply(to: img, params: params)
        img = ToneMapper.applyExposure(to: img, stops: params.exposure)
        img = ToneMapper.applyToneCurves(to: img, params: params)
        frames.append(DevelopDebugFrame(stage: .finalTone, image: img.cropped(to: extent), metrics: stats))
        return frames
    }

    /// 파일 → 파일 현상 + 출력.
    public func developFile(input: URL, output: URL, format: ExportFormat,
                            base: FilmBase?, params: DevelopParameters,
                            metadata: ExportMeta? = nil,
                            outputProfile: ICCOutputProfileSnapshot? = nil) throws {
        try ExportDestinationSafety.validateDistinct(
            protectedSources: [input],
            outputURLs: [output]
        )
        if format == .rawScanTIFF {
            guard outputProfile == nil else {
                throw ChromabaseError.writeFailed("invalid printer output ICC profile")
            }
        } else if params.developTarget == .print,
                  outputProfile?.validatedColorSpace() == nil {
            throw ChromabaseError.writeFailed(
                "PRINT export requires a valid RGB printer-class ICC profile"
            )
        }
        guard let inputImg = loadImage(input) else {
            throw ChromabaseError.loadFailed(input.path)
        }
        let outputImage = format == .rawScanTIFF
            ? inputImg
            : develop(image: inputImg, base: base, params: params)
        try ExportEngine.write(
            outputImage,
            to: output,
            format: format,
            using: ci,
            metadata: metadata,
            outputProfile: params.developTarget == .print ? outputProfile : nil
        )
    }

    public func developScannerFile(input: URL, output: URL, format: ExportFormat,
                                   base: FilmBase?, params: DevelopParameters,
                                   metadata: ExportMeta? = nil,
                                   outputProfile: ICCOutputProfileSnapshot? = nil) throws {
        try ExportDestinationSafety.validateDistinct(
            protectedSources: [input],
            outputURLs: [output]
        )
        if format == .rawScanTIFF {
            guard outputProfile == nil else {
                throw ChromabaseError.writeFailed("invalid printer output ICC profile")
            }
        } else if params.developTarget == .print,
                  outputProfile?.validatedColorSpace() == nil {
            throw ChromabaseError.writeFailed(
                "PRINT export requires a valid RGB printer-class ICC profile"
            )
        }
        guard let inputImg = loadScannerImage(input) else {
            throw ChromabaseError.loadFailed(input.path)
        }
        let outputImage = format == .rawScanTIFF
            ? inputImg
            : developScanner(image: inputImg, base: base, params: params)
        try ExportEngine.write(
            outputImage,
            to: output,
            format: format,
            using: ci,
            metadata: metadata,
            outputProfile: params.developTarget == .print ? outputProfile : nil
        )
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

public enum ExportFormat: String, Sendable, Codable {
    case jpeg
    case png
    case tiff16
    case rawScanTIFF
}
