import SwiftUI
import AppKit
import Chromabase

private enum ExportDetailPage: String, CaseIterable, Identifiable {
    case file
    case quality
    case source

    var id: Self { self }
}

struct ExportSection: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedDetailPage = ExportDetailPage.file
    var usesPaperLayout = false
    var usesCompositeLayout = false
    var onExport: (() -> Void)?
    var onQuickExport: (() -> Void)?

    private let dpiOptions: [Int] = [0, 72, 150, 240, 300, 600]
    private let longEdgeOptions: [Int] = [0, 1024, 2048, 4096, 6000]
    private let quickDPIOptions: [Int] = [0, 72, 150, 240, 300, 600]

    var body: some View {
        Section {
            exportDetailTabs
            ExportRecipeControls()
            exportSelectedSettings

            if model.actionableFrame != nil {
                ExportActionPill(
                    title: exportButtonTitle(model.text(.commandExport)),
                    systemImage: "square.and.arrow.up",
                    revealHelp: model.text(AppLocalizedPhrase.showInFinder),
                    isProminent: true,
                    isActionEnabled: usesPaperLayout
                        ? model.canExportPrintSelection
                        : model.canExportSelection,
                    action: { (onExport ?? model.exportSelectionToFolder)() },
                    reveal: { revealExportFolder(root: model.exportFolderURL) }
                )
                .controlSize(.large)
            }
        } header: {
            sectionHeader(model.text(.exportSection), systemImage: "square.and.arrow.up")
        }

        Section {
            Picker(model.text(.exportFormatLabel), selection: $model.quickExportFormat) {
                Text("JPEG").tag(ExportFormat.jpeg)
                Text("PNG").tag(ExportFormat.png)
            }

            Picker(model.text(.exportDPILabel), selection: quickDPIBinding) {
                ForEach(availableQuickDPIOptions, id: \.self) { dpi in
                    Text(dpi == 0 ? model.text(.settingsSourceDPI) : "\(dpi) dpi").tag(dpi)
                }
            }

            if !usesPaperLayout {
                Picker(model.text(.exportSizeLabel), selection: $model.quickExportLongEdge) {
                    ForEach(longEdgeOptions, id: \.self) { edge in
                        Text(edge == 0 ? model.text(.exportFullSize) : "\(edge) \(model.text(.exportLongEdgeSuffix))").tag(edge)
                    }
                }
            }

            quickExportEncodingOptions

            quickExportFolderRow

            if let filename = model.quickExportNamingPreview() {
                LabeledContent(exportNamingText(.filename)) {
                    Text(filename)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if model.actionableFrame != nil {
                ExportActionPill(
                    title: exportButtonTitle(model.text(.commandQuickExport)),
                    systemImage: "bolt",
                    revealHelp: model.text(AppLocalizedPhrase.showInFinder),
                    isActionEnabled: usesPaperLayout
                        ? model.canQuickExportPrintSelection
                        : model.canQuickExportSelection,
                    action: { (onQuickExport ?? model.quickExportSelection)() },
                    reveal: { revealExportFolder(root: model.quickExportFolderURL) }
                )
                .controlSize(.large)
            }
        } header: {
            sectionHeader(model.text(.quickExportSection), systemImage: "bolt")
        }

        if !model.exportBatchStore.items.isEmpty || model.isPrintPackageExporting {
            Section {
                ExportBatchProgressView(store: model.exportBatchStore)
                if let progress = model.printPackageExportProgress {
                    PrintPackageExportProgressView(progress: progress)
                }
            }
        }
    }

    private var exportDetailTabs: some View {
        HStack(spacing: 0) {
            ForEach(exportDetailPages) { page in
                let isSelected = selectedDetailPage == page
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selectedDetailPage = page
                    }
                } label: {
                    Text(exportDetailTitle(page))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(AppTypography.minimumScaleFactor)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .padding(.horizontal, 6)
                        .background {
                            if isSelected {
                                Color.clear
                                    .liquidSurface(cornerRadius: 15, interactive: true)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(exportDetailTitle(page))
                .accessibilitySelectionState(
                    isSelected,
                    selectedValue: model.accessibilityText(.selected),
                    unselectedValue: model.accessibilityText(.notSelected),
                    unselectedHint: model.accessibilityText(.select)
                )
            }
        }
        .padding(3)
        .liquidSurface(cornerRadius: 18, interactive: true)
        .onChange(of: usesCompositeLayout) { _, isComposite in
            if isComposite && selectedDetailPage == .source { selectedDetailPage = .file }
        }
    }

    private var exportDetailPages: [ExportDetailPage] {
        usesCompositeLayout ? [.file, .quality] : ExportDetailPage.allCases
    }

    private func exportDetailTitle(_ page: ExportDetailPage) -> String {
        switch page {
        case .file: model.text(AppLocalizedPhrase.exportFileSettings)
        case .quality: model.text(AppLocalizedPhrase.exportQualitySettings)
        case .source: model.text(AppLocalizedPhrase.exportSourceSettings)
        }
    }

    @ViewBuilder
    private var exportSelectedSettings: some View {
        switch selectedDetailPage {
        case .file:
            Picker(model.text(.exportFormatLabel), selection: $model.exportFormat) {
                Text("JPEG").tag(ExportFormat.jpeg)
                Text("PNG").tag(ExportFormat.png)
                Text(verbatim: "TIFF").tag(ExportFormat.tiff16)
            }
            exportFolderRow
            ExportNamingControls()
        case .quality:
            ExportFormatOptionsView()

            Picker(model.text(.exportDPILabel), selection: exportDPIBinding) {
                ForEach(availableDPIOptions, id: \.self) { dpi in
                    Text(dpi == 0 ? model.text(.settingsSourceDPI) : "\(dpi) dpi").tag(dpi)
                }
            }

            if !usesPaperLayout {
                Picker(model.text(.exportSizeLabel), selection: $model.exportLongEdge) {
                    ForEach(longEdgeOptions, id: \.self) { edge in
                        Text(edge == 0 ? model.text(.exportFullSize) : "\(edge) \(model.text(.exportLongEdgeSuffix))").tag(edge)
                    }
                }
            }

            OutputSharpeningOptionsView()
        case .source:
            ExportMetadataPolicyView()

            Toggle(model.text(AppLocalizedPhrase.exportMainFlatMaster), isOn: $model.exportWriteMainFlatMaster)
                .help(model.text(.exportMainFlatMasterHelp))

            Toggle(model.text(AppLocalizedPhrase.exportOriginalRawTIFF), isOn: $model.exportWriteOriginalRaw)
                .help(model.text(.exportOriginalRawHelp))

            Toggle(model.text(AppLocalizedPhrase.exportSidecar), isOn: $model.exportWriteSidecar)
                .help(model.text(.exportSidecarHelp))

            if let frame = model.actionableFrame {
                LabeledContent(model.text(.exportSourceLabel)) {
                    Text(frame.sourceSummary(language: model.appLanguage))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var availableDPIOptions: [Int] {
        usesPaperLayout ? dpiOptions.filter { $0 > 0 } : dpiOptions
    }

    private var availableQuickDPIOptions: [Int] {
        usesPaperLayout ? quickDPIOptions.filter { $0 > 0 } : quickDPIOptions
    }

    private var exportDPIBinding: Binding<Int> {
        Binding(
            get: { usesPaperLayout && model.exportDPI == 0 ? 300 : model.exportDPI },
            set: { model.exportDPI = $0 }
        )
    }

    private var quickDPIBinding: Binding<Int> {
        Binding(
            get: { usesPaperLayout && model.quickExportDPI == 0 ? 300 : model.quickExportDPI },
            set: { model.quickExportDPI = $0 }
        )
    }

    private var exportFolderRow: some View {
        LabeledContent(model.text(.exportFolderLabel)) {
            HStack(spacing: 6) {
                Text(model.exportFolderDisplay)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    chooseExportFolder()
                } label: {
                    Text(model.text(.exportChangeFolder))
                }
                .controlSize(.small)
            }
        }
    }

    /// 빠른 내보내기의 인코딩 옵션. 포맷별로 화질을 정하는 값만 노출한다 —
    /// JPEG 는 품질, PNG 는 비트 심도다.
    @ViewBuilder
    private var quickExportEncodingOptions: some View {
        switch model.quickExportFormat {
        case .jpeg:
            LabeledContent(exportEncodingText(.jpegQuality)) {
                HStack(spacing: 8) {
                    Slider(value: $model.quickExportJPEGQuality, in: 0...1, step: 0.01)
                    Text(verbatim: "\(Int((model.quickExportJPEGQuality * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        case .png:
            Picker(exportEncodingText(.pngBitDepth), selection: $model.quickExportPNGBitDepth) {
                Text(verbatim: "8-bit").tag(ExportBitDepth.eight)
                Text(verbatim: "16-bit").tag(ExportBitDepth.sixteen)
            }
            .pickerStyle(.segmented)
        case .tiff16, .rawScanTIFF:
            EmptyView()
        }
    }

    private var quickExportFolderRow: some View {
        LabeledContent(model.text(.exportFolderLabel)) {
            HStack(spacing: 6) {
                Text(model.quickExportFolderDisplay)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    chooseQuickExportFolder()
                } label: {
                    Text(model.text(.exportChangeFolder))
                }
                .controlSize(.small)
            }
        }
    }

    private func exportButtonTitle(_ title: String) -> String {
        let count = usesPaperLayout
            ? model.printExportOutputCount
            : model.exportSelection.count
        return usesCompositeLayout || count > 1
            ? "\(title) (\(count))"
            : title
    }

    /// 사진이 실제로 저장되는 세부 폴더(`<루트>/<날짜>/<출처 폴더>`)를 Finder 로 연다.
    private func revealExportFolder(root: URL) {
        NSWorkspace.shared.open(
            ExportRevealLocator.folder(
                root: root,
                group: model.actionableFrame.map { model.exportStorageGroupName(for: $0) }
            )
        )
    }

    private func chooseQuickExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = model.text(AppLocalizedPhrase.choose)
        panel.directoryURL = model.quickExportFolderURL
        presentFolderPanel(panel) { model.quickExportFolderPath = $0.path }
    }

    private func exportNamingText(_ text: ExportNamingLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }

    private func exportEncodingText(_ text: ExportEncodingLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }

    private func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = model.text(AppLocalizedPhrase.choose)
        panel.directoryURL = model.exportFolderURL
        presentFolderPanel(panel) { model.exportFolderPath = $0.path }
    }

    private func presentFolderPanel(_ panel: NSOpenPanel, onChoose: @escaping (URL) -> Void) {
        panel.canCreateDirectories = true
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                onChoose(url)
            }
        }
    }
}
