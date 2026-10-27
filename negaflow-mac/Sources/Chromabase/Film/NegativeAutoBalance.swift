import CoreImage
import Foundation

public extension DevelopTarget {
    /// 자동 밸런스 스위치가 반전 범위를 정하는 타깃(MAIN 계열의 MAIN·PRINT, 그리고 커스텀).
    /// 화면은 이 값과 필름이 네거티브인지로 스위치를 보일지 정한다. 엔진도 같은 규칙을 쓴다.
    var supportsAutoBalance: Bool { NegativeAutoBalance.supports(self) }
}

/// The 412bb31 scene-range response, exposed by the visible Auto Balance switch.
/// This is a scene-dependent rendering choice, not measured film calibration.
enum NegativeAutoBalance {
    static func supports(_ target: DevelopTarget) -> Bool {
        target == .main || target == .print || target.isCustom
    }

    /// 장면을 읽지 않는 고정 범위: 명목 범위 × 필름 상대 계수 × 장치·필름 채널 교정.
    /// 채널 교정(`channelRange`)은 컬러에만 쓴다 — 흑백은 세 채널을 한 곡선으로 본다.
    static func fixedStats(base: FilmBase, preset: FilmStockDmin?,
                           params: DevelopParameters) -> NegativeInversion.ChannelStats {
        var stats = NegativeInversion.genericStats(base: base, filmType: params.filmType)
        guard params.filmType != .bwNegative else { return stats }
        if let preset { stats.dmaxNorm *= preset.relativeRangeFactor }
        if let calibration = params.channelRange { stats.dmaxNorm *= calibration }
        return stats
    }

    static func invert(_ input: CIImage, base: FilmBase, preset: FilmStockDmin?,
                       params: DevelopParameters, measurements: inout DevelopSceneMeasurements) -> CIImage {
        var stats: NegativeInversion.ChannelStats
        if let cached = measurements.inversionStats { stats = cached }
        else {
            if params.autoBalance, let measured = NegativeInversion.sampleStats(
                input, base: base, filmType: params.filmType,
                region: measurements.analysisRegion, densityLimit: 1.8) {
                stats = measured
                if params.filmType != .bwNegative, let preset { stats.dmaxNorm *= preset.relativeRangeFactor }
            } else {
                stats = fixedStats(base: base, preset: preset, params: params)
            }
            measurements.inversionStats = stats
        }
        let inverted = NegativeInversion.applyDensityEncoding(to: input, stats: stats,
            response: NegativeInversion.response(for: params.filmType))
        guard params.autoBalance else { return inverted }
        return NegativeInversion.applyMutedSceneVibrance(to: inverted,
            monochrome: params.filmType == .bwNegative, region: measurements.analysisRegion,
            amount: &measurements.mutedVibranceAmount)
    }
}
