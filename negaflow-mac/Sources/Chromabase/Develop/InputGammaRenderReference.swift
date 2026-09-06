import Foundation
import CoreImage

/// 수동 입력 감마의 밀도 변화를 장면 자동 정규화가 다시 지우지 않도록 기준 범위를 고정합니다.
/// 원본의 기본 해석에서 한 번 측정한 작은 수치만 보관하며 현상 픽셀은 보관하지 않습니다.
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
