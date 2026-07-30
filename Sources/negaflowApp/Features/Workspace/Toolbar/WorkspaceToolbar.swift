import SwiftUI
import AppKit
import Chromabase

enum WorkspaceModule: String, CaseIterable, Identifiable {
    case library
    case develop
    case print

    var id: Self { self }

    var navigationIndex: Int {
        switch self {
        case .library: 0
        case .develop: 1
        case .print: 2
        }
    }
}

enum WorkspaceToolbarLayout {
    static let rightClusterWidth = WorkspaceAdaptiveLayout.developPanelDefaultWidth + 72
    static let rollToolbarMaximumWidth: CGFloat = 420
    static let trailingInset: CGFloat = 10
    static let minimumSeparation: CGFloat = 12

    static func showsPhotoControls(availableWidth: CGFloat) -> Bool {
        let requiredHalfWidth = trailingInset
            + rightClusterWidth
            + minimumSeparation
            + rollToolbarMaximumWidth / 2
        return availableWidth >= requiredHalfWidth * 2
    }
}

struct WorkspaceToolbar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isSidebarVisible: Bool
    @Binding var isInspectorVisible: Bool
    @Binding var isFilmstripVisible: Bool
    @Binding var selectedWorkspaceModule: WorkspaceModule
    @Binding var showDiagnostics: Bool
    /// 전체화면에서는 신호등 버튼이 숨겨지므로 왼쪽 자리를 비워 둘 필요가 없다.
    var isWindowFullScreen: Bool = false
    private let rightPanelToolbarWidth = WorkspaceToolbarLayout.rightClusterWidth

    private var trafficLightReserve: CGFloat { isWindowFullScreen ? 12 : 86 }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                HStack(spacing: 10) {
                    primaryQuickControls

                    if model.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }

                    toolbarBackgroundDoubleClickArea

                    rightToolbarCluster
                }
                .padding(.leading, trafficLightReserve)
                .padding(.trailing, 10)

                if WorkspaceToolbarLayout.showsPhotoControls(availableWidth: proxy.size.width) {
                    centerToolbarContent
                }
            }
        }
        .padding(.vertical, 6)
        .frame(height: 40)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusEffectDisabled()
    }

    private var primaryQuickControls: some View {
        HStack(spacing: 3) {
            if model.hasScanner {
                if model.capabilities?.supportsPreview == true {
                    ToolbarActionButton(
                        systemName: "eye",
                        title: model.text(.commandPreviewScan),
                        help: model.text(.commandPreviewScan),
                        isDisabled: !model.canPreview
                    ) {
                        Task { await model.runScan(preview: true) }
                    }
                    toolbarDivider
                }
                ToolbarActionButton(
                    systemName: "viewfinder",
                    title: model.text(.commandScanFrame),
                    help: model.text(.commandScanFrame),
                    accessibilityIdentifier: "negaflow.scan",
                    isDisabled: !model.canScan
                ) {
                    Task { await model.scanFrames(count: 1, preview: false) }
                }
                toolbarDivider
            }

            WorkspaceExportActions(
                availabilityStore: model.exportAvailabilityStore,
                selectedWorkspaceModule: selectedWorkspaceModule
            )
        }
        .padding(.leading, 1)
        .padding(.trailing, 12)
        .padding(.vertical, 1)
    }

    private var rightToolbarCluster: some View {
        HStack(spacing: 10) {
            workspaceSectionLinks

            Spacer(minLength: 8)

            panelVisibilityControls

            appearancePicker

            utilityMenu
        }
        .frame(width: rightPanelToolbarWidth, alignment: .leading)
    }

    private var workspaceSectionLinks: some View {
        HStack(spacing: 12) {
            WorkspaceTextButton(
                title: model.text(.menuLibrary),
                isSelected: selectedWorkspaceModule == .library,
                accessibilityIdentifier: "negaflow.workspace.library"
            ) {
                withAnimation(.snappy(duration: 0.14)) {
                    selectedWorkspaceModule = .library
                }
            }

            toolbarDivider

            WorkspaceTextButton(
                title: model.text(.menuDevelop),
                isSelected: selectedWorkspaceModule == .develop,
                accessibilityIdentifier: "negaflow.workspace.develop"
            ) {
                withAnimation(.snappy(duration: 0.14)) {
                    selectedWorkspaceModule = .develop
                }
            }

            toolbarDivider

            WorkspaceTextButton(
                title: model.text(.menuPrint),
                isSelected: selectedWorkspaceModule == .print,
                accessibilityIdentifier: "negaflow.workspace.print"
            ) {
                withAnimation(.snappy(duration: 0.14)) {
                    selectedWorkspaceModule = .print
                }
            }
        }
        .frame(width: 266)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.42))
            .frame(width: 1, height: 14)
            .frame(width: 9)
    }

    private var toolbarBackgroundDoubleClickArea: some View {
        Color.clear
            .frame(minWidth: 12, maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                NSApp.keyWindow?.performZoom(nil)
            }
    }

    @ViewBuilder
    private var centerToolbarContent: some View {
        if let frame = model.actionableFrame {
            RollToolbarStrip(frame: frame)
        }
    }

    private var panelVisibilityControls: some View {
        HStack(spacing: 2) {
            PanelToggleButton(
                systemName: "sidebar.left",
                isOn: isSidebarVisible,
                help: model.text(.commandShowHideSidebar),
                accessibilityIdentifier: "negaflow.panel.sidebar"
            ) {
                withAnimation(.snappy(duration: 0.18)) { isSidebarVisible.toggle() }
            }

            PanelToggleButton(
                systemName: "rectangle.bottomthird.inset.filled",
                isOn: isFilmstripVisible,
                help: model.text(.commandShowHideFilmstrip),
                accessibilityIdentifier: "negaflow.panel.filmstrip"
            ) {
                withAnimation(.snappy(duration: 0.18)) { isFilmstripVisible.toggle() }
            }

            PanelToggleButton(
                systemName: "sidebar.right",
                isOn: isInspectorVisible,
                help: model.text(.commandShowHideInspector),
                accessibilityIdentifier: "negaflow.panel.inspector"
            ) {
                withAnimation(.snappy(duration: 0.18)) { isInspectorVisible.toggle() }
            }
        }
        .padding(1)
        .adaptiveRoundedSurface(cornerRadius: 7, material: .regular)
        .help(model.text(.menuView))
    }

    private var appearancePicker: some View {
        Menu {
            ForEach(AppAppearanceMode.allCases) { mode in
                Button {
                    model.appearanceMode = mode
                } label: {
                    Label(appearanceName(mode), systemImage: mode.systemImage)
                }
            }
        } label: {
            Image(systemName: model.appearanceMode.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .help(model.text(.settingsAppearancePicker))
        .accessibilityLabel(model.text(.settingsAppearancePicker))
    }

    private func appearanceName(_ mode: AppAppearanceMode) -> String {
        switch mode {
        case .system: return model.text(.appearanceSystem)
        case .dark: return model.text(.appearanceDark)
        case .light: return model.text(.appearanceLight)
        }
    }

    private var utilityMenu: some View {
        Menu {
            Button {
                Task { await model.refreshDevices() }
            } label: {
                Label(model.text(.commandDetectScanners), systemImage: "arrow.clockwise")
            }
            .disabled(model.isDetecting || model.isScanning)

            Toggle(isOn: Binding(get: { model.demoMode }, set: { model.toggleDemo($0) })) {
                Label(model.text(.commandToggleScannerSimulator), systemImage: "scanner")
            }

            Divider()

            Button {
                Task { await model.runDiagnostics() }
                showDiagnostics = true
            } label: {
                Label(model.text(.commandDiagnostics), systemImage: "waveform.path.ecg")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .help(model.text(.commandWorkspaceOptions))
        .accessibilityLabel(model.text(.commandWorkspaceOptions))
        .popover(isPresented: $showDiagnostics) {
            DiagnosticsReportView(center: model.diagnosticsCenter)
                .environmentObject(model)
        }
    }
}

private struct WorkspaceExportActions: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var availabilityStore: ExportAvailabilityStore
    let selectedWorkspaceModule: WorkspaceModule

    var body: some View {
        ToolbarActionButton(
            systemName: "bolt.badge.checkmark",
            title: model.text(.commandQuickExport),
            help: model.text(
                AppLocalizedPhrase.quickExportHelpFormat,
                model.text(.commandQuickExport),
                model.quickExportFormat.uiLabel,
                model.quickExportDPI,
                model.quickExportFolderDisplay
            ),
            accessibilityIdentifier: "negaflow.quick-export",
            isDisabled: !model.canQuickExportSelection(for: selectedWorkspaceModule)
        ) {
            model.quickExportSelection(for: selectedWorkspaceModule)
        }

        Rectangle()
            .fill(Color.secondary.opacity(0.42))
            .frame(width: 1, height: 14)
            .frame(width: 9)

        ToolbarActionButton(
            systemName: "square.and.arrow.up",
            title: model.text(.commandExport),
            help: model.text(.commandExport),
            accessibilityIdentifier: "negaflow.export",
            isDisabled: !model.canExportSelection(for: selectedWorkspaceModule)
        ) {
            model.exportSelectionToFolder(for: selectedWorkspaceModule)
        }
    }
}
