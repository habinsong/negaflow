import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit
import Metal

extension DevelopFrameRenderer {
    static func render(_ snapshot: DevelopFrameSnapshot) throws -> DevelopFrameRenderResult {
        // 한 번의 현상에서 만든 중간 CIImage/IOSurface 버퍼를 패스 종료 시 즉시 반환(Apple 권장:
        // 반복 createCGImage 루프는 autoreleasepool 로 감싸 메모리 급증을 막는다).
        return try autoreleasepool {
            try Task.checkCancellation()
            if snapshot.isInputGammaPreview, let source = snapshot.inputGammaPreviewSource,
               !source.matches(snapshot.rawScanURL) { throw DevelopFrameRenderError.loadFailed }
            let engine = ChromabaseEngine()
            let context = renderContext()
            guard let input = try resolveRenderInput(snapshot, engine: engine, context: context) else {
                throw loadError(for: snapshot)
            }
            try Task.checkCancellation()
            let rawInput = input.image
            // 크롭한 사진 영역 — 장면 측정은 그 안에서, 베이스는 그 바깥 띠에서 찾는다.
            let analysisRegion = AnalysisRegion(transform: snapshot.imageTransform,
                                                imageSize: rawInput.extent.size)
            let base = developBase(for: snapshot, input: rawInput, engine: engine,
                                   analysisRegion: analysisRegion)
            let rangeShapeAttempted = snapshot.needsRangeShape && snapshot.filmType == .colorNegative
                && base != nil
            let rangeShape = rangeShapeAttempted
                ? base.flatMap { ChannelRangeCalibration.measure(in: rawInput, base: $0, region: analysisRegion) }
                : nil
            var measurements = snapshot.cachedSceneMeasurements
            measurements.analysisRegion = analysisRegion
            var inputParams = snapshot.params
            inputParams.filmType = snapshot.filmType
            try NativeCameraRAW.prepare(source: snapshot.rawScanURL,
                params: inputParams, measurements: &measurements)
            try InputGammaRenderReference.prepare(source: snapshot.rawScanURL,
                params: inputParams, measurements: &measurements)
            let rawPair = snapshot.needsRawPreview
                ? try renderRawPreview(
                    from: displayProxy(measurements.cameraToWorking?.apply(to: rawInput) ?? rawInput,
                                       maxDimension: snapshot.proxyMaxDimension),
                    transform: snapshot.imageTransform,
                    context: context
                )
                : nil
            try Task.checkCancellation()
            // MAIN 비교본과 스캐너 타깃은 반전 도메인이 다르다. 선택한 타깃의 측정만
            // 캐시에 돌려주고 비교본이 그 통계를 덮어쓰지 않게 한다.
            let developedPair = try renderDeveloped(
                input: rawInput,
                base: base,
                snapshot: snapshot,
                engine: engine,
                context: context,
                measurements: &measurements
            )
            try Task.checkCancellation()
            var comparisonMeasurements = DevelopSceneMeasurements()
            comparisonMeasurements.analysisRegion = analysisRegion
            var comparisonParams = inputParams
            comparisonParams.developTarget = .main
            comparisonParams.scannerProfileID = nil
            try NativeCameraRAW.prepare(source: snapshot.rawScanURL,
                params: comparisonParams, measurements: &comparisonMeasurements)
            try InputGammaRenderReference.prepare(source: snapshot.rawScanURL,
                params: comparisonParams, measurements: &comparisonMeasurements)
            let neutralPair = snapshot.needsNeutralPreview
                ? try renderNeutralPreview(
                    input: rawInput,
                    base: base,
                    snapshot: snapshot,
                    engine: engine,
                    context: context,
                    measurements: &comparisonMeasurements
                )
                : nil
            let mainPair = snapshot.needsMainPreview
                ? try renderMainPreview(
                    input: rawInput,
                    base: base,
                    snapshot: snapshot,
                    engine: engine,
                    context: context,
                    measurements: &comparisonMeasurements
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
            try Task.checkCancellation()
            if snapshot.isInputGammaPreview, let source = snapshot.inputGammaPreviewSource,
               !source.matches(snapshot.rawScanURL) { throw DevelopFrameRenderError.loadFailed }
            return DevelopFrameRenderResult(
                base: base,
                rawPreview: rawPair?.transformed,
                rawBase: rawPair?.base,
                neutralPreview: neutralPair?.transformed,
                neutralBase: neutralPair?.base,
                mainPreview: mainPair?.transformed,
                mainBase: mainPair?.base,
                developed: developedPair.transformed,
                developedBase: developedPair.base,
                workingBase: developedPair.workingBase,
                clippingOverlay: developedPair.clippingOverlay,
                clippingOverlayBase: developedPair.clippingOverlayBase,
                destinationGamutOverlay: developedPair.destinationGamutOverlay,
                destinationGamutOverlayBase: developedPair.destinationGamutOverlayBase,
                thumbnailBase: developedPair.thumbnailBase,
                thumbnail: developedPair.thumbnail,
                debugPreviews: debugPreviews,
                previewRaw: input.generatedPreviewRaw,
                sceneMeasurements: measurements,
                rangeShape: rangeShape,
                rangeShapeAttempted: rangeShapeAttempted
            )
        }
    }

    /// 반전 기준 베이스 — 캐시가 있으면 그대로, 없으면 크롭 바깥 띠에서 잰다. 포지티브는 nil.
    static func developBase(
        for snapshot: DevelopFrameSnapshot,
        input rawInput: CIImage,
        engine: ChromabaseEngine,
        analysisRegion: AnalysisRegion?
    ) -> FilmBase? {
        guard snapshot.filmType.requiresInversion else { return nil }
        return snapshot.cachedBase ?? engine.estimateFilmBase(
            in: rawInput,
            mode: snapshot.params.baseEstimationMode,
            manual: snapshot.params.manualBaseRGB,
            filmStockDminID: snapshot.params.filmStockDminID,
            lightSourceProfileID: snapshot.params.lightSourceProfileID,
            filmType: snapshot.filmType,
            analysisRegion: analysisRegion
        )
    }

    static func renderFastPreview(_ snapshot: DevelopFrameSnapshot) throws -> DevelopFrameFastPreviewResult {
        return try autoreleasepool {
            let engine = ChromabaseEngine()
            let context = renderContext()
            guard let input = try resolveRenderInput(snapshot, engine: engine, context: context) else {
                throw loadError(for: snapshot)
            }
            var effectiveParams = snapshot.preset.map {
                DevelopParameters(preset: $0, overrides: snapshot.params)
            } ?? snapshot.params
            effectiveParams.filmType = snapshot.filmType
            effectiveParams.developTarget = snapshot.params.developTarget
            effectiveParams.imageTransform = .identity
            var measurements = DevelopSceneMeasurements()
            measurements.analysisRegion = AnalysisRegion(transform: snapshot.imageTransform,
                                                         imageSize: input.image.extent.size)
            try NativeCameraRAW.prepare(source: snapshot.rawScanURL,
                params: effectiveParams, measurements: &measurements)
            try InputGammaRenderReference.prepare(source: snapshot.rawScanURL,
                params: effectiveParams, measurements: &measurements)
            let baseImage = engine.developScannerPreview(
                image: input.image,
                base: snapshot.cachedBase,
                params: effectiveParams,
                maxDimension: snapshot.proxyMaxDimension,
                measurements: &measurements
            )
            let previewImage = snapshot.imageTransform.isIdentity
                ? baseImage
                : ImageTransformStage.apply(to: baseImage, transform: snapshot.imageTransform)
            guard let previewCG = renderDisplayCGImage(
                previewImage,
                context: context,
                softProof: snapshot.softProof,
                developTarget: snapshot.params.developTarget
            ) else {
                throw DevelopFrameRenderError.developedFailed
            }
            let thumbnailImage = snapshot.needsThumbnail
                ? renderUnproofedThumbnail(previewImage, context: context)
                : nil
            return DevelopFrameFastPreviewResult(
                preview: previewCG,
                thumbnail: thumbnailImage,
                previewRaw: input.generatedPreviewRaw
            )
        }
    }

    /// 무보정 현상본: Target=main, 스캐너 프로파일 없음, 프리셋/인스펙터 조정 전부 기본값.
    /// base/film/transform 만 사용자 설정을 따른다(반전 기준은 동일해야 Before/After가 정합).
    private static func renderNeutralPreview(
        input: CIImage,
        base: FilmBase?,
        snapshot: DevelopFrameSnapshot,
        engine: ChromabaseEngine,
        context: CIContext,
        measurements: inout DevelopSceneMeasurements
    ) throws -> (transformed: CGImage, base: CGImage) {
        var neutral = DevelopParameters()
        neutral.filmType = snapshot.filmType
        neutral.developTarget = .main
        neutral.baseEstimationMode = snapshot.params.baseEstimationMode
        neutral.autoBalance = snapshot.params.autoBalance
        neutral.baseScale = snapshot.params.baseScale
        neutral.inputGamma = snapshot.params.inputGamma
        neutral.manualBaseRGB = snapshot.params.manualBaseRGB
        neutral.filmStockDminID = snapshot.params.filmStockDminID
        neutral.lightSourceProfileID = snapshot.params.lightSourceProfileID
        // 반전 기준이다 — 빠지면 자동 밸런스를 끈 프레임에서 Before 만 교정 전 색으로 나온다.
        neutral.channelRange = snapshot.params.channelRange
        neutral.scannerProfileID = nil
        neutral.imageTransform = .identity
        let baseImage = engine.developScannerPreview(
            image: input,
            base: base,
            params: neutral,
            maxDimension: snapshot.proxyMaxDimension,
            measurements: &measurements
        )
        guard let baseCG = renderDisplayCGImage(
            baseImage,
            context: context,
            softProof: snapshot.softProof,
            developTarget: snapshot.params.developTarget
        ) else {
            throw DevelopFrameRenderError.developedFailed
        }
        if snapshot.imageTransform.isIdentity {
            return (baseCG, baseCG)
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
        return (transformedCG, baseCG)
    }

    /// 현재 조정과 프로파일은 유지하고 출력 타깃만 MAIN으로 바꾼 비교본.
    private static func renderMainPreview(
        input: CIImage,
        base: FilmBase?,
        snapshot: DevelopFrameSnapshot,
        engine: ChromabaseEngine,
        context: CIContext,
        measurements: inout DevelopSceneMeasurements
    ) throws -> (transformed: CGImage, base: CGImage) {
        var main = snapshot.preset.map {
            DevelopParameters(preset: $0, overrides: snapshot.params)
        } ?? snapshot.params
        main.filmType = snapshot.filmType
        main.developTarget = .main
        main.imageTransform = .identity
        let baseImage = engine.developScannerPreview(
            image: input,
            base: base,
            params: main,
            maxDimension: snapshot.proxyMaxDimension,
            measurements: &measurements
        )
        guard let baseCG = renderDisplayCGImage(
            baseImage,
            context: context,
            softProof: .disabled,
            developTarget: .main
        ) else {
            throw DevelopFrameRenderError.developedFailed
        }
        if snapshot.imageTransform.isIdentity {
            return (baseCG, baseCG)
        }
        let transformedImage = ImageTransformStage.apply(to: baseImage, transform: snapshot.imageTransform)
        guard let transformedCG = renderDisplayCGImage(
            transformedImage,
            context: context,
            softProof: .disabled,
            developTarget: .main
        ) else {
            throw DevelopFrameRenderError.developedFailed
        }
        return (transformedCG, baseCG)
    }


}
