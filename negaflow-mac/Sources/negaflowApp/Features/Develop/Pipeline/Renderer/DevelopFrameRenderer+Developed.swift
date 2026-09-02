import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit
import Metal

extension DevelopFrameRenderer {
    /// 현상은 변형(회전/플립/크롭) 없이 수행해 `base`(변형 전)를 캐시로 남기고, 표시용은
    /// 그 위에 `ImageTransformStage`만 얹는다. 이후 회전/크롭은 무거운 색 파이프라인을 다시
    /// 돌리지 않고 `base`에 변형만 재적용하면 되므로 즉시 반영된다.
    static func renderDeveloped(
        input: CIImage,
        base: FilmBase?,
        snapshot: DevelopFrameSnapshot,
        engine: ChromabaseEngine,
        context: CIContext,
        measurements: inout DevelopSceneMeasurements
    ) throws -> (
        transformed: CGImage,
        base: CGImage,
        workingBase: CGImage?,
        clippingOverlay: CGImage?,
        clippingOverlayBase: CGImage?,
        destinationGamutOverlay: CGImage?,
        destinationGamutOverlayBase: CGImage?,
        thumbnailBase: CGImage?,
        thumbnail: CGImage?
    ) {
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
            maxDimension: snapshot.proxyMaxDimension,
            measurements: &measurements
        )
        // 미리보기 8bit 변환 직전 dithering으로 명부/하늘 banding 완화(OutputDither). 출력 계층에서만.
        guard let baseCG = renderDisplayCGImage(
            baseImage,
            context: context,
            softProof: snapshot.softProof,
            developTarget: snapshot.params.developTarget
        ) else {
            throw DevelopFrameRenderError.developedFailed
        }
        let workingBase = snapshot.needsPixelSamplerBase
            ? renderWorkingSamplerImage(baseImage, context: context)
            : nil
        let clippingOverlayBase = snapshot.clippingOverlayEnabled
            ? renderClippingOverlay(baseImage, context: context)
            : nil
        let destinationGamutOverlayBase = snapshot.destinationGamutWarningEnabled
            ? DestinationGamutWarning.makeOverlay(
                for: baseImage,
                context: context,
                settings: displaySoftProofSettings(
                    snapshot.softProof,
                    developTarget: snapshot.params.developTarget
                )
            )?.overlay
            : nil
        let shouldBuildThumbnailBase = snapshot.needsThumbnail
            || snapshot.proxyMaxDimension >= DevelopFrameRenderer.fullMaxDimension - 0.5
        let thumbnailBase = shouldBuildThumbnailBase
            ? renderUnproofedThumbnail(baseImage, context: context)
            : nil
        if snapshot.imageTransform.isIdentity {
            return (
                baseCG, baseCG, workingBase,
                clippingOverlayBase, clippingOverlayBase,
                destinationGamutOverlayBase, destinationGamutOverlayBase,
                thumbnailBase,
                snapshot.needsThumbnail ? thumbnailBase : nil
            )
        }
        let transformedImage = ImageTransformStage.apply(to: baseImage, transform: snapshot.imageTransform)
        guard let transformedCG = renderDisplayCGImage(
            transformedImage,
            context: context,
            softProof: snapshot.softProof,
            developTarget: snapshot.params.developTarget
        ) else {
            throw DevelopFrameRenderError.developedFailed
        }
        let clippingOverlay = snapshot.clippingOverlayEnabled
            ? renderClippingOverlay(transformedImage, context: context)
            : nil
        let destinationGamutOverlay = destinationGamutOverlayBase.flatMap {
            renderOverlay($0, transform: snapshot.imageTransform, context: context)
        }
        let thumbnail = snapshot.needsThumbnail
            ? renderUnproofedThumbnail(transformedImage, context: context)
            : nil
        return (
            transformedCG, baseCG, workingBase,
            clippingOverlay, clippingOverlayBase,
            destinationGamutOverlay, destinationGamutOverlayBase,
            thumbnailBase, thumbnail
        )
    }

    private static func renderWorkingSamplerImage(_ image: CIImage, context: CIContext) -> CGImage? {
        context.createCGImage(
            image,
            from: image.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
    }

    private static func renderClippingOverlay(_ image: CIImage, context: CIContext) -> CGImage? {
        guard let overlay = ChannelClippingOverlay.makeOverlay(for: image) else { return nil }
        return context.createCGImage(
            overlay,
            from: overlay.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
    }

    static func renderUnproofedThumbnail(_ image: CIImage, context: CIContext) -> CGImage? {
        // 썸네일은 현상 프리뷰와 같은 표시 gamut 매핑을 거쳐야 확장범위 명부가 프리뷰와
        // 동일하게 접힌다(프리뷰는 하드 클립, 썸네일은 soft-clip 되는 불일치 방지). soft-proof 는
        // 걸지 않는다(썸네일은 항상 무프루프).
        let thumbnail = DisplayGamutMap.apply(to: displayProxy(image, maxDimension: thumbnailMaxDimension))
        return context.createCGImage(
            OutputDither.apply(to: thumbnail),
            from: thumbnail.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
    }

    private static func renderOverlay(
        _ image: CGImage,
        transform: ImageTransform,
        context: CIContext
    ) -> CGImage? {
        let transformed = ImageTransformStage.apply(
            to: CIImage(cgImage: image),
            transform: transform
        )
        return context.createCGImage(
            transformed,
            from: transformed.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
    }

    static func renderDisplayCGImage(
        _ image: CIImage,
        context: CIContext,
        softProof: SoftProofSettings,
        developTarget: DevelopTarget
    ) -> CGImage? {
        let effectiveSoftProof = displaySoftProofSettings(
            softProof,
            developTarget: developTarget
        )
        // 작업 이미지는 확장범위 값을 보존하므로, 출력 경계에서 hue-safe soft-clip 으로 [0,1] 로
        // 접은 뒤 soft-proof 를 건다(soft-proof 는 [0,1] 입력만 종이 gamut 으로 압축).
        let displayReferred = DisplayGamutMap.apply(to: image)
        let proofed = SoftProof.apply(to: displayReferred, using: effectiveSoftProof)
        let colorSpace = effectiveSoftProof.isEnabled
            ? SoftProof.proofColorSpace(for: effectiveSoftProof)
            : CGColorSpace(name: CGColorSpace.sRGB)!
        return context.createCGImage(
            OutputDither.apply(to: proofed),
            from: proofed.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }

    static func displaySoftProofSettings(
        _ settings: SoftProofSettings,
        developTarget: DevelopTarget
    ) -> SoftProofSettings {
        guard settings.isEnabled,
              developTarget == .print,
              settings.printerOutputICCProfileData != nil else { return settings }
        var effective = settings
        effective.iccProfileData = settings.printerOutputICCProfileData
        return effective
    }

    static func renderDebugPreviews(
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

    static func renderRawPreview(
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


}
