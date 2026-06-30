import Chromabase

struct BatchWBSettings {
    let filmType: FilmType
    let developTarget: DevelopTarget
    let baseEstimationMode: DevelopParameters.BaseMode
    let manualBaseRGB: SIMD3<Double>?
    let filmStockDminID: String?
    let scannerProfileID: String?
    let warmth: Double
    let tint: Double
}

extension ScanFrame {
    var batchWBSettings: BatchWBSettings {
        BatchWBSettings(
            filmType: filmType,
            developTarget: params.developTarget,
            baseEstimationMode: params.baseEstimationMode,
            manualBaseRGB: params.baseEstimationMode == .manual ? params.manualBaseRGB : nil,
            filmStockDminID: params.baseEstimationMode == .preset ? params.filmStockDminID : nil,
            scannerProfileID: params.scannerProfileID,
            warmth: params.warmth,
            tint: params.tint
        )
    }

    func applyBatchWBSettings(_ settings: BatchWBSettings) {
        filmType = settings.filmType
        updateParams {
            $0.filmType = settings.filmType
            $0.developTarget = settings.developTarget
            $0.baseEstimationMode = settings.baseEstimationMode
            $0.manualBaseRGB = settings.manualBaseRGB
            $0.filmStockDminID = settings.filmStockDminID
            $0.scannerProfileID = settings.scannerProfileID
            $0.warmth = settings.warmth
            $0.tint = settings.tint
        }
    }
}

extension AppModel {
    func syncBatchWB(from source: ScanFrame) {
        let targets = frames.filter { $0.id != source.id }
        guard !targets.isEmpty else {
            statusMessage = "동기화할 프레임 없음"
            return
        }

        let settings = source.batchWBSettings
        for target in targets {
            target.applyBatchWBSettings(settings)
            Task { await developFrame(target) }
        }
        statusMessage = "WB 동기화 완료: \(targets.count)프레임"
    }
}
