import Foundation

public struct DevelopSettingsPasteScope: Codable, Sendable, Equatable {
    public var base: Bool
    public var tone: Bool
    public var color: Bool
    public var detail: Bool
    public var geometry: Bool
    public var inputGamma: Bool
    public var baseScale: Bool

    public init(
        base: Bool = true,
        tone: Bool = true,
        color: Bool = true,
        detail: Bool = true,
        geometry: Bool = true,
        inputGamma: Bool? = nil,
        baseScale: Bool? = nil
    ) {
        self.base = base
        self.tone = tone
        self.color = color
        self.detail = detail
        self.geometry = geometry
        // 기존 호출/저장값의 베이스 선택을 따르며, 새 UI에서는 독립적으로 선택합니다.
        self.inputGamma = inputGamma ?? base
        self.baseScale = baseScale ?? base
    }

    public static let all = DevelopSettingsPasteScope()

    public var isEmpty: Bool {
        !base && !tone && !color && !detail && !geometry && !inputGamma && !baseScale
    }

    public var isFullDevelopScope: Bool {
        base && tone && color && detail && geometry && inputGamma && baseScale
    }

    public var displayName: String {
        guard !isFullDevelopScope else { return "All" }
        var groups: [String] = []
        if inputGamma { groups.append("Input Gamma") }
        if baseScale { groups.append("Base Scale") }
        if base { groups.append("Base") }
        if tone { groups.append("Tone") }
        if color { groups.append("Color") }
        if detail { groups.append("Detail") }
        if geometry { groups.append("Geometry") }
        return groups.isEmpty ? "None" : groups.joined(separator: "/")
    }

    public func applying(source: DevelopParameters, to destination: DevelopParameters) -> DevelopParameters {
        var next = destination
        if inputGamma { next.inputGamma = source.inputGamma }
        if baseScale { next.baseScale = source.baseScale }

        if base {
            next.filmType = source.filmType
            next.isDigitalSource = source.isDigitalSource
            next.developTarget = source.developTarget
            next.scannerProfileID = source.scannerProfileID
            next.baseEstimationMode = source.baseEstimationMode
            next.manualBaseRGB = source.manualBaseRGB
            next.filmStockDminID = source.filmStockDminID
            next.lightSourceProfileID = source.lightSourceProfileID
            next.autoLevels = source.autoLevels
            next.autoNeutralBalance = source.autoNeutralBalance
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
            next.bwToning = source.bwToning
            next.filmEmulation = source.filmEmulation
            next.filmEmulationIntensity = source.filmEmulationIntensity
        }

        if detail {
            next.grain = source.grain
            next.sharpness = source.sharpness
            next.halation = source.halation
            next.clarity = source.clarity
            next.vignette = source.vignette
            next.defectRemoval = source.defectRemoval
            next.noiseReduction = source.noiseReduction
            next.noiseReductionLuma = source.noiseReductionLuma
            next.noiseReductionChroma = source.noiseReductionChroma
            next.noiseReductionDarkTone = source.noiseReductionDarkTone
            next.noiseReductionDetail = source.noiseReductionDetail
            next.noiseReductionGrainProtect = source.noiseReductionGrainProtect
            next.localDodgeBurn = source.localDodgeBurn
        }

        next.imageTransform = geometry ? source.imageTransform : destination.imageTransform
        return next
    }

    enum CodingKeys: String, CodingKey {
        case base, tone, color, detail, geometry, inputGamma, baseScale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        base = try container.decodeIfPresent(Bool.self, forKey: .base) ?? true
        tone = try container.decodeIfPresent(Bool.self, forKey: .tone) ?? true
        color = try container.decodeIfPresent(Bool.self, forKey: .color) ?? true
        detail = try container.decodeIfPresent(Bool.self, forKey: .detail) ?? true
        geometry = try container.decodeIfPresent(Bool.self, forKey: .geometry) ?? true
        inputGamma = try container.decodeIfPresent(Bool.self, forKey: .inputGamma) ?? base
        baseScale = try container.decodeIfPresent(Bool.self, forKey: .baseScale) ?? base
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(base, forKey: .base)
        try container.encode(tone, forKey: .tone)
        try container.encode(color, forKey: .color)
        try container.encode(detail, forKey: .detail)
        try container.encode(geometry, forKey: .geometry)
        try container.encode(inputGamma, forKey: .inputGamma)
        try container.encode(baseScale, forKey: .baseScale)
    }
}
