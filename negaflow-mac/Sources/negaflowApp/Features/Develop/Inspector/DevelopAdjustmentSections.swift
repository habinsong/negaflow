import SwiftUI
import Chromabase

struct DevelopAdjustmentSections: View {
    @EnvironmentObject private var model: AppModel

    let expandedPanel: InspectorPanel?
    let isBWToningAvailable: Bool
    let showNoiseReductionStrength: Bool
    let debugMetricsText: String?

    let debugOverlayEnabled: Binding<Bool>
    let debugOverlayStage: Binding<DevelopDebugStage>
    let focusedSlider: FocusState<InspectorSliderFocus?>.Binding
    let pointCurves: Binding<PointCurves>
    let colorMixer: Binding<ColorMixer>
    let colorGrading: Binding<ColorGrading>
    let bwToning: Binding<BWToning>
    let noiseReductionEnabled: Binding<Bool>

    let toneBinding: (WritableKeyPath<DevelopParameters, Double>) -> Binding<Double>
    let batchWBBinding: (WritableKeyPath<DevelopParameters, Double>) -> Binding<Double>
    let calibrationBinding: (WritableKeyPath<CalibrationAdjust, Double>) -> Binding<Double>
    let toggle: (InspectorPanel) -> Void
    let reset: (InspectorPanel) -> Void
    let onAdjustmentChange: () -> Void

    var body: some View {
        basicToneSection
        toneCurveSection
        colorSection
        colorMixerSection
        colorGradingSection
        if isBWToningAvailable {
            bwToningSection
        }
        calibrationSection
        detailSection
            if model.developerMode {
                debugSection
            }
    }

