import CoreImage
import Chromabase

extension DevelopFrameRenderer {
    /// 중립 스포이드: 찍은 점(변형 전 정규 좌표, y-down)의 화이트밸런스 입력값. 화면 현상과 같은
    /// 입력·베이스·장면 측정·프록시를 써서 사용자가 본 화면과 같은 기준에서 잰다.
    static func whiteBalanceInputSample(
        _ snapshot: DevelopFrameSnapshot,
        atBaseUnit point: CGPoint
    ) throws -> SIMD3<Double>? {
        try autoreleasepool {
            let engine = ChromabaseEngine()
            guard let input = try resolveRenderInput(snapshot, engine: engine, context: renderContext()) else {
                throw loadError(for: snapshot)
            }
            let rawInput = input.image
            let analysisRegion = AnalysisRegion(transform: snapshot.imageTransform,
                                                imageSize: rawInput.extent.size)
            let base = developBase(for: snapshot, input: rawInput, engine: engine,
                                   analysisRegion: analysisRegion)
            var measurements = snapshot.cachedSceneMeasurements
            measurements.analysisRegion = analysisRegion
            var inputParams = snapshot.params
            inputParams.filmType = snapshot.filmType
            try NativeCameraRAW.prepare(source: snapshot.rawScanURL,
                params: inputParams, measurements: &measurements)
            try InputGammaRenderReference.prepare(source: snapshot.rawScanURL,
                params: inputParams, measurements: &measurements)
            var params = snapshot.preset.map {
                DevelopParameters(preset: $0, overrides: snapshot.params)
            } ?? snapshot.params
            params.filmType = snapshot.filmType
            params.developTarget = snapshot.params.developTarget
            params.imageTransform = .identity
            let reference = engine.developWhiteBalanceInputPreview(
                image: rawInput,
                base: base,
                params: params,
                maxDimension: snapshot.proxyMaxDimension,
                measurements: &measurements
            )
            return NeutralWhiteBalancePicker.sample(reference, atUnit: point)
        }
    }
}
