import SwiftUI
import AppKit
import Chromabase

extension DevelopWorkflowInspector {
    func resetPhotoAngle() {
        model.resetPhotoAngle(frame)
    }

    /// 히스토그램은 지금 화면에 보이는 픽셀의 분포여야 한다. 현상본을 기다리는 동안 원본으로
    /// 폴백하면 네거티브에서 반전 전 분포가 잠깐 그려져, 그 위에서 누른 Auto 조정까지 어긋난다.
    var displayedImage: NSImage? {
        frame.showDeveloped ? (frame.developedImage ?? frame.thumbnailImage)
                            : (frame.rawPreviewImage ?? frame.developedImage)
    }

    func toggle(_ panel: InspectorPanel) {
        withAnimation(.snappy(duration: 0.18)) {
            expandedPanel = expandedPanel == panel ? nil : panel
        }
    }

    func reset(_ panel: InspectorPanel) {
        let shouldSyncBatchWB = DevelopInspectorResetter.reset(panel, frame: frame, neutralPreset: neutralPreset)
        scheduleRedevelop(frame)
        if shouldSyncBatchWB { syncBatchWBIfNeeded() }
    }

    var noiseReductionEnabledBinding: Binding<Bool> {
        DevelopInspectorBindings.noiseReductionEnabled(frame: frame) { scheduleRedevelop(frame) }
    }

    var debugOverlayEnabledBinding: Binding<Bool> {
        DevelopInspectorBindings.debugOverlayEnabled(frame: frame) { scheduleRedevelop(frame) }
    }

    var debugOverlayStageBinding: Binding<DevelopDebugStage> {
        DevelopInspectorBindings.debugOverlayStage(frame: frame)
    }

    var debugMetricsText: String? {
        guard frame.debugOverlayEnabled else {
            return nil
        }
        guard let metrics = frame.debugMetrics[frame.debugOverlayStage] else {
            return nil
        }
        return model.text(AppLocalizedPhrase.baseMetricsFormat, format(metrics.dmin), format(metrics.dmaxNorm))
    }

    func format(_ value: SIMD3<Double>?) -> String {
        guard let value else { return model.text(AppLocalizedPhrase.notAvailableAbbrev) }
        return String(format: "%.3f %.3f %.3f", value.x, value.y, value.z)
    }

    func toneBinding(_ keyPath: WritableKeyPath<DevelopParameters, Double>) -> Binding<Double> {
        DevelopInspectorBindings.tone(frame: frame, keyPath: keyPath) { scheduleRedevelop(frame) }
    }

    var pointCurvesBinding: Binding<PointCurves> {
        DevelopInspectorBindings.pointCurves(frame: frame)
    }
    var colorMixerBinding: Binding<ColorMixer> {
        DevelopInspectorBindings.colorMixer(frame: frame)
    }
    var colorGradingBinding: Binding<ColorGrading> {
        DevelopInspectorBindings.colorGrading(frame: frame)
    }
    var bwToningBinding: Binding<BWToning> {
        DevelopInspectorBindings.bwToning(frame: frame)
    }

    var isBWToningAvailable: Bool {
        frame.filmType == .bwNegative || frame.filmType == .bwPositive
    }

    func calibBinding(_ keyPath: WritableKeyPath<CalibrationAdjust, Double>) -> Binding<Double> {
        DevelopInspectorBindings.calibration(frame: frame, keyPath: keyPath) { scheduleRedevelop(frame) }
    }

    /// Geometry(imageTransform)·Base 설정을 제외한 모든 보정 값을 기본값으로 되돌린다(⌘Z 로 취소 가능).
    func resetAllAdjustments() {
        model.resetAllDevelopAdjustments(frame, neutralPreset: neutralPreset)
        syncBatchWBIfNeeded()
    }

    var neutralPreset: LookPreset? {
        model.presets.first(where: { $0.id == "neutral" })
    }

    var visibleSliderOrder: [InspectorSliderFocus] {
        guard selectedTab == .basic else { return [] }
        return DevelopInspectorFocusNavigation.visibleSliderOrder(
            expandedPanel: expandedPanel,
            showNoiseReductionStrength: frame.params.noiseReduction > 1e-3
        )
    }

    func handleSliderKey(_ direction: DevelopKeyboardNudge.Direction, press: KeyPress) -> KeyPress.Result {
        guard selectedTab == .basic, let focusedSlider else { return .ignored }
        nudge(focusedSlider, direction: direction, coarse: press.modifiers.contains(.shift))
        return .handled
    }

    func handleSliderTab(press: KeyPress) -> KeyPress.Result {
        guard selectedTab == .basic else { return .ignored }
        guard let next = DevelopInspectorFocusNavigation.nextFocusedSlider(
            current: focusedSlider,
            order: visibleSliderOrder,
            reverse: press.modifiers.contains(.shift)
        ) else {
            return .ignored
        }
        self.focusedSlider = next
        return .handled
    }

    func nudge(_ slider: InspectorSliderFocus, direction: DevelopKeyboardNudge.Direction, coarse: Bool) {
        let shouldSyncBatchWB = DevelopInspectorKeyboardController.nudge(
            slider,
            frame: frame,
            direction: direction,
            coarse: coarse
        )
        scheduleRedevelop(frame)
        if shouldSyncBatchWB { syncBatchWBIfNeeded() }
    }

}
