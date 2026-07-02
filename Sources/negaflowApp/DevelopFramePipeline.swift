import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit
import Metal

struct DevelopFrameSnapshot: @unchecked Sendable {
    let rawScanURL: URL
    // raw 입력 출처(로더 분기). 기본은 스캐너 TIFF.
    var sourceKind: FrameSource = .scannerTIFF
    // ICE 적용된 raw(메모리 CGImage). 있으면 이걸 입력으로 써서 원본 TIFF를 재디코딩하지 않는다.
    let preloadedRaw: CGImage?
    var preloadedPreviewRaw: DevelopFramePreviewRaw? = nil
    // 메모리 적재본이 없을 때의 디스크 백킹(ICE 적용된 raw TIFF). 그래도 결함 제거가 유지된다.
    let cleanedRawURL: URL?
    let filmType: FilmType
    let params: DevelopParameters
    let preset: LookPreset?
    let imageTransform: ImageTransform
    let cachedBase: FilmBase?
    let baseKey: FilmBaseCacheKey
    let needsRawPreview: Bool
    let needsNeutralPreview: Bool
    let needsDebugPreviews: Bool
    var softProof: SoftProofSettings = .disabled
    // 현상 프록시 긴 변 상한. 인터랙티브(드래그 중) 패스는 작게, 정착(settle) 패스는 풀해상도로.
    var proxyMaxDimension: CGFloat = DevelopFrameRenderer.fullMaxDimension
    // 썸네일만 생성(인터랙티브 패스에서 부가 비용 없이 스트립용 썸네일 확보).
    var needsThumbnail: Bool = true
}

struct DevelopFrameRenderResult: @unchecked Sendable {
    let base: FilmBase?
    let rawPreview: CGImage?
    let rawBase: CGImage?          // 변형 전 raw proxy (fast 회전/크롭용 캐시)
    let neutralPreview: CGImage?   // 무보정 현상본 (Before 비교용)
    let neutralBase: CGImage?      // 변형 전 무보정 현상본 (fast 회전/크롭용 캐시)
    let developed: CGImage
    let developedBase: CGImage     // 변형 전 현상 결과 (fast 회전/크롭용 캐시)
    let thumbnail: CGImage?        // 필름스트립용 경량 썸네일(긴 변 ~360px)
    let debugPreviews: [DevelopDebugPreview]
    let previewRaw: DevelopFramePreviewRaw?
}

struct DevelopFramePreviewRaw: @unchecked Sendable {
    let image: CGImage
    let usesLinearSRGB: Bool
}

struct DevelopDebugPreview: @unchecked Sendable {
    let stage: DevelopDebugStage
    let image: CGImage
    let metrics: DevelopDebugMetrics?
}

enum DevelopFrameRenderError: Error {
    case loadFailed
    case rawPreviewFailed
    case developedFailed
}

