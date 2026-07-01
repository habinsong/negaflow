import SwiftUI
import AppKit
import Chromabase

enum InspectorPanel: CaseIterable {
    case tone
    case curve
    case color
    case colorMixer
    case colorGrading
    case calibration
    case detail
    case debug
}

struct DevelopWorkflowInspector: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @Binding var cropMode: Bool
    @Binding var brushMode: Bool
    @Binding var regionICEMode: Bool
    @State private var expandedPanel: InspectorPanel? = .tone
    @State private var autoMatchScannerProfile = false
    @FocusState private var focusedSlider: InspectorSliderFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image = displayedImage {
                InspectorCard {
                    InteractiveHistogramView(image: image, frame: frame) { scheduleRedevelop(frame) }
                        .disabled(model.isScanning)
                }
            }

            BaseControlSection(
                frame: frame,
                baseMode: baseModeBinding,
                manualBaseBinding: manualBaseBinding(channel:),
                filmStockDminID: filmStockDminIDBinding,
                scannerProfileID: scannerProfileIDBinding,
                scannerProfiles: matchingScannerProfiles,
                autoMatchScannerProfile: $autoMatchScannerProfile,
                autoMatchAction: applyAutoMatchedScannerProfile
            )
            .disabled(model.isScanning)

            ToolStripSection(frame: frame, cropMode: $cropMode, brushMode: $brushMode, regionICEMode: $regionICEMode)
                .disabled(model.isScanning)

            Button(role: .destructive) {
                resetAllAdjustments()
            } label: {
                Label("Reset All Adjustments", systemImage: "arrow.counterclockwise.circle")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .disabled(model.isScanning)
            .help("Geometry(회전/크롭)를 제외한 모든 보정 값을 초기화합니다")

            // 자동 보정 — 라이트룸 Auto Tone(⌘U) / Auto White Balance(⇧⌘U). 현상 결과를 분석해
            // 톤/색을 한 번에 맞춘 뒤, 아래 슬라이더로 미세조정한다(델타 누적 → 다시 눌러도 수렴).
            HStack(spacing: 8) {
                Button { model.autoTone(frame) } label: {
                    Label("Auto Tone", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }
                .keyboardShortcut("u", modifiers: .command)
                .help("자동 톤 ⌘U — 히스토그램으로 노출·대비·하이라이트·섀도우·화이트·블랙·바이브런스 보정")
                Button { model.autoWhiteBalance(frame) } label: {
                    Label("Auto WB", systemImage: "drop.halffull").frame(maxWidth: .infinity)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .help("자동 화이트 밸런스 ⇧⌘U — gray-world 로 Warmth·Tint 무채색 보정")
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .disabled(model.isScanning || frame.developedImage == nil)

            WorkflowSection(
                title: "Basic Tone",
                systemImage: "slider.horizontal.3",
                isExpanded: expandedPanel == .tone,
                toggle: { toggle(.tone) },
                reset: { reset(.tone) },
                contentDisabled: model.isScanning
            ) {
                InspectorRow("Look") {
                    Picker("Look", selection: Binding(
                        get: { frame.preset },
                        set: { frame.preset = $0; scheduleRedevelop(frame) }
                    )) {
                        Text("없음").tag(LookPreset?.none)
                        ForEach(model.presets) { Text($0.name).tag(LookPreset?.some($0)) }
                    }
                    .labelsHidden()
                }
                InspectorSlider("Exposure", value: toneBinding(\.exposure), range: -2...2, focusID: .exposure, focusedSlider: $focusedSlider)
                InspectorSlider("Contrast", value: toneBinding(\.contrast), range: -1...1, focusID: .contrast, focusedSlider: $focusedSlider)
                InspectorSlider("Highlights", value: toneBinding(\.highlight), range: -1...1, focusID: .highlight, focusedSlider: $focusedSlider)
                InspectorSlider("Shadows", value: toneBinding(\.shadow), range: -1...1, focusID: .shadow, focusedSlider: $focusedSlider)
                InspectorSlider("Whites", value: toneBinding(\.whites), range: -1...1, focusID: .whites, focusedSlider: $focusedSlider)
                InspectorSlider("Blacks", value: toneBinding(\.blacks), range: -1...1, focusID: .blacks, focusedSlider: $focusedSlider)
                InspectorSlider("Density", value: toneBinding(\.density), range: -1...1, focusID: .density, focusedSlider: $focusedSlider)
            }

            WorkflowSection(
                title: "Tone Curve",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                isExpanded: expandedPanel == .curve,
                toggle: { toggle(.curve) },
                reset: { reset(.curve) },
                contentDisabled: model.isScanning
            ) {
                InspectorSlider("Highlights", value: toneBinding(\.curveHighlights), range: -1...1, focusID: .curveHighlights, focusedSlider: $focusedSlider)
                InspectorSlider("Lights", value: toneBinding(\.curveLights), range: -1...1, focusID: .curveLights, focusedSlider: $focusedSlider)
                InspectorSlider("Darks", value: toneBinding(\.curveDarks), range: -1...1, focusID: .curveDarks, focusedSlider: $focusedSlider)
                InspectorSlider("Shadows", value: toneBinding(\.curveShadows), range: -1...1, focusID: .curveShadows, focusedSlider: $focusedSlider)
                Divider().opacity(0.4).padding(.vertical, 2)
                ToneCurveEditor(curves: pointCurvesBinding, onChange: { scheduleRedevelop(frame) })
            }

            WorkflowSection(
                title: "Color",
                systemImage: "eyedropper.halffull",
                isExpanded: expandedPanel == .color,
                toggle: { toggle(.color) },
                reset: { reset(.color) },
                contentDisabled: model.isScanning
            ) {
                InspectorSlider("Warmth", value: batchWBBinding(\.warmth), range: -1...1, focusID: .warmth, focusedSlider: $focusedSlider)
                InspectorSlider("Tint", value: batchWBBinding(\.tint), range: -1...1, focusID: .tint, focusedSlider: $focusedSlider)
                InspectorSlider("Vibrance", value: toneBinding(\.vibrance), range: -1...1, focusID: .vibrance, focusedSlider: $focusedSlider)
                InspectorSlider("Saturation", value: toneBinding(\.saturation), range: -1...1, focusID: .saturation, focusedSlider: $focusedSlider)
                InspectorSlider("Color Depth", value: toneBinding(\.colorDepth), range: -1...1, focusID: .colorDepth, focusedSlider: $focusedSlider)
            }

            WorkflowSection(
                title: "Color Mixer",
                systemImage: "circle.hexagongrid.fill",
                isExpanded: expandedPanel == .colorMixer,
                toggle: { toggle(.colorMixer) },
                reset: { reset(.colorMixer) },
                contentDisabled: model.isScanning
            ) {
                ColorMixerSection(mixer: colorMixerBinding, onChange: { scheduleRedevelop(frame) })
            }

            WorkflowSection(
                title: "Color Grading",
                systemImage: "paintpalette",
                isExpanded: expandedPanel == .colorGrading,
                toggle: { toggle(.colorGrading) },
                reset: { reset(.colorGrading) },
                contentDisabled: model.isScanning
            ) {
                ColorGradingSection(grading: colorGradingBinding, onChange: { scheduleRedevelop(frame) })
            }

            WorkflowSection(
                title: "Calibration",
                systemImage: "camera.filters",
                isExpanded: expandedPanel == .calibration,
                toggle: { toggle(.calibration) },
                reset: { reset(.calibration) },
                contentDisabled: model.isScanning
            ) {
                calibrationPrimary("Red Primary", hue: \.redHue, sat: \.redSat)
                Divider().opacity(0.35)
                calibrationPrimary("Green Primary", hue: \.greenHue, sat: \.greenSat)
                Divider().opacity(0.35)
                calibrationPrimary("Blue Primary", hue: \.blueHue, sat: \.blueSat)
            }

            WorkflowSection(
                title: "Detail & Effects",
                systemImage: "camera.macro",
                isExpanded: expandedPanel == .detail,
                toggle: { toggle(.detail) },
                reset: { reset(.detail) },
                contentDisabled: model.isScanning
            ) {
                InspectorRow("Noise Reduction") {
                    Toggle("", isOn: noiseReductionEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if frame.params.noiseReduction > 1e-3 {
                    InspectorSlider("NR Strength", value: toneBinding(\.noiseReduction), range: 0.05...1, focusID: .noiseReduction, focusedSlider: $focusedSlider)
                }
                InspectorSlider("Grain", value: toneBinding(\.grain), range: 0...1, focusID: .grain, focusedSlider: $focusedSlider)
                InspectorSlider("Sharpness", value: toneBinding(\.sharpness), range: 0...1, focusID: .sharpness, focusedSlider: $focusedSlider)
                InspectorSlider("Clarity", value: toneBinding(\.clarity), range: -1...1, focusID: .clarity, focusedSlider: $focusedSlider)
                InspectorSlider("Halation", value: toneBinding(\.halation), range: 0...1, focusID: .halation, focusedSlider: $focusedSlider)
                InspectorSlider("Vignette", value: toneBinding(\.vignette), range: -1...1, focusID: .vignette, focusedSlider: $focusedSlider)
            }

            WorkflowSection(
                title: "Developer Debug",
                systemImage: "waveform.path.ecg.rectangle",
                isExpanded: expandedPanel == .debug,
                toggle: { toggle(.debug) },
                reset: nil,
                contentDisabled: model.isScanning
            ) {
                InspectorRow("Debug Overlay") {
                    Toggle("", isOn: debugOverlayEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                InspectorRow("Stage") {
                    Picker("Stage", selection: debugOverlayStageBinding) {
                        ForEach(DevelopDebugStage.allCases, id: \.self) { stage in
                            Text(stage.displayName).tag(stage)
                        }
                    }
                    .labelsHidden()
                    .disabled(!frame.debugOverlayEnabled)
                }
                if let debugMetricsText {
                    Text(debugMetricsText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .allowsTightening(true)
                }
            }
        }
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { handleSliderKey(.decrease, press: $0) }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { handleSliderKey(.decrease, press: $0) }
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { handleSliderKey(.increase, press: $0) }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { handleSliderKey(.increase, press: $0) }
        .onKeyPress(.tab, phases: .down) { handleSliderTab(press: $0) }
        .onChange(of: expandedPanel) { _, _ in
            guard let focusedSlider, !visibleSliderOrder.contains(focusedSlider) else { return }
            self.focusedSlider = nil
        }
    }

    var displayedImage: NSImage? {
        frame.showDeveloped ? (frame.developedImage ?? frame.rawPreviewImage)
                            : (frame.rawPreviewImage ?? frame.developedImage)
    }

    func toggle(_ panel: InspectorPanel) {
        withAnimation(.snappy(duration: 0.18)) {
            expandedPanel = expandedPanel == panel ? nil : panel
        }
    }

    func reset(_ panel: InspectorPanel) {
        let defaults = DevelopParameters()
        frame.updateParams { params in
            switch panel {
            case .tone:
                frame.preset = model.presets.first(where: { $0.id == "neutral" })
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
            case .calibration:
                params.redPrimary = defaults.redPrimary
                params.greenPrimary = defaults.greenPrimary
                params.bluePrimary = defaults.bluePrimary
                params.calibration = defaults.calibration
            case .detail:
                params.noiseReduction = defaults.noiseReduction
                params.grain = defaults.grain
                params.sharpness = defaults.sharpness
                params.clarity = defaults.clarity
                params.halation = defaults.halation
                params.vignette = defaults.vignette
            case .debug:
                break
            }
        }
        scheduleRedevelop(frame)
        if panel == .color { syncBatchWBIfNeeded() }
    }

    /// 노이즈 제거 on/off 토글. 켜면 기본 강도(0.7), 끄면 0.
    var noiseReductionEnabledBinding: Binding<Bool> {
        Binding(
            get: { frame.params.noiseReduction > 1e-3 },
            set: { on in
                frame.updateParams { $0.noiseReduction = on ? 0.7 : 0 }
                scheduleRedevelop(frame)
            }
        )
    }

    var debugOverlayEnabledBinding: Binding<Bool> {
        Binding(
            get: { frame.debugOverlayEnabled },
            set: { isOn in
                frame.debugOverlayEnabled = isOn
                if isOn {
                    scheduleRedevelop(frame)
                }
            }
        )
    }

    var debugOverlayStageBinding: Binding<DevelopDebugStage> {
        Binding(
            get: { frame.debugOverlayStage },
            set: { frame.debugOverlayStage = $0 }
        )
    }

    var debugMetricsText: String? {
        guard frame.debugOverlayEnabled else {
            return nil
        }
        guard let metrics = frame.debugMetrics[frame.debugOverlayStage] else {
            return nil
        }
        return "dmin \(format(metrics.dmin)) · dmax \(format(metrics.dmaxNorm))"
    }

    func format(_ value: SIMD3<Double>?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.3f %.3f %.3f", value.x, value.y, value.z)
    }

    func toneBinding(_ keyPath: WritableKeyPath<DevelopParameters, Double>) -> Binding<Double> {
        Binding(
            get: { frame.params[keyPath: keyPath] },
            set: { value in
                frame.updateParams { $0[keyPath: keyPath] = value }
                scheduleRedevelop(frame)
            }
        )
    }

    // MARK: 고급 색/톤 바인딩 (서브구조체 통째로 set → updateParams가 재현상 트리거)

    var pointCurvesBinding: Binding<PointCurves> {
        Binding(get: { frame.params.pointCurves },
                set: { v in frame.updateParams { $0.pointCurves = v } })
    }
    var colorMixerBinding: Binding<ColorMixer> {
        Binding(get: { frame.params.colorMixer },
                set: { v in frame.updateParams { $0.colorMixer = v } })
    }
    var colorGradingBinding: Binding<ColorGrading> {
        Binding(get: { frame.params.colorGrading },
                set: { v in frame.updateParams { $0.colorGrading = v } })
    }

    func calibBinding(_ keyPath: WritableKeyPath<CalibrationAdjust, Double>) -> Binding<Double> {
        Binding(
            get: { frame.params.calibration[keyPath: keyPath] },
            set: { value in
                frame.updateParams { $0.calibration[keyPath: keyPath] = value }
                scheduleRedevelop(frame)
            }
        )
    }

    @ViewBuilder
    func calibrationPrimary(
        _ title: String,
        hue: WritableKeyPath<CalibrationAdjust, Double>,
        sat: WritableKeyPath<CalibrationAdjust, Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            InspectorSlider("Hue", value: calibBinding(hue), range: -1...1)
            InspectorSlider("Saturation", value: calibBinding(sat), range: -1...1)
        }
    }

    /// Geometry(imageTransform)·Base 설정을 제외한 모든 보정 값을 기본값으로 되돌린다.
    func resetAllAdjustments() {
        let d = DevelopParameters()
        frame.preset = model.presets.first(where: { $0.id == "neutral" })
        frame.updateParams { p in
            p.exposure = d.exposure; p.contrast = d.contrast; p.density = d.density
            p.highlight = d.highlight; p.shadow = d.shadow; p.whites = d.whites; p.blacks = d.blacks
            p.curveHighlights = d.curveHighlights; p.curveLights = d.curveLights
            p.curveDarks = d.curveDarks; p.curveShadows = d.curveShadows
            p.pointCurves = d.pointCurves
            p.warmth = d.warmth; p.tint = d.tint; p.vibrance = d.vibrance
            p.saturation = d.saturation; p.colorDepth = d.colorDepth
            p.redPrimary = d.redPrimary; p.greenPrimary = d.greenPrimary; p.bluePrimary = d.bluePrimary
            p.colorMixer = d.colorMixer; p.colorGrading = d.colorGrading; p.calibration = d.calibration
            p.grain = d.grain; p.sharpness = d.sharpness; p.clarity = d.clarity
            p.halation = d.halation; p.vignette = d.vignette; p.noiseReduction = d.noiseReduction
        }
        scheduleRedevelop(frame)
        syncBatchWBIfNeeded()
    }

    var visibleSliderOrder: [InspectorSliderFocus] {
        switch expandedPanel {
        case .tone:
            return [.exposure, .contrast, .highlight, .shadow, .whites, .blacks, .density]
        case .curve:
            return [.curveHighlights, .curveLights, .curveDarks, .curveShadows]
        case .color:
            return [.warmth, .tint, .vibrance, .saturation, .colorDepth]
        case .calibration:
            return []
        case .detail:
            var ids: [InspectorSliderFocus] = []
            if frame.params.noiseReduction > 1e-3 { ids.append(.noiseReduction) }
            ids.append(contentsOf: [.grain, .sharpness, .clarity, .halation, .vignette])
            return ids
        case .colorMixer, .colorGrading, .debug, nil:
            return []
        }
    }

    func handleSliderKey(_ direction: DevelopKeyboardNudge.Direction, press: KeyPress) -> KeyPress.Result {
        guard !model.isScanning, let focusedSlider else { return .ignored }
        nudge(focusedSlider, direction: direction, coarse: press.modifiers.contains(.shift))
        return .handled
    }

    func handleSliderTab(press: KeyPress) -> KeyPress.Result {
        let order = visibleSliderOrder
        guard let focusedSlider, let index = order.firstIndex(of: focusedSlider), !order.isEmpty else {
            return .ignored
        }
        let offset = press.modifiers.contains(.shift) ? -1 : 1
        let next = (index + offset + order.count) % order.count
        self.focusedSlider = order[next]
        return .handled
    }

    func nudge(_ slider: InspectorSliderFocus, direction: DevelopKeyboardNudge.Direction, coarse: Bool) {
        switch slider {
        case .exposure:
            nudgeParam(\.exposure, range: -2...2, direction: direction, coarse: coarse)
        case .contrast:
            nudgeParam(\.contrast, range: -1...1, direction: direction, coarse: coarse)
        case .highlight:
            nudgeParam(\.highlight, range: -1...1, direction: direction, coarse: coarse)
        case .shadow:
            nudgeParam(\.shadow, range: -1...1, direction: direction, coarse: coarse)
        case .whites:
            nudgeParam(\.whites, range: -1...1, direction: direction, coarse: coarse)
        case .blacks:
            nudgeParam(\.blacks, range: -1...1, direction: direction, coarse: coarse)
        case .density:
            nudgeParam(\.density, range: -1...1, direction: direction, coarse: coarse)
        case .curveHighlights:
            nudgeParam(\.curveHighlights, range: -1...1, direction: direction, coarse: coarse)
        case .curveLights:
            nudgeParam(\.curveLights, range: -1...1, direction: direction, coarse: coarse)
        case .curveDarks:
            nudgeParam(\.curveDarks, range: -1...1, direction: direction, coarse: coarse)
        case .curveShadows:
            nudgeParam(\.curveShadows, range: -1...1, direction: direction, coarse: coarse)
        case .warmth:
            nudgeBatchWBParam(\.warmth, range: -1...1, direction: direction, coarse: coarse)
        case .tint:
            nudgeBatchWBParam(\.tint, range: -1...1, direction: direction, coarse: coarse)
        case .vibrance:
            nudgeParam(\.vibrance, range: -1...1, direction: direction, coarse: coarse)
        case .saturation:
            nudgeParam(\.saturation, range: -1...1, direction: direction, coarse: coarse)
        case .colorDepth:
            nudgeParam(\.colorDepth, range: -1...1, direction: direction, coarse: coarse)
        case .redPrimary:
            nudgeParam(\.redPrimary, range: -1...1, direction: direction, coarse: coarse)
        case .greenPrimary:
            nudgeParam(\.greenPrimary, range: -1...1, direction: direction, coarse: coarse)
        case .bluePrimary:
            nudgeParam(\.bluePrimary, range: -1...1, direction: direction, coarse: coarse)
        case .noiseReduction:
            nudgeParam(\.noiseReduction, range: 0.05...1, direction: direction, coarse: coarse)
        case .grain:
            nudgeParam(\.grain, range: 0...1, direction: direction, coarse: coarse)
        case .sharpness:
            nudgeParam(\.sharpness, range: 0...1, direction: direction, coarse: coarse)
        case .clarity:
            nudgeParam(\.clarity, range: -1...1, direction: direction, coarse: coarse)
        case .halation:
            nudgeParam(\.halation, range: 0...1, direction: direction, coarse: coarse)
        case .vignette:
            nudgeParam(\.vignette, range: -1...1, direction: direction, coarse: coarse)
        }
    }

    func nudgeParam(
        _ keyPath: WritableKeyPath<DevelopParameters, Double>,
        range: ClosedRange<Double>,
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
        scheduleRedevelop(frame)
    }

    func nudgeBatchWBParam(
        _ keyPath: WritableKeyPath<DevelopParameters, Double>,
        range: ClosedRange<Double>,
        direction: DevelopKeyboardNudge.Direction,
        coarse: Bool
    ) {
        nudgeParam(keyPath, range: range, direction: direction, coarse: coarse)
        syncBatchWBIfNeeded()
    }

    func batchWBBinding(_ keyPath: WritableKeyPath<DevelopParameters, Double>) -> Binding<Double> {
        Binding(
            get: { frame.params[keyPath: keyPath] },
            set: { value in
                frame.updateParams { $0[keyPath: keyPath] = value }
                scheduleRedevelop(frame)
                syncBatchWBIfNeeded()
            }
        )
    }

    var baseModeBinding: Binding<DevelopParameters.BaseMode> {
        Binding(
            get: { frame.params.baseEstimationMode },
            set: { mode in
                frame.updateParams { params in
                    params.baseEstimationMode = mode
                    if mode == .manual, params.manualBaseRGB == nil {
                        params.manualBaseRGB = frame.baseRGB ?? SIMD3(0.90, 0.65, 0.45)
                    }
                    if mode != .preset {
                        autoMatchScannerProfile = false
                    } else if autoMatchScannerProfile {
                        params.scannerProfileID = autoMatchedScannerProfileID(filmStockDminID: params.filmStockDminID)
                        model.scannerProfileID = params.scannerProfileID
                    }
                }
                scheduleRedevelop(frame)
                syncBatchWBIfNeeded()
            }
        )
    }

    /// 필름 Dmin/Dmax 프리셋 ID 바인딩. preset 모드에서 사용자가 필름을 선택하면 현상을 다시 건다.
    var filmStockDminIDBinding: Binding<String?> {
        Binding(
            get: { frame.params.filmStockDminID },
            set: { id in
                frame.updateParams { params in
                    params.filmStockDminID = id
                    // "선택 안 함"이면 preset 의미가 없으니 auto로 되돌린다.
                    if id == nil { params.baseEstimationMode = .auto }
                    if autoMatchScannerProfile {
                        params.scannerProfileID = autoMatchedScannerProfileID(filmStockDminID: id)
                        model.scannerProfileID = params.scannerProfileID
                    }
                }
                scheduleRedevelop(frame)
                syncBatchWBIfNeeded()
            }
        )
    }

    var scannerProfileIDBinding: Binding<String?> {
        Binding(
            get: { frame.params.scannerProfileID },
            set: { id in
                model.scannerProfileID = id
                frame.updateParams { $0.scannerProfileID = id }
                scheduleRedevelop(frame)
                syncBatchWBIfNeeded()
            }
        )
    }

    var matchingScannerProfiles: [ScannerProfile] {
        ScannerProfileMatcher.matchingProfiles(
            target: frame.params.developTarget,
            filmType: frame.params.filmType,
            profiles: model.scannerProfiles
        )
    }

    func autoMatchedScannerProfileID(filmStockDminID: String?) -> String? {
        ScannerProfileMatcher.preferredProfileID(
            target: frame.params.developTarget,
            filmType: frame.params.filmType,
            filmStockDminID: filmStockDminID,
            currentID: nil,
            profiles: model.scannerProfiles
        )
    }

    func applyAutoMatchedScannerProfile() {
        let id = autoMatchedScannerProfileID(filmStockDminID: frame.params.filmStockDminID)
        model.scannerProfileID = id
        frame.updateParams { $0.scannerProfileID = id }
        scheduleRedevelop(frame)
        syncBatchWBIfNeeded()
    }

    func manualBaseBinding(channel: Int) -> Binding<Double> {
        Binding(
            get: {
                let rgb = frame.params.manualBaseRGB ?? frame.baseRGB ?? SIMD3(0.90, 0.65, 0.45)
                switch channel {
                case 0: return rgb.x
                case 1: return rgb.y
                default: return rgb.z
                }
            },
            set: { value in
                var rgb = frame.params.manualBaseRGB ?? frame.baseRGB ?? SIMD3(0.90, 0.65, 0.45)
                let clamped = min(max(value, 0), 1)
                switch channel {
                case 0: rgb.x = clamped
                case 1: rgb.y = clamped
                default: rgb.z = clamped
                }
                frame.updateParams {
                    $0.manualBaseRGB = rgb
                    $0.baseEstimationMode = .manual
                }
                scheduleRedevelop(frame)
                syncBatchWBIfNeeded()
            }
        )
    }

    func syncBatchWBIfNeeded() { }   // Auto Sync WB(배치 WB 동기화) 제거됨 — 기존 호출부 호환용 no-op

    func scheduleRedevelop(_ frame: ScanFrame) {
        // 레이트 throttle은 모델이 담당한다(리딩+트레일링 ~22fps). 매 틱 동기 리비전 증가로 루프를
        // 무제한 렌더시키던 과거 방식이 GPU(IOSurface) 누적·간헐 블랭크 렌더의 원인이었다.
        model.requestDevelop(frame)
    }
}
