import CoreImage
import Foundation

/// The 412bb31 scene-range response, exposed by the visible Auto Balance switch.
/// This is a scene-dependent rendering choice, not measured film calibration.
enum NegativeAutoBalance {
    static func supports(_ target: DevelopTarget) -> Bool {
        target == .main || target == .print || target.isCustom
    }

    static func invert(_ input: CIImage, base: FilmBase, preset: FilmStockDmin?,
                       params: DevelopParameters, measurements: inout DevelopSceneMeasurements) -> CIImage {
        var stats: NegativeInversion.ChannelStats
        if let cached = measurements.inversionStats { stats = cached }
        else {
            stats = params.autoBalance
                ? NegativeInversion.sampleStats(input, base: base, filmType: params.filmType,
                    region: measurements.analysisRegion, densityLimit: 1.8)
                    ?? NegativeInversion.genericStats(base: base, filmType: params.filmType)
                : NegativeInversion.genericStats(base: base, filmType: params.filmType)
            if params.filmType != .bwNegative, let preset { stats.dmaxNorm *= preset.relativeRangeFactor }
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
