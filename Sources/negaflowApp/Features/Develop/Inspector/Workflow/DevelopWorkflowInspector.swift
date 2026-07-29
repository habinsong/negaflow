import SwiftUI
import AppKit
import Chromabase

enum InspectorPanel: CaseIterable {
    case tone
    case curve
    case color
    case colorMixer
    case colorGrading
    case bwToning
    case calibration
    case detail
    case debug
}

enum DevelopInspectorTab: CaseIterable, Identifiable {
    case basic
    case base
    case edit
    case defects
    case info
    case reset

    var id: Self { self }

    var systemImages: [String] {
        switch self {
        case .basic: return ["slider.horizontal.3"]
        case .base: return ["circle.lefthalf.filled"]
        case .edit: return ["crop.rotate"]
        case .defects: return ["paintbrush.pointed.fill"]
        case .info: return ["info.circle"]
        case .reset: return ["arrow.counterclockwise.circle"]
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .basic: return AppLocalization.text(.inspectorTabBasic, language: language)
        case .base: return AppLocalization.text(.baseSection, language: language)
        case .edit: return AppLocalization.text(.inspectorTabEdit, language: language)
        case .defects: return AppLocalization.text(.inspectorTabDefect, language: language)
        case .info: return SourceMetadataInspectorLocalizedText.info.resolved(language: language)
        case .reset: return AppLocalization.text(.reset, language: language)
        }
    }
}

