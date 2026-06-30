import Foundation

public struct DevelopSettingsPasteScope: Codable, Sendable, Equatable {
    public var base: Bool
    public var tone: Bool
    public var color: Bool
    public var detail: Bool

    public init(base: Bool = true, tone: Bool = true, color: Bool = true, detail: Bool = true) {
        self.base = base
        self.tone = tone
        self.color = color
        self.detail = detail
    }

    public static let all = DevelopSettingsPasteScope()

    public var isEmpty: Bool {
        !base && !tone && !color && !detail
    }

    public var isFullDevelopScope: Bool {
        base && tone && color && detail
    }

    public var displayName: String {
        guard !isFullDevelopScope else { return "All" }
        var groups: [String] = []
        if base { groups.append("Base") }
        if tone { groups.append("Tone") }
        if color { groups.append("Color") }
        if detail { groups.append("Detail") }
        return groups.isEmpty ? "None" : groups.joined(separator: "/")
    }

    public func applying(source: DevelopParameters, to destination: DevelopParameters) -> DevelopParameters {
        var next = destination

        if base {
            next.filmType = source.filmType
            next.developTarget = source.developTarget
            next.scannerProfileID = source.scannerProfileID
            next.baseEstimationMode = source.baseEstimationMode
            next.manualBaseRGB = source.manualBaseRGB
            next.filmStockDminID = source.filmStockDminID
        }

        if tone {
            next.exposure = source.exposure
            next.contrast = source.contrast
            next.density = source.density
            next.highlight = source.highlight
            next.shadow = source.shadow
            next.whites = source.whites
            next.blacks = source.blacks
            next.curveHighlights = source.curveHighlights
            next.curveLights = source.curveLights
            next.curveDarks = source.curveDarks
            next.curveShadows = source.curveShadows
            next.pointCurves = source.pointCurves
        }

        if color {
            next.warmth = source.warmth
            next.tint = source.tint
            next.colorDepth = source.colorDepth
            next.vibrance = source.vibrance
            next.saturation = source.saturation
            next.redPrimary = source.redPrimary
            next.greenPrimary = source.greenPrimary
            next.bluePrimary = source.bluePrimary
            next.colorMixer = source.colorMixer
            next.colorGrading = source.colorGrading
            next.calibration = source.calibration
        }

        if detail {
            next.grain = source.grain
            next.sharpness = source.sharpness
            next.halation = source.halation
            next.clarity = source.clarity
            next.vignette = source.vignette
            next.defectRemoval = source.defectRemoval
            next.noiseReduction = source.noiseReduction
        }

        next.imageTransform = destination.imageTransform
        return next
    }
}
