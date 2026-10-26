import CoreImage
import Foundation

/// Fixed sensitometric inversion for MAIN/PRINT. The generic gamma and gray density
/// are design references, not a measured characterization of a scanner or film roll.
enum NegativeLinearResponse {
    static let version = "fixed-density-linear-v6"
    static let shadowKnee = NegativeInversion.midGrayLinear / 4
    static let highlightKnee = 0.70

    static func applies(_ params: DevelopParameters) -> Bool {
        (params.developTarget == .main || params.developTarget == .print)
            && (params.scannerProfileID?.isEmpty ?? true)
    }

    static func stats(base: FilmBase, preset: FilmStockDmin?, filmType: FilmType)
        -> NegativeInversion.ChannelStats {
        var stats = NegativeInversion.genericStats(base: base, filmType: filmType)
        if filmType != .bwNegative, let preset {
            stats.dmaxNorm *= preset.relativeRangeFactor
        }
        return stats
    }

    // Join a film-density toe to the straight log-exposure portion with matching
    // value and derivative. D=0 is zero scene exposure, not a phantom 0.0194 grey.
    static let toeDensity = NegativeInversion.normalMidDensity
        + NegativeInversion.referenceFilmGamma * log10(shadowKnee / NegativeInversion.midGrayLinear)
    static let toePower = toeDensity * log(10) / NegativeInversion.referenceFilmGamma

    static func linearValue(density: Double) -> Double {
        if density < toeDensity {
            let magnitude = shadowKnee * pow(abs(density) / toeDensity, toePower)
            return density < 0 ? -magnitude : magnitude
        }
        return NegativeInversion.midGrayLinear * pow(10,
            (density - NegativeInversion.normalMidDensity) / NegativeInversion.referenceFilmGamma)
    }

    static func blackFloor(filmType: FilmType) -> Double {
        NegativeInversion.response(for: filmType).baseToe
    }

    /// The same scalar curve is applied to each channel after WB. Its middle is
    /// identity; the shoulder bounds each channel without coupling its low-signal
    /// inversion to the other channels' brightness. Highlight color ratios change.
    static func outputLuminance(_ y: Double, filmType: FilmType) -> Double {
        let black = blackFloor(filmType: filmType)
        guard y > 0 else { return black }
        if y < shadowKnee {
            let distance = 1 - y / shadowKnee
            return y + black * distance * distance
        }
        if y > highlightKnee {
            let room = 1 - highlightKnee
            return highlightKnee + room * ((y - highlightKnee) / (y - highlightKnee + room))
        }
        return y
    }

    /// Inverse of the output curve, so upstream corrections can target output values.
    static func inputLuminance(forOutput y: Double, filmType: FilmType) -> Double {
        guard y.isFinite, y >= 0, y < 1 else { return .nan }
        let black = blackFloor(filmType: filmType)
        guard y > black else { return 0 }
        if y < shadowKnee {
            let a = black / (shadowKnee * shadowKnee)
            let b = 1 - 2 * black / shadowKnee
            let distance = y - black
            return 2 * distance / (b + sqrt(b * b + 4 * a * distance))
        }
        if y > highlightKnee {
            return highlightKnee + (1 - highlightKnee) * (y - highlightKnee) / (1 - y)
        }
        return y
    }

    static func invert(_ image: CIImage, stats: NegativeInversion.ChannelStats,
                       filmType: FilmType) -> CIImage {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "negativeLinear") else { return image }
        let range = NegativeInversion.response(for: filmType).normalRange
        let scale = SIMD3(repeating: range / NegativeInversion.referenceFilmGamma) / stats.dmaxNorm
        return kernel.apply(extent: image.extent, arguments: [
            image, CIVector(x: stats.dmin.x, y: stats.dmin.y, z: stats.dmin.z),
            CIVector(x: scale.x, y: scale.y, z: scale.z),
            NegativeInversion.normalMidDensity / NegativeInversion.referenceFilmGamma,
            toeDensity / NegativeInversion.referenceFilmGamma, shadowKnee,
        ])?.cropped(to: image.extent) ?? image
    }

    static func output(_ image: CIImage, exposure: Double, filmType: FilmType) -> CIImage {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "negativeOutputTone") else { return image }
        let requestedGain = Float(pow(2, exposure))
        // Match ToneMapper's invalid-exposure no-op without dropping the output curve.
        let gain: Float = requestedGain.isFinite && requestedGain > 0 ? requestedGain : 1
        return kernel.apply(extent: image.extent, arguments: [
            image, gain, Float(shadowKnee), Float(highlightKnee),
            Float(blackFloor(filmType: filmType)),
        ])?.cropped(to: image.extent) ?? image
    }
}