struct DevelopWorkflowInspector: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject private var localAdjustmentSession: LocalAdjustmentSession
    @ObservedObject var frame: ScanFrame
    @Binding var cropMode: Bool
    @Binding var brushMode: Bool
    @Binding var regionDefectMode: Bool
    @Binding var cloneStampMode: Bool
    @Binding var basePickerMode: Bool
    @State var expandedPanel: InspectorPanel? = .tone
    @State var selectedTab: DevelopInspectorTab = .basic
    @FocusState var focusedSlider: InspectorSliderFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image = displayedImage {
                InspectorCard {
                    InteractiveHistogramView(image: image, frame: frame) { scheduleRedevelop(frame) }
                }
            }

            tabStrip
            selectedTabContent
        }
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { handleSliderKey(.decrease, press: $0) }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { handleSliderKey(.decrease, press: $0) }
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { handleSliderKey(.increase, press: $0) }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { handleSliderKey(.increase, press: $0) }
        .onKeyPress(.tab, phases: .down) { handleSliderTab(press: $0) }
        .onChange(of: selectedTab) { _, tab in
            cancelActiveInteraction()
            if tab != .basic { focusedSlider = nil }
        }
        .onChange(of: expandedPanel) { _, _ in
            guard let focusedSlider, !visibleSliderOrder.contains(focusedSlider) else { return }
            self.focusedSlider = nil
        }
        .onChange(of: frame.filmType) { _, _ in
            if expandedPanel == .bwToning && !isBWToningAvailable {
                expandedPanel = nil
            }
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(DevelopInspectorTab.allCases.enumerated()), id: \.element) { index, tab in
                if index > 0 {
                    // 아이콘 사이 구분선. 선택/호버 음영 아래에 깔리지 않게 얇고 흐리게.
                    Divider()
                        .frame(height: 15)
                        .overlay(Color.primary.opacity(0.12))
                }
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    DevelopInspectorTabLabel(
                        title: tab.title(language: model.appLanguage),
                        systemImages: tab.systemImages,
                        isSelected: selectedTab == tab
                    )
                }
                .buttonStyle(.plain)
                .help(tab.title(language: model.appLanguage))
                .accessibilityLabel(tab.title(language: model.appLanguage))
                .accessibilitySelectionState(
                    selectedTab == tab,
                    selectedValue: model.accessibilityText(.selected),
                    unselectedValue: model.accessibilityText(.notSelected),
                    unselectedHint: model.accessibilityText(.select)
                )
            }
        }
        .padding(3)
        .liquidSurface(cornerRadius: 18, interactive: true)
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .basic:
            basicQuickActionsContent
            basicAdjustmentContent
        case .base:
            baseControlContent
            basicAdjustmentContent
        case .edit:
            editToolContent
            basicAdjustmentContent
        case .defects:
            grainMendToolContent
            basicAdjustmentContent
        case .info:
            SourceMetadataInspectorView(frame: frame)
            AppMetadataOverlayEditor(frame: frame)
            RollRecordEditor(frame: frame)
        case .reset:
            resetToolContent
            basicAdjustmentContent
        }
    }

    private var baseControlContent: some View {
        BaseControlSection(
            frame: frame,
            baseMode: baseModeBinding,
            manualBaseBinding: manualBaseBinding(channel:),
            filmStockDminID: filmStockDminIDBinding,
            lightSourceProfileID: lightSourceProfileIDBinding,
            basePickerMode: $basePickerMode,
            resetManualBase: resetManualBase,
            scannerProfileID: scannerProfileIDBinding,
            scannerProfiles: matchingScannerProfiles
        )
    }

    private var editToolContent: some View {
        Group {
            ToolStripSection(
                frame: frame,
                cropMode: $cropMode,
                brushMode: $brushMode,
                regionDefectMode: $regionDefectMode
            )
            LocalAdjustmentSection(
                frame: frame,
                cropMode: $cropMode,
                brushMode: $brushMode,
                regionDefectMode: $regionDefectMode,
                cloneStampMode: $cloneStampMode,
                basePickerMode: $basePickerMode
            )
        }
    }

    @ViewBuilder
    private var grainMendToolContent: some View {
        DefectControlsSection(
            frame: frame,
            cropMode: $cropMode,
            brushMode: $brushMode,
            regionDefectMode: $regionDefectMode,
            cloneStampMode: $cloneStampMode
        )

        DefectLayerSection(frame: frame)
    }

    private var resetToolContent: some View {
        ResetControlsSection(
            canResetPhotoAngle: canResetPhotoAngle,
            onResetAllAdjustments: resetAllAdjustments,
            onResetPhotoAngle: resetPhotoAngle
        )
    }

    private var basicAdjustmentContent: some View {
        DevelopAdjustmentSections(
            expandedPanel: expandedPanel,
            isBWToningAvailable: isBWToningAvailable,
            showNoiseReductionStrength: frame.params.noiseReduction > 1e-3,
            debugMetricsText: debugMetricsText,
            debugOverlayEnabled: debugOverlayEnabledBinding,
            debugOverlayStage: debugOverlayStageBinding,
            focusedSlider: $focusedSlider,
            pointCurves: pointCurvesBinding,
            colorMixer: colorMixerBinding,
            colorGrading: colorGradingBinding,
            bwToning: bwToningBinding,
            noiseReductionEnabled: noiseReductionEnabledBinding,
            toneBinding: toneBinding,
            batchWBBinding: batchWBBinding,
            calibrationBinding: calibBinding,
            toggle: toggle,
            reset: reset,
            onAdjustmentChange: { scheduleRedevelop(frame) }
        )
    }

    private var basicQuickActionsContent: some View {
        DevelopQuickActionsSection(
            canAutoAdjust: canAutoAdjust,
            showsAutoCorrections: frame.filmType.requiresInversion,
            autoLevels: autoCorrectionBinding(\.autoLevels),
            autoNeutralBalance: autoCorrectionBinding(\.autoNeutralBalance),
            showsResetAll: false,
            onResetAll: resetAllAdjustments,
            onAutoTone: { model.autoTone(frame) },
            onAutoWhiteBalance: { model.autoWhiteBalance(frame) },
            onResetAutoTone: { model.resetAutoTone(frame) },
            onResetAutoWhiteBalance: { model.resetAutoWhiteBalance(frame) }
        )
    }

    private var canResetPhotoAngle: Bool {
        frame.imageTransform.rotation != .deg0 || abs(frame.imageTransform.straightenAngle) >= 1e-4
    }

    private var canAutoAdjust: Bool {
        displayedImage != nil
    }

    private func cancelActiveInteraction() {
        cropMode = false
        brushMode = false
        regionDefectMode = false
        cloneStampMode = false
        basePickerMode = false
        localAdjustmentSession.deactivate()
    }

}
