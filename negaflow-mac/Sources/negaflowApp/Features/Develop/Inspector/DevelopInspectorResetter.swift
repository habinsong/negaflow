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
        // 크롭·수평 각도도 보정이다(라이트룸 초기화와 같다) — 남겨 두면 초기화 뒤에도 크롭 바깥 띠로
        // 베이스를 재는 등 결과가 초기 상태와 달랐다(2026-10-15 사용자 지적). 90° 회전·뒤집기는 필름을
        // 홀더에 넣은 방향이라 그대로 둔다.
        frame.updateTransform {
            $0.cropRect = nil
            $0.cropAspect = nil
            $0.straightenAngle = 0
        }
        frame.updateParams { params in
            params.baseScale = .identity
            if params.inputGamma != .automatic {
                params.manualBaseRGB = nil
                if params.baseEstimationMode == .manual { params.baseEstimationMode = .auto }
            }
            params.inputGamma = .automatic
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
