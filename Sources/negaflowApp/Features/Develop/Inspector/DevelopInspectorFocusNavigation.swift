enum DevelopInspectorFocusNavigation {
    static func visibleSliderOrder(
        expandedPanel: InspectorPanel?,
        showNoiseReductionStrength: Bool
    ) -> [InspectorSliderFocus] {
        switch expandedPanel {
        case .tone:
            return [.exposure, .contrast, .highlight, .shadow, .whites, .blacks, .density]
        case .curve:
            return [.curveHighlights, .curveLights, .curveDarks, .curveShadows]
        case .color:
            return [.warmth, .tint, .vibrance, .saturation, .colorDepth]
        case .detail:
            var ids: [InspectorSliderFocus] = []
            if showNoiseReductionStrength {
                ids.append(contentsOf: [
                    .noiseReduction, .noiseReductionLuma, .noiseReductionChroma,
                    .noiseReductionDarkTone, .noiseReductionDetail, .noiseReductionGrainProtect,
                ])
            }
            ids.append(contentsOf: [.grain, .sharpness, .clarity, .halation, .vignette])
            return ids
        case .calibration, .bwToning, .colorMixer, .colorGrading, .debug, nil:
            return []
        }
    }

    static func nextFocusedSlider(
        current: InspectorSliderFocus?,
        order: [InspectorSliderFocus],
        reverse: Bool
    ) -> InspectorSliderFocus? {
        guard let current, let index = order.firstIndex(of: current), !order.isEmpty else {
            return nil
        }
        let offset = reverse ? -1 : 1
        let next = (index + offset + order.count) % order.count
        return order[next]
    }
}
