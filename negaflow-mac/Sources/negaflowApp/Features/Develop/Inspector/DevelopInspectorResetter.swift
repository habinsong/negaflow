import Chromabase

enum DevelopInspectorResetter {
    @discardableResult
    @MainActor
    static func reset(_ panel: InspectorPanel, frame: ScanFrame, neutralPreset: LookPreset?) -> Bool {
        let defaults = DevelopParameters()
        frame.updateParams { params in
            switch panel {
            case .tone:
                frame.preset = neutralPreset
                params.exposure = defaults.exposure
                params.contrast = defaults.contrast
                params.highlight = defaults.highlight
                params.shadow = defaults.shadow
                params.whites = defaults.whites
                params.blacks = defaults.blacks
                params.density = defaults.density
            case .curve:
                params.curveHighlights = defaults.curveHighlights
                params.curveLights = defaults.curveLights
                params.curveDarks = defaults.curveDarks
                params.curveShadows = defaults.curveShadows
                params.pointCurves = defaults.pointCurves
            case .color:
                params.warmth = defaults.warmth
                params.tint = defaults.tint
                params.vibrance = defaults.vibrance
                params.saturation = defaults.saturation
                params.colorDepth = defaults.colorDepth
            case .colorMixer:
                params.colorMixer = defaults.colorMixer
            case .colorGrading:
                params.colorGrading = defaults.colorGrading
            case .bwToning:
                params.bwToning = defaults.bwToning
            case .calibration:
                params.redPrimary = defaults.redPrimary
                params.greenPrimary = defaults.greenPrimary
                params.bluePrimary = defaults.bluePrimary
                params.calibration = defaults.calibration
            case .detail:
                params.noiseReduction = defaults.noiseReduction
                params.noiseReductionLuma = defaults.noiseReductionLuma
                params.noiseReductionChroma = defaults.noiseReductionChroma
                params.noiseReductionDarkTone = defaults.noiseReductionDarkTone
                params.noiseReductionDetail = defaults.noiseReductionDetail
                params.noiseReductionGrainProtect = defaults.noiseReductionGrainProtect
                params.grain = defaults.grain
                params.sharpness = defaults.sharpness
                params.clarity = defaults.clarity
                params.halation = defaults.halation
                params.vignette = defaults.vignette
            case .debug:
                break
            }
        }
        return panel == .color
    }

    @MainActor
    static func resetAllAdjustments(frame: ScanFrame, neutralPreset: LookPreset?) {
        let defaults = DevelopParameters()
        frame.preset = neutralPreset
        frame.updateParams { params in
            params.exposure = defaults.exposure
            params.contrast = defaults.contrast
            params.density = defaults.density
            params.highlight = defaults.highlight
            params.shadow = defaults.shadow
            params.whites = defaults.whites
            params.blacks = defaults.blacks
            params.curveHighlights = defaults.curveHighlights
            params.curveLights = defaults.curveLights
            params.curveDarks = defaults.curveDarks
            params.curveShadows = defaults.curveShadows
            params.pointCurves = defaults.pointCurves
            params.warmth = defaults.warmth
            params.tint = defaults.tint
            params.vibrance = defaults.vibrance
            params.saturation = defaults.saturation
            params.colorDepth = defaults.colorDepth
            params.redPrimary = defaults.redPrimary
            params.greenPrimary = defaults.greenPrimary
            params.bluePrimary = defaults.bluePrimary
            params.colorMixer = defaults.colorMixer
            params.colorGrading = defaults.colorGrading
            params.calibration = defaults.calibration
            params.bwToning = defaults.bwToning
            params.localDodgeBurn = defaults.localDodgeBurn
            params.grain = defaults.grain
            params.sharpness = defaults.sharpness
            params.clarity = defaults.clarity
            params.halation = defaults.halation
            params.vignette = defaults.vignette
            params.noiseReduction = defaults.noiseReduction
            params.noiseReductionLuma = defaults.noiseReductionLuma
            params.noiseReductionChroma = defaults.noiseReductionChroma
            params.noiseReductionDarkTone = defaults.noiseReductionDarkTone
            params.noiseReductionDetail = defaults.noiseReductionDetail
            params.noiseReductionGrainProtect = defaults.noiseReductionGrainProtect
        }
    }
}