    private var basicToneSection: some View {
        WorkflowSection(
            title: model.text(AppLocalizedPhrase.basicTone),
            systemImage: "slider.horizontal.3",
            isExpanded: expandedPanel == .tone,
            toggle: { toggle(.tone) },
            reset: { reset(.tone) }
        ) {
            InspectorSlider(model.text(AppLocalizedPhrase.exposure), value: toneBinding(\.exposure), range: DevelopToneRange.exposure, focusID: .exposure, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.contrast), value: toneBinding(\.contrast), range: -1...1, focusID: .contrast, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.toneHighlights), value: toneBinding(\.highlight), range: -1...1, focusID: .highlight, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.shadows), value: toneBinding(\.shadow), range: -1...1, focusID: .shadow, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.whites), value: toneBinding(\.whites), range: DevelopToneRange.whites, focusID: .whites, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.blacks), value: toneBinding(\.blacks), range: DevelopToneRange.blacks, focusID: .blacks, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.density), value: toneBinding(\.density), range: -1...1, focusID: .density, focusedSlider: focusedSlider)
        }
    }

    private var toneCurveSection: some View {
        WorkflowSection(
            title: model.text(AppLocalizedPhrase.toneCurve),
            systemImage: "point.topleft.down.curvedto.point.bottomright.up",
            isExpanded: expandedPanel == .curve,
            toggle: { toggle(.curve) },
            reset: { reset(.curve) }
        ) {
            InspectorSlider(model.text(AppLocalizedPhrase.toneHighlights), value: toneBinding(\.curveHighlights), range: -1...1, focusID: .curveHighlights, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.lights), value: toneBinding(\.curveLights), range: -1...1, focusID: .curveLights, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.darks), value: toneBinding(\.curveDarks), range: -1...1, focusID: .curveDarks, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.shadows), value: toneBinding(\.curveShadows), range: -1...1, focusID: .curveShadows, focusedSlider: focusedSlider)
            Divider().opacity(0.4).padding(.vertical, 2)
            ToneCurveEditor(curves: pointCurves, onChange: onAdjustmentChange)
        }
    }

    private var colorSection: some View {
        WorkflowSection(
            title: model.text(AppLocalizedPhrase.color),
            systemImage: "eyedropper.halffull",
            isExpanded: expandedPanel == .color,
            toggle: { toggle(.color) },
            reset: { reset(.color) }
        ) {
            InspectorSlider(model.text(AppLocalizedPhrase.warmth), value: batchWBBinding(\.warmth), range: -1...1, focusID: .warmth, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.tint), value: batchWBBinding(\.tint), range: -1...1, focusID: .tint, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.vibrance), value: toneBinding(\.vibrance), range: -1...1, focusID: .vibrance, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.saturation), value: toneBinding(\.saturation), range: -1...1, focusID: .saturation, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.colorDepth), value: toneBinding(\.colorDepth), range: -1...1, focusID: .colorDepth, focusedSlider: focusedSlider)
        }
    }

    private var colorMixerSection: some View {
        WorkflowSection(
            title: model.text(AppLocalizedPhrase.colorMixer),
            systemImage: "circle.hexagongrid.fill",
            isExpanded: expandedPanel == .colorMixer,
            toggle: { toggle(.colorMixer) },
            reset: { reset(.colorMixer) }
        ) {
            ColorMixerSection(mixer: colorMixer, onChange: onAdjustmentChange)
        }
    }

    private var colorGradingSection: some View {
        WorkflowSection(
            title: model.text(AppLocalizedPhrase.colorGrading),
            systemImage: "paintpalette",
            isExpanded: expandedPanel == .colorGrading,
            toggle: { toggle(.colorGrading) },
            reset: { reset(.colorGrading) }
        ) {
            ColorGradingSection(grading: colorGrading, onChange: onAdjustmentChange)
        }
    }

    private var bwToningSection: some View {
        WorkflowSection(
            title: model.text(AppLocalizedPhrase.bwToning),
            systemImage: "circle.righthalf.filled",
            isExpanded: expandedPanel == .bwToning,
            toggle: { toggle(.bwToning) },
            reset: { reset(.bwToning) }
        ) {
            BWToningSection(toning: bwToning, onChange: onAdjustmentChange)
        }
    }

    private var calibrationSection: some View {
        WorkflowSection(
            title: model.text(AppLocalizedPhrase.calibration),
            systemImage: "camera.filters",
            isExpanded: expandedPanel == .calibration,
            toggle: { toggle(.calibration) },
            reset: { reset(.calibration) }
        ) {
            calibrationPrimary(model.text(AppLocalizedPhrase.redPrimary), hue: \.redHue, sat: \.redSat)
            Divider().opacity(0.35)
            calibrationPrimary(model.text(AppLocalizedPhrase.greenPrimary), hue: \.greenHue, sat: \.greenSat)
            Divider().opacity(0.35)
            calibrationPrimary(model.text(AppLocalizedPhrase.bluePrimary), hue: \.blueHue, sat: \.blueSat)
        }
    }

    private var detailSection: some View {
        WorkflowSection(
            title: model.text(AppLocalizedPhrase.detailEffects),
            systemImage: "camera.macro",
            isExpanded: expandedPanel == .detail,
            toggle: { toggle(.detail) },
            reset: { reset(.detail) }
        ) {
            InspectorRow(model.text(AppLocalizedPhrase.noiseReduction)) {
                Toggle("", isOn: noiseReductionEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if showNoiseReductionStrength {
                InspectorSlider(model.text(AppLocalizedPhrase.noiseReductionStrength), value: toneBinding(\.noiseReduction), range: 0.05...1, focusID: .noiseReduction, focusedSlider: focusedSlider)
                InspectorSlider(model.text(AppLocalizedPhrase.noiseReductionLuminance), value: toneBinding(\.noiseReductionLuma), range: 0...1, focusID: .noiseReductionLuma, focusedSlider: focusedSlider)
                InspectorSlider(model.text(AppLocalizedPhrase.noiseReductionColor), value: toneBinding(\.noiseReductionChroma), range: 0...1, focusID: .noiseReductionChroma, focusedSlider: focusedSlider)
                InspectorSlider(model.text(AppLocalizedPhrase.noiseReductionDarkTones), value: toneBinding(\.noiseReductionDarkTone), range: 0...1, focusID: .noiseReductionDarkTone, focusedSlider: focusedSlider)
                InspectorSlider(model.text(AppLocalizedPhrase.noiseReductionDetail), value: toneBinding(\.noiseReductionDetail), range: 0...1, focusID: .noiseReductionDetail, focusedSlider: focusedSlider)
                InspectorSlider(model.text(AppLocalizedPhrase.noiseReductionGrainProtect), value: toneBinding(\.noiseReductionGrainProtect), range: 0...1, focusID: .noiseReductionGrainProtect, focusedSlider: focusedSlider)
            }
            InspectorSlider(model.text(AppLocalizedPhrase.grain), value: toneBinding(\.grain), range: 0...1, focusID: .grain, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.sharpness), value: toneBinding(\.sharpness), range: 0...1, focusID: .sharpness, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.clarity), value: toneBinding(\.clarity), range: -1...1, focusID: .clarity, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.halation), value: toneBinding(\.halation), range: 0...1, focusID: .halation, focusedSlider: focusedSlider)
            InspectorSlider(model.text(AppLocalizedPhrase.vignette), value: toneBinding(\.vignette), range: -1...1, focusID: .vignette, focusedSlider: focusedSlider)
        }
    }

    private var debugSection: some View {
        WorkflowSection(
            title: model.text(AppLocalizedPhrase.developerDebug),
            systemImage: "waveform.path.ecg.rectangle",
            isExpanded: expandedPanel == .debug,
            toggle: { toggle(.debug) },
            reset: nil
        ) {
            InspectorRow(model.text(AppLocalizedPhrase.debugOverlay)) {
                Toggle("", isOn: debugOverlayEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            InspectorRow(model.text(AppLocalizedPhrase.stage)) {
                Picker(model.text(AppLocalizedPhrase.stage), selection: debugOverlayStage) {
                    ForEach(DevelopDebugStage.allCases, id: \.self) { stage in
                        Text(stage.displayName).tag(stage)
                    }
                }
                .labelsHidden()
                .disabled(!debugOverlayEnabled.wrappedValue)
            }
            if let debugMetricsText {
                Text(debugMetricsText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
                    .allowsTightening(true)
            }
        }
    }

    private func calibrationPrimary(
        _ title: String,
        hue: WritableKeyPath<CalibrationAdjust, Double>,
        sat: WritableKeyPath<CalibrationAdjust, Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            InspectorSlider(model.text(AppLocalizedPhrase.hue), value: calibrationBinding(hue), range: -1...1)
            InspectorSlider(model.text(AppLocalizedPhrase.saturation), value: calibrationBinding(sat), range: -1...1)
        }
    }
}
