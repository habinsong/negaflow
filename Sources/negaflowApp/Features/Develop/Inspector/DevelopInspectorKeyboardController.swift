import Chromabase

enum DevelopInspectorKeyboardController {
    @discardableResult
    @MainActor
    static func nudge(
        _ slider: InspectorSliderFocus,
        frame: ScanFrame,
        direction: DevelopKeyboardNudge.Direction,
        coarse: Bool
    ) -> Bool {
        switch slider {
        case .exposure:
            nudgeParam(\.exposure, range: DevelopToneRange.exposure, frame: frame, direction: direction, coarse: coarse)
        case .contrast:
            nudgeParam(\.contrast, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .highlight:
            nudgeParam(\.highlight, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .shadow:
            nudgeParam(\.shadow, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .whites:
            nudgeParam(\.whites, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .blacks:
            nudgeParam(\.blacks, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .density:
            nudgeParam(\.density, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .curveHighlights:
            nudgeParam(\.curveHighlights, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .curveLights:
            nudgeParam(\.curveLights, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .curveDarks:
            nudgeParam(\.curveDarks, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .curveShadows:
            nudgeParam(\.curveShadows, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .warmth:
            nudgeParam(\.warmth, range: -1...1, frame: frame, direction: direction, coarse: coarse)
            return true
        case .tint:
            nudgeParam(\.tint, range: -1...1, frame: frame, direction: direction, coarse: coarse)
            return true
        case .vibrance:
            nudgeParam(\.vibrance, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .saturation:
            nudgeParam(\.saturation, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .colorDepth:
            nudgeParam(\.colorDepth, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .redPrimary:
            nudgeParam(\.redPrimary, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .greenPrimary:
            nudgeParam(\.greenPrimary, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .bluePrimary:
            nudgeParam(\.bluePrimary, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .noiseReduction:
            nudgeParam(\.noiseReduction, range: 0.05...1, frame: frame, direction: direction, coarse: coarse)
        case .noiseReductionLuma:
            nudgeParam(\.noiseReductionLuma, range: 0...1, frame: frame, direction: direction, coarse: coarse)
        case .noiseReductionChroma:
            nudgeParam(\.noiseReductionChroma, range: 0...1, frame: frame, direction: direction, coarse: coarse)
        case .noiseReductionDarkTone:
            nudgeParam(\.noiseReductionDarkTone, range: 0...1, frame: frame, direction: direction, coarse: coarse)
        case .noiseReductionDetail:
            nudgeParam(\.noiseReductionDetail, range: 0...1, frame: frame, direction: direction, coarse: coarse)
        case .noiseReductionGrainProtect:
            nudgeParam(\.noiseReductionGrainProtect, range: 0...1, frame: frame, direction: direction, coarse: coarse)
        case .grain:
            nudgeParam(\.grain, range: 0...1, frame: frame, direction: direction, coarse: coarse)
        case .sharpness:
            nudgeParam(\.sharpness, range: 0...1, frame: frame, direction: direction, coarse: coarse)
        case .clarity:
            nudgeParam(\.clarity, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        case .halation:
            nudgeParam(\.halation, range: 0...1, frame: frame, direction: direction, coarse: coarse)
        case .vignette:
            nudgeParam(\.vignette, range: -1...1, frame: frame, direction: direction, coarse: coarse)
        }
        return false
    }

    @MainActor
    private static func nudgeParam(
        _ keyPath: WritableKeyPath<DevelopParameters, Double>,
        range: ClosedRange<Double>,
        frame: ScanFrame,
        direction: DevelopKeyboardNudge.Direction,
        coarse: Bool
    ) {
        frame.updateParams {
            $0[keyPath: keyPath] = DevelopKeyboardNudge.adjustedValue(
                $0[keyPath: keyPath],
                range: range,
                direction: direction,
                coarse: coarse
            )
        }
    }
}
