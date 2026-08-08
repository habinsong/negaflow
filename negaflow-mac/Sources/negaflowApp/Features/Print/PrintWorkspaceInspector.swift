import AppKit
import Chromabase
import SwiftUI
import UniformTypeIdentifiers

enum PrintInspectorTab: String, CaseIterable, Identifiable {
    case layout
    case content
    case output

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .layout: "rectangle.inset.filled"
        case .content: "photo.on.rectangle.angled"
        case .output: "camera.filters"
        }
    }
}

struct PrintWorkspaceInspector: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settingsStore: PrintWorkspaceSettingsStore
    @State private var selectedTab = PrintInspectorTab.layout
    @State private var isAdvancedProofExpanded = false

    init(
        settingsStore: PrintWorkspaceSettingsStore,
        initialTab: PrintInspectorTab = .layout
    ) {
        self.settingsStore = settingsStore
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                inspectorHeader
                inspectorTabs
            }
            .adaptivePanelSurface(.bar)
            Divider()
            ScrollView {
                selectedTabContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaptivePanelSurface(.regular)
        .clipped()
        .accessibilityIdentifier("negaflow.print.inspector")
        .onChange(of: settingsStore.layoutMode) { _, mode in
            guard mode.usesIndividualPages, selectedTab == .content else { return }
            selectedTab = .layout
        }
    }

    private var inspectorHeader: some View {
        HStack(spacing: 8) {
            Label(model.text(.menuPrint), systemImage: "printer")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(
                model.actionableFrame?.compactDisplayName(language: model.appLanguage)
                    ?? model.text(.noFrame)
            )
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)
                .frame(maxWidth: 180, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 9)
    }

    private var inspectorTabs: some View {
        HStack(spacing: 2) {
            ForEach(availableTabs) { tab in
                PrintInspectorTabButton(
                    title: tabTitle(tab),
                    systemImage: tab.systemImage,
                    isSelected: selectedTab == tab
                ) {
                    withAnimation(.snappy(duration: 0.18)) { selectedTab = tab }
                }
            }
        }
        .padding(3)
        .liquidSurface(cornerRadius: 15)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .accessibilityIdentifier("negaflow.print.inspector.tabs")
    }

    private var availableTabs: [PrintInspectorTab] {
        settingsStore.layoutMode.usesIndividualPages
            ? [.layout, .output]
            : PrintInspectorTab.allCases
    }

    private func tabTitle(_ tab: PrintInspectorTab) -> String {
        switch tab {
        case .layout: model.text(.printLayoutMode)
        case .content: model.text(.printContentSection)
        case .output: model.text(.printOutputSection)
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .layout:
            layoutTab
        case .content:
            contentTab
        case .output:
            outputTab
        }
    }

    private var layoutTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrintInspectorSection(
                title: model.text(.printLayoutSection),
                systemImage: "rectangle.inset.filled"
            ) {
                PrintInspectorPairedInlineFields(
                    leadingTitle: model.text(.printLayoutMode),
                    leadingControl: {
                        PrintInspectorPopupPicker(
                            selection: layoutModeBinding,
                            options: PrintWorkspaceLayoutMode.allCases.map {
                                .init($0, title: layoutModeTitle($0))
                            },
                            accessibilityLabel: model.text(.printLayoutMode),
                            horizontalPadding: 6
                        )
                        .accessibilityIdentifier("negaflow.print.layout.mode")
                    },
                    trailingTitle: model.text(.printPaperSize),
                    trailingControl: {
                        PrintInspectorPopupPicker(
                            selection: $settingsStore.paperSize,
                            options: PrintPaperSize.allCases.map {
                                .init($0, title: paperSizeTitle($0))
                            },
                            accessibilityLabel: model.text(.printPaperSize),
                            horizontalPadding: 6
                        )
                    }
                )

                Divider()
                    .opacity(0.4)

                PrintInspectorStackedField(model.text(.printOrientation)) {
                    PrintInspectorSegmentedPicker(
                        options: PrintPaperOrientation.allCases,
                        label: orientationTitle,
                        selection: $settingsStore.orientation
                    )
                    .accessibilityIdentifier("negaflow.print.layout.orientation")
                }

                Divider()
                    .opacity(0.4)

                PrintInspectorSliderRow(
                    label: model.text(.printMargin),
                    value: $settingsStore.marginMM,
                    range: 0...50,
                    step: 1,
                    valueText: "\(Int(settingsStore.marginMM.rounded())) mm",
                    inputFractionDigits: 0
                )

                Divider()
                    .opacity(0.4)

                PrintInspectorBooleanSegmentedField(
                    label: model.text(.printRuler),
                    isOn: $settingsStore.showsRulers
                )
                .accessibilityIdentifier("negaflow.print.layout.ruler")

                if settingsStore.showsRulers {
                    PrintInspectorStackedField(model.text(.printRulerUnit)) {
                        PrintInspectorSegmentedPicker(
                            options: PrintRulerUnit.allCases,
                            label: rulerUnitTitle,
                            selection: $settingsStore.rulerUnit
                        )
                    }
                    .accessibilityIdentifier("negaflow.print.layout.ruler-unit")
                }

                Divider()
                    .opacity(0.4)

                PrintInspectorStackedField(model.text(.printContactSheetBackground)) {
                    PrintInspectorSegmentedPicker(
                        options: PrintContactSheetBackground.allCases,
                        label: sheetColorTitle,
                        selection: $settingsStore.sheetColor
                    )
                }
                .accessibilityIdentifier("negaflow.print.layout.sheet-color")

                PrintInspectorInlineField(model.text(.printSurface)) {
                    PrintInspectorPopupPicker(
                        selection: $settingsStore.paperSurface,
                        options: PrintPaperSurface.allCases.map {
                            .init($0, title: paperSurfaceTitle($0))
                        },
                        accessibilityLabel: model.text(.printSurface)
                    )
                }
                .accessibilityIdentifier("negaflow.print.layout.surface")
            }

            if settingsStore.layoutMode.packageMode != nil {
                PrintInspectorSection(
                    title: layoutModeTitle(settingsStore.layoutMode),
                    systemImage: layoutModeSystemImage(settingsStore.layoutMode)
                ) {
                    PrintPackageInspectorControls(
                        settingsStore: settingsStore,
                        scope: .layout
                    )
                }
            }

            PrintInspectorSection(
                title: model.text(.printTemplates),
                systemImage: "square.stack.3d.up"
            ) {
                PrintLayoutTemplateControls(settingsStore: settingsStore)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("negaflow.print.inspector.layout")
    }

    private var contentTab: some View {
        PrintInspectorSection(
            title: model.text(.printContentSection),
            systemImage: "photo.on.rectangle.angled"
        ) {
            PrintPackageInspectorControls(
                settingsStore: settingsStore,
                scope: .content
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("negaflow.print.inspector.content")
    }

    private var outputTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrintInspectorSection(
                title: model.text(.printOutputSection),
                systemImage: "camera.filters"
            ) {
                PrintInspectorStackedField(model.text(.printOutputProcess)) {
                    PrintInspectorSegmentedPicker(
                        options: PrintOutputProcess.allCases,
                        label: outputProcessTitle,
                        selection: outputProcessBinding
                    )
                    .accessibilityIdentifier("negaflow.print.output.process")
                }
            }

            if settingsStore.outputProcess == .cPrint {
                cPrintLabSection
                cPrintPreviewSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("negaflow.print.inspector.output")
    }

    private var cPrintLabSection: some View {
        PrintInspectorSection(
            title: model.text(.printOutputCPrint),
            systemImage: "photo.badge.checkmark"
        ) {
            PrintInspectorPairedInlineFields(
                leadingTitle: model.text(.printLab),
                leadingControl: {
                    PrintInspectorTextField(
                        prompt: model.text(AppLocalizedPhrase.custom),
                        text: $settingsStore.cPrintLabName
                    )
                },
                trailingTitle: model.text(.printPaper),
                trailingControl: {
                    PrintInspectorTextField(
                        prompt: model.text(AppLocalizedPhrase.custom),
                        text: $settingsStore.cPrintPaperName
                    )
                }
            )

        }
    }

    private var cPrintPreviewSection: some View {
        PrintInspectorSection(
            title: model.text(.printPreview),
            systemImage: "eye"
        ) {
            proofProfileRow

            Divider()
                .opacity(0.4)

            PrintInspectorBooleanSegmentedField(
                label: model.text(.printPreview),
                isOn: cPrintPreviewBinding
            )

            if model.cPrintProofICCProfileData == nil {
                PrintInspectorHelpText(
                    text: model.text(.printPreviewProfileRequired),
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }

            Divider()
                .opacity(0.4)

            PrintInspectorDisclosure(
                isExpanded: $isAdvancedProofExpanded,
                accessibilityLabel: model.text(.printAdvanced)
            ) {
                Text(model.text(.printAdvanced))
                    .font(.callout.weight(.medium))
            } content: {
                VStack(alignment: .leading, spacing: PrintInspectorMetrics.verticalSpacing) {
                    PrintInspectorValueRow(
                        label: model.text(.printDeliveryColorSpace),
                        value: model.exportColorSpace.uiLabel
                    )

                    Divider()
                        .opacity(0.4)

                    PrintInspectorBooleanSegmentedField(
                        label: model.text(.printPaperSimulation),
                        isOn: paperSimulationBinding
                    )

                    PrintInspectorBooleanSegmentedField(
                        label: model.text(AppLocalizedPhrase.colorGamutWarning),
                        isOn: $model.destinationGamutWarningEnabled
                    )
                }
            }
        }
    }

    private var proofProfileRow: some View {
        PrintInspectorStackedField(model.text(.printProofProfile)) {
            HStack(spacing: 6) {
                Button(action: chooseCPrintProofProfile) {
                    HStack(spacing: 8) {
                        Text(model.cPrintProofICCProfileName ?? "—")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Image(systemName: "folder")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrintInspectorTransientButtonStyle())
                .frame(maxWidth: .infinity)
                .help(model.text(AppLocalizedPhrase.choose))
                .accessibilityLabel(model.text(AppLocalizedPhrase.choose))

                if model.cPrintProofICCProfileData != nil {
                    Button(action: model.clearCPrintProofICCProfile) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(
                        PrintInspectorTransientButtonStyle(
                            horizontalPadding: 9,
                            minimumHeight: 30
                        )
                    )
                    .help(model.text(AppLocalizedPhrase.reset))
                    .accessibilityLabel(model.text(AppLocalizedPhrase.reset))
                }
            }
        }
    }

    /// 사진 비율 용지는 고정 치수가 아니라 활성 사진을 따라가므로 이름으로 보여준다.
    private func paperSizeTitle(_ paperSize: PrintPaperSize) -> String {
        paperSize == .photoRatio ? model.text(.printPaperPhotoRatio) : paperSize.uiLabel
    }

    private func orientationTitle(_ orientation: PrintPaperOrientation) -> String {
        switch orientation {
        case .automatic: model.text(.printOrientationAutomatic)
        case .portrait: model.text(.printOrientationPortrait)
        case .landscape: model.text(.printOrientationLandscape)
        }
    }

    private func rulerUnitTitle(_ unit: PrintRulerUnit) -> String {
        switch unit {
        case .inches: model.text(.printRulerInches)
        case .centimeters: model.text(.printRulerCentimeters)
        }
    }

    private func sheetColorTitle(_ background: PrintContactSheetBackground) -> String {
        switch background {
        case .black: model.text(.canvasBackgroundBlack)
        case .gray: model.text(.canvasBackgroundGray)
        case .white: model.text(.canvasBackgroundWhite)
        }
    }

    private func outputProcessTitle(_ process: PrintOutputProcess) -> String {
        switch process {
        case .standard: model.text(.printOutputStandard)
        case .cPrint: model.text(.printOutputCPrint)
        }
    }

    private func layoutModeSystemImage(_ mode: PrintWorkspaceLayoutMode) -> String {
        switch mode {
        case .singleImage: "photo"
        case .contactSheet: "rectangle.grid.3x2"
        case .picturePackage: "rectangle.3.group"
        case .customPackage: "square.resize"
        case .cyanotype: "drop.fill"
        case .glassPlate: "rectangle.on.rectangle"
        case .gelatin: "circle.lefthalf.filled"
        }
    }

    private func layoutModeTitle(_ mode: PrintWorkspaceLayoutMode) -> String {
        switch mode {
        case .singleImage: model.text(.printSingleImage)
        case .contactSheet: model.text(.printContactSheet)
        case .picturePackage: model.text(.printPicturePackage)
        case .customPackage: model.text(.printCustomPackage)
        case .cyanotype: model.text(.printCyanotype)
        case .glassPlate: model.text(.printGlassPlate)
        case .gelatin: model.text(.printGelatin)
        }
    }

    private var outputProcessBinding: Binding<PrintOutputProcess> {
        Binding(
            get: { settingsStore.outputProcess },
            set: { process in model.setPrintOutputProcess(process) }
        )
    }

    private var layoutModeBinding: Binding<PrintWorkspaceLayoutMode> {
        Binding(
            get: { settingsStore.layoutMode },
            set: { mode in
                settingsStore.layoutMode = mode
                if mode == .customPackage {
                    settingsStore.prepareDefaultCustomPackage(
                        sourceCount: model.actionableSelectedFrames.count
                    )
                }
            }
        )
    }

    private var cPrintPreviewBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.cPrintPreviewEnabled },
            set: { enabled in model.setCPrintPreviewEnabled(enabled) }
        )
    }

    private var paperSimulationBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.cPrintPaperSimulationEnabled },
            set: { enabled in model.setCPrintPaperSimulationEnabled(enabled) }
        )
    }

    private func paperSurfaceTitle(_ surface: PrintPaperSurface) -> String {
        switch surface {
        case .glossy: model.text(.printSurfaceGlossy)
        case .matte: model.text(.printSurfaceMatte)
        case .lustre: model.text(.printSurfaceLustre)
        case .silk: model.text(.printSurfaceSilk)
        }
    }

    private func chooseCPrintProofProfile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["icc", "icm"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = model.text(AppLocalizedPhrase.choose)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let data = try? Data(contentsOf: url),
                      let colorSpace = SoftProof.rgbOutputColorSpace(fromICCData: data) else {
                    model.statusMessage = model.text(AppLocalizedPhrase.softProofInvalidICC)
                    return
                }
                let localizedName = NSColorSpace(cgColorSpace: colorSpace)?.localizedName
                let fileName = url.deletingPathExtension().lastPathComponent
                let name = localizedName.flatMap { $0.isEmpty ? nil : $0 } ?? fileName
                guard model.setCPrintProofICCProfile(
                    data: data,
                    name: name
                ) else {
                    model.statusMessage = model.text(AppLocalizedPhrase.softProofInvalidICC)
                    return
                }
            }
        }
    }
}