enum DevelopFrameRenderer {
    // 풀해상도 프리뷰 프록시 상한(정착 패스). 익스포트는 별도 풀해상도 경로라 영향받지 않는다.
    static let fullMaxDimension: CGFloat = 3600
    // 인터랙티브(드래그 중) 프록시 상한. 픽셀 수가 ~5배 적어 즉각적인 라이브 프리뷰를 준다.
    static let interactiveMaxDimension: CGFloat = 1600
    private static let thumbnailMaxDimension: CGFloat = 360
    // 공유 렌더 컨텍스트는 Metal command queue 로 만든다. 단일 큐로 GPU 작업이 정렬돼, 빠른 반복
    // 렌더에서 "GPU 쓰기 완료 전에 결과를 읽어 빈/검은 프레임이 나오는" 동기화 버블을 없앤다
    // (Apple WWDC 권장: contextWithMTLCommandQueue). 디바이스가 없으면 기존 GPU 옵션으로 폴백.
    private static let metalDevice = MTLCreateSystemDefaultDevice()
    private static let metalQueue = metalDevice?.makeCommandQueue()
    private static let sharedRenderContext: CIContext = {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ]
        if let queue = metalQueue {
            return CIContext(mtlCommandQueue: queue, options: options)
        }
        return CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
    }()
    private static let linearRawProxyContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
    ])
    private static let srgbRawProxyContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    ])

    static func render(_ snapshot: DevelopFrameSnapshot) throws -> DevelopFrameRenderResult {
        // 한 번의 현상에서 만든 중간 CIImage/IOSurface 버퍼를 패스 종료 시 즉시 반환(Apple 권장:
        // 반복 createCGImage 루프는 autoreleasepool 로 감싸 메모리 급증을 막는다).
        return try autoreleasepool {
            let engine = ChromabaseEngine()
            let context = renderContext()
            guard let input = resolveRenderInput(snapshot, engine: engine, context: context) else {
                throw DevelopFrameRenderError.loadFailed
            }
            let rawInput = input.image
            let base = snapshot.filmType.requiresInversion
                ? snapshot.cachedBase ?? engine.estimateFilmBase(
                    in: rawInput,
                    mode: snapshot.params.baseEstimationMode,
                    manual: snapshot.params.manualBaseRGB,
                    filmStockDminID: snapshot.params.filmStockDminID
                )
                : nil
            let rawPair = snapshot.needsRawPreview
                ? try renderRawPreview(
                    from: displayProxy(rawInput, maxDimension: snapshot.proxyMaxDimension),
                    transform: snapshot.imageTransform,
                    context: context
                )
                : nil
            let developedPair = try renderDeveloped(
                input: rawInput,
                base: base,
                snapshot: snapshot,
                engine: engine,
                context: context
            )
            let neutralPair = snapshot.needsNeutralPreview
                ? try renderNeutralPreview(
                    input: rawInput,
                    base: base,
                    snapshot: snapshot,
                    engine: engine,
                    context: context
                )
                : nil
            let debugPreviews = snapshot.needsDebugPreviews
                ? try renderDebugPreviews(
                    input: rawInput,
                    base: base,
                    snapshot: snapshot,
                    engine: engine,
                    context: context
                )
                : []
            let thumbnailImage = snapshot.needsThumbnail
                ? makeThumbnail(from: developedPair.transformed, context: context)
                : nil
            return DevelopFrameRenderResult(
                base: base,
                rawPreview: rawPair?.transformed,
                rawBase: rawPair?.base,
                neutralPreview: neutralPair?.transformed,
                neutralBase: neutralPair?.base,
                developed: developedPair.transformed,
                developedBase: developedPair.base,
                thumbnail: thumbnailImage,
                debugPreviews: debugPreviews,
                previewRaw: input.generatedPreviewRaw
            )
        }
    }

    /// 이미 렌더된 발색 CGImage 에서 작은 썸네일을 만든다(필름스트립용). 추가 색 연산 없이 축소만.
    private static func makeThumbnail(from cg: CGImage, context: CIContext) -> CGImage? {
        let maxSide = CGFloat(max(cg.width, cg.height))
        guard maxSide > thumbnailMaxDimension else { return cg }
        let scale = thumbnailMaxDimension / maxSide
        let image = CIImage(cgImage: cg).applyingFilter("CILanczosScaleTransform", parameters: [
            "inputScale": scale, "inputAspectRatio": 1.0,
        ])
        let target = CGRect(origin: .zero,
                            size: CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale))
        return context.createCGImage(image, from: target, format: .RGBA8,
                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    /// 무보정 현상본: Target=main, 스캐너 프로파일 없음, 프리셋/인스펙터 조정 전부 기본값.
    /// base/film/transform 만 사용자 설정을 따른다(반전 기준은 동일해야 Before/After가 정합).
    private static func renderNeutralPreview(
        input: CIImage,
        base: FilmBase?,
        snapshot: DevelopFrameSnapshot,
        engine: ChromabaseEngine,
        context: CIContext
    ) throws -> (transformed: CGImage, base: CGImage) {
        var neutral = DevelopParameters()
        neutral.filmType = snapshot.filmType
        neutral.developTarget = .main
        neutral.baseEstimationMode = snapshot.params.baseEstimationMode
        neutral.manualBaseRGB = snapshot.params.manualBaseRGB
        neutral.filmStockDminID = snapshot.params.filmStockDminID
        neutral.scannerProfileID = nil
        neutral.imageTransform = .identity
        let baseImage = engine.developScannerPreview(
            image: input,
            base: base,
            params: neutral,
            maxDimension: snapshot.proxyMaxDimension
        )
        guard let baseCG = renderDisplayCGImage(baseImage, context: context, softProof: snapshot.softProof) else {
            throw DevelopFrameRenderError.developedFailed
        }
        if snapshot.imageTransform.isIdentity {
            return (baseCG, baseCG)
        }
        let transformedImage = ImageTransformStage.apply(to: baseImage, transform: snapshot.imageTransform)
        guard let transformedCG = renderDisplayCGImage(transformedImage, context: context, softProof: snapshot.softProof) else {
            throw DevelopFrameRenderError.developedFailed
        }
        return (transformedCG, baseCG)
    }

    static func renderRawPreview(_ snapshot: DevelopFrameSnapshot) throws -> CGImage {
        let engine = ChromabaseEngine()
        let context = renderContext()
        guard let input = resolveRenderInput(snapshot, engine: engine, context: context) else {
            throw DevelopFrameRenderError.loadFailed
        }
        return try renderRawPreview(
            from: displayProxy(input.image, maxDimension: snapshot.proxyMaxDimension),
            transform: snapshot.imageTransform,
            context: context
        ).transformed
    }

    private struct RenderInput {
        let image: CIImage
        let generatedPreviewRaw: DevelopFramePreviewRaw?
    }

    private static func resolveRenderInput(
        _ snapshot: DevelopFrameSnapshot,
        engine: ChromabaseEngine,
        context: CIContext
    ) -> RenderInput? {
        if let cached = snapshot.preloadedPreviewRaw {
            return RenderInput(image: ciImage(from: cached), generatedPreviewRaw: nil)
        }
        if let preview = resolvePreviewInput(snapshot) {
            let proxy = materializedPreviewRaw(
                preview.image,
                usesLinearSRGB: preview.usesLinearSRGB,
                context: rawProxyContext(usesLinearSRGB: preview.usesLinearSRGB)
            )
            return RenderInput(
                image: proxy.map(ciImage(from:)) ?? preview.image,
                generatedPreviewRaw: proxy
            )
        }
        guard let rawInput = resolveRawInput(snapshot, engine: engine) else { return nil }
        guard shouldCachePreviewInput(rawInput.extent, maxDimension: snapshot.proxyMaxDimension) else {
            return RenderInput(image: rawInput, generatedPreviewRaw: nil)
        }
        let usesLinear = snapshot.sourceKind == .scannerTIFF
            || snapshot.preloadedRaw != nil
            || snapshot.cleanedRawURL != nil
            || rawInput.colorSpace?.name == CGColorSpace(name: CGColorSpace.linearSRGB)?.name
        let proxy = materializedPreviewRaw(
            displayProxy(rawInput, maxDimension: snapshot.proxyMaxDimension),
            usesLinearSRGB: usesLinear,
            context: rawProxyContext(usesLinearSRGB: usesLinear)
        )
        return RenderInput(
            image: proxy.map(ciImage(from:)) ?? rawInput,
            generatedPreviewRaw: proxy
        )
    }

    private static func resolvePreviewInput(_ snapshot: DevelopFrameSnapshot) -> ImageLoader.PreviewImage? {
        if let url = snapshot.cleanedRawURL {
            return ImageLoader.loadScannerPreview(
                url,
                maxDimension: snapshot.proxyMaxDimension,
                highResolutionThreshold: fullMaxDimension
            )
        }
        switch snapshot.sourceKind {
        case .scannerTIFF:
            return ImageLoader.loadScannerPreview(
                snapshot.rawScanURL,
                maxDimension: snapshot.proxyMaxDimension,
                highResolutionThreshold: fullMaxDimension
            )
        case .importedFile:
            return ImageLoader.loadImportedPreview(
                snapshot.rawScanURL,
                maxDimension: snapshot.proxyMaxDimension,
                highResolutionThreshold: fullMaxDimension
            )
        }
    }

    private static func materializedPreviewRaw(
        _ input: CIImage,
        usesLinearSRGB: Bool,
        context: CIContext
    ) -> DevelopFramePreviewRaw? {
        let colorSpace = usesLinearSRGB
            ? CGColorSpace(name: CGColorSpace.linearSRGB)!
            : CGColorSpace(name: CGColorSpace.sRGB)!
        let format: CIFormat = usesLinearSRGB ? .RGBA16 : .RGBA8
        guard let cg = context.createCGImage(input, from: input.extent.integral, format: format, colorSpace: colorSpace) else {
            return nil
        }
        return DevelopFramePreviewRaw(image: cg, usesLinearSRGB: usesLinearSRGB)
    }

    private static func ciImage(from preview: DevelopFramePreviewRaw) -> CIImage {
        if preview.usesLinearSRGB {
            return CIImage(cgImage: preview.image, options: [.colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!])
        }
        return CIImage(cgImage: preview.image)
    }

    private static func rawProxyContext(usesLinearSRGB: Bool) -> CIContext {
        usesLinearSRGB ? linearRawProxyContext : srgbRawProxyContext
    }

    private static func shouldCachePreviewInput(_ extent: CGRect, maxDimension: CGFloat) -> Bool {
        guard maxDimension > 0, extent.width > 0, extent.height > 0 else { return false }
        return max(extent.width, extent.height) > fullMaxDimension
            && max(extent.width, extent.height) > maxDimension
    }

    /// 우선순위: ICE 메모리 raw → ICE 디스크 백킹 → 원본 파일. 앞 둘이면 결함 제거가 반영된다.
    private static func resolveRawInput(_ snapshot: DevelopFrameSnapshot, engine: ChromabaseEngine) -> CIImage? {
        if let pre = snapshot.preloadedRaw {
            let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
            return CIImage(cgImage: pre, options: [.colorSpace: linear])
        }
        if let url = snapshot.cleanedRawURL, let ci = ImageLoader.loadScannerTIFF(url) {
            return ci
        }
        // 원본 파일 로드는 출처에 따라 분기한다. 스캐너 TIFF는 16bit linear 강제(loadScannerImage),
        // 가져온 파일(RAW/DNG/JPG/PNG/TIFF)은 ImageLoader.load(RAW 데모사이크 + 파일 색공간 보존).
        switch snapshot.sourceKind {
        case .scannerTIFF:  return engine.loadScannerImage(snapshot.rawScanURL)
        case .importedFile: return engine.loadImportedImage(snapshot.rawScanURL)
        }
    }

    /// 현상은 변형(회전/플립/크롭) 없이 수행해 `base`(변형 전)를 캐시로 남기고, 표시용은
    /// 그 위에 `ImageTransformStage`만 얹는다. 이후 회전/크롭은 무거운 색 파이프라인을 다시
    /// 돌리지 않고 `base`에 변형만 재적용하면 되므로 즉시 반영된다.
    private static func renderDeveloped(
        input: CIImage,
        base: FilmBase?,
        snapshot: DevelopFrameSnapshot,
        engine: ChromabaseEngine,
        context: CIContext
    ) throws -> (transformed: CGImage, base: CGImage) {
        var effectiveParams: DevelopParameters
        if let preset = snapshot.preset {
            effectiveParams = DevelopParameters(preset: preset, overrides: snapshot.params)
        } else {
            effectiveParams = snapshot.params
        }
        effectiveParams.filmType = snapshot.filmType
        effectiveParams.developTarget = snapshot.params.developTarget
        effectiveParams.imageTransform = .identity   // 변형은 표시 단계에서 별도 적용
        let baseImage = engine.developScannerPreview(
            image: input,
            base: base,
            params: effectiveParams,
            maxDimension: snapshot.proxyMaxDimension
        )
        // 미리보기 8bit 변환 직전 dithering으로 명부/하늘 banding 완화(OutputDither). 출력 계층에서만.
        guard let baseCG = renderDisplayCGImage(baseImage, context: context, softProof: snapshot.softProof) else {
            throw DevelopFrameRenderError.developedFailed
        }
        if snapshot.imageTransform.isIdentity {
            return (baseCG, baseCG)
        }
        let transformedImage = ImageTransformStage.apply(to: baseImage, transform: snapshot.imageTransform)
        guard let transformedCG = renderDisplayCGImage(transformedImage, context: context, softProof: snapshot.softProof) else {
            throw DevelopFrameRenderError.developedFailed
        }
        return (transformedCG, baseCG)
    }

    private static func renderDisplayCGImage(
        _ image: CIImage,
        context: CIContext,
        softProof: SoftProofSettings
    ) -> CGImage? {
        let proofed = SoftProof.apply(to: image, using: softProof)
        let colorSpace = softProof.isEnabled
            ? SoftProof.proofColorSpace(for: softProof)
            : CGColorSpace(name: CGColorSpace.sRGB)!
        return context.createCGImage(
            OutputDither.apply(to: proofed),
            from: proofed.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }

    private static func renderDebugPreviews(
        input: CIImage,
        base: FilmBase?,
        snapshot: DevelopFrameSnapshot,
        engine: ChromabaseEngine,
        context: CIContext
    ) throws -> [DevelopDebugPreview] {
        var effectiveParams = snapshot.preset.map {
            DevelopParameters(preset: $0, overrides: snapshot.params)
        } ?? snapshot.params
        effectiveParams.filmType = snapshot.filmType
        effectiveParams.developTarget = snapshot.params.developTarget
        effectiveParams.imageTransform = .identity
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        return try engine
            .developDebugFramesScannerPreview(
                image: input,
                base: base,
                params: effectiveParams,
                maxDimension: snapshot.proxyMaxDimension
            )
            .map { frame in
                let proxy = ImageTransformStage.apply(
                    to: displayProxy(frame.image, maxDimension: snapshot.proxyMaxDimension),
                    transform: snapshot.imageTransform
                )
                guard let cg = context.createCGImage(
                    proxy,
                    from: proxy.extent,
                    format: .RGBA8,
                    colorSpace: colorSpace
                ) else {
                    throw DevelopFrameRenderError.developedFailed
                }
                return DevelopDebugPreview(stage: frame.stage, image: cg, metrics: frame.metrics)
            }
    }

    private static func renderRawPreview(
        from input: CIImage,
        transform: ImageTransform,
        context: CIContext
    ) throws -> (transformed: CGImage, base: CGImage) {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let baseCG = context.createCGImage(input, from: input.extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw DevelopFrameRenderError.rawPreviewFailed
        }
        if transform.isIdentity {
            return (baseCG, baseCG)
        }
        let image = ImageTransformStage.apply(to: input, transform: transform)
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw DevelopFrameRenderError.rawPreviewFailed
        }
        return (cg, baseCG)
    }

    private static func displayProxy(_ input: CIImage, maxDimension: CGFloat = fullMaxDimension) -> CIImage {
        let extent = input.extent.integral
        let maxSide = max(extent.width, extent.height)
        guard maxSide > maxDimension else {
            return input
        }
        let scale = maxDimension / maxSide
        let scaledSize = CGSize(width: extent.width * scale, height: extent.height * scale)
        return input
            .applyingFilter("CILanczosScaleTransform", parameters: [
                "inputScale": scale,
                "inputAspectRatio": 1.0,
            ])
            .cropped(to: CGRect(origin: .zero, size: scaledSize))
    }

    private static func renderContext() -> CIContext {
        sharedRenderContext
    }
}
