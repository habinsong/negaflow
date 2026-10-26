import Foundation
import CoreImage

/// MAIN/PRINT uses fixed density units. Explicit scene-adaptive targets freeze the
/// reference measured with the original transfer so manual gamma is not cancelled.
public enum InputGammaRenderReference {
    private struct Key: Hashable {
        let url: URL
        let observation: InputGammaFileObservation
        let filmType: FilmType
        let stock: String?
        let light: String?
    }
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var values: [Key: SIMD3<Double>] = [:]
    }
    private static let cache = Cache()

    public static func prepare(
        source: URL, params: DevelopParameters, measurements: inout DevelopSceneMeasurements
    ) throws {
        guard params.inputGamma != .automatic, params.filmType.requiresInversion else { return }
        if !params.developTarget.isScannerEmulation {
            let preset = params.baseEstimationMode == .preset
                ? params.filmStockDminID.flatMap(FilmStockDminRegistry.find) : nil
            measurements.inputGammaReferenceRange = NegativeLinearResponse.stats(
                base: FilmBase(rgb: SIMD3(repeating: 1), source: .manual),
                preset: preset, filmType: params.filmType).dmaxNorm
            return
        }
        let key = Key(url: source.standardizedFileURL, observation: try InputGammaFileObservation.read(source),
            filmType: params.filmType,
            stock: params.baseEstimationMode == .preset ? params.filmStockDminID : nil,
            light: params.baseEstimationMode == .preset ? params.lightSourceProfileID : nil)
        if let value = cache.lock.withLock({ cache.values[key] }) {
            measurements.inputGammaReferenceRange = value
            return
        }
        // 잠금 밖에서 디코드합니다. 다른 파일의 프리뷰가 출력 측정을 기다리지 않습니다.
        let range = try measure(source, params: params)
        guard try InputGammaFileObservation.read(source) == key.observation else {
            throw InputGammaDecodeError.decodeFailed
        }
        cache.lock.withLock {
            if cache.values.count >= 64 { cache.values.removeAll(keepingCapacity: true) }
            cache.values[key] = range
        }
        measurements.inputGammaReferenceRange = range
    }

    private static func measure(_ source: URL, params: DevelopParameters) throws -> SIMD3<Double> {
        try autoreleasepool {
            let image: CIImage
            if let preview = try ImageLoader.loadImportedPreview(source, maxDimension: 640,
                highResolutionThreshold: 0, inputGamma: .automatic) {
                image = preview.image
            } else { image = try ImageLoader.loadImportedDecoded(source, inputGamma: .automatic).image }
            let engine = ChromabaseEngine()
            let mode: DevelopParameters.BaseMode = params.baseEstimationMode == .preset ? .preset : .auto
            let stock = mode == .preset ? params.filmStockDminID.flatMap(FilmStockDminRegistry.find) : nil
            var referenceParams = params
            referenceParams.baseEstimationMode = mode
            referenceParams.manualBaseRGB = nil
            let base = engine.resolveFilmBase(for: image, provided: nil, preset: stock, params: referenceParams)
            if let stock {
                return NegativeInversion.presetStats(for: image, base: base, preset: stock,
                    filmType: params.filmType).dmaxNorm
            }
            return (NegativeInversion.sampleStats(image, base: base, filmType: params.filmType)
                ?? NegativeInversion.genericStats(base: base, filmType: params.filmType)).dmaxNorm
        }
    }
}
