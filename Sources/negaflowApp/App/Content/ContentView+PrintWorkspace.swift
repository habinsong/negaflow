import SwiftUI

extension ContentView {
    @ViewBuilder
    func printWorkspaceContent(availableWidth: CGFloat) -> some View {
        let layout = WorkspaceAdaptiveLayout(availableWidth: availableWidth)
        let sharedPanelWidth = layout.panelIdealWidth(CGFloat(panelWidth))
        HSplitView {
            if isSidebarVisible {
                PrintWorkspaceSidebar(
                    settingsStore: printWorkspaceStore,
                    selectedTab: $selectedPrintSidebarTab,
                    selectedFolderID: $librarySelectedFolderID
                )
                .frame(
                    minWidth: layout.panelMinimumWidth,
                    idealWidth: sharedPanelWidth,
                    maxWidth: layout.panelIdealMaximumWidth
                )
                .reportWorkspacePanelWidth(.sidebar)
            }

            printCenterPane
                .frame(
                    minWidth: layout.centerMinimumWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )

            if isInspectorVisible {
                PrintWorkspaceInspector(settingsStore: printWorkspaceStore)
                    .frame(
                        minWidth: layout.panelMinimumWidth,
                        idealWidth: sharedPanelWidth,
                        maxWidth: layout.panelIdealMaximumWidth
                    )
                    .reportWorkspacePanelWidth(.inspector)
            }
        }
        .onPreferenceChange(WorkspacePanelWidthPreferenceKey.self) { widths in
            persistWorkspacePanelWidths(widths, layout: layout)
        }
    }

    private var printCenterPane: some View {
        VStack(spacing: 0) {
            if let frame = model.actionableFrame {
                PrintCanvasView(
                    settingsStore: printWorkspaceStore,
                    activeFrame: frame,
                    frames: model.actionableSelectedFrames.isEmpty
                        ? [frame]
                        : model.actionableSelectedFrames
                )
                    .id(frame.id)
            } else {
                ContentUnavailableView(model.text(.noFrame), systemImage: "printer")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.secondary)
                    .background(model.canvasBackground.color)
            }

            if isFilmstripVisible {
                WorkspaceFilmstrip()
            }
            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
