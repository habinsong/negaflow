import SwiftUI

extension ContentView {
    @ViewBuilder
    func printWorkspaceContent(availableWidth: CGFloat) -> some View {
        let layout = WorkspaceAdaptiveLayout(availableWidth: availableWidth)
        HStack(spacing: 0) {
            if isSidebarVisible {
                WorkspaceResizablePanel(
                    storedWidth: $sidebarPanelWidth,
                    range: layout.panelWidthRange,
                    edge: .trailing
                ) {
                    PrintWorkspaceSidebar(
                        settingsStore: printWorkspaceStore,
                        selectedTab: $selectedPrintSidebarTab,
                        selectedFolderID: $librarySelectedFolderID
                    )
                }
                Divider()
            }

            printCenterPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isInspectorVisible {
                Divider()
                WorkspaceResizablePanel(
                    storedWidth: $inspectorPanelWidth,
                    range: layout.panelWidthRange,
                    edge: .leading
                ) {
                    PrintWorkspaceInspector(settingsStore: printWorkspaceStore)
                }
            }
        }
    }

    private var printCenterPane: some View {
        VStack(spacing: 0) {
            if let frame = model.actionableFrame {
                // 선택을 넓힐 때마다 활성 사진이 바뀐다. 여기에 .id(frame.id) 를 걸면 시트가
                // 통째로 다시 만들어져 방금 추가한 사진이 붙기 전에 화면이 초기화된다.
                PrintCanvasView(
                    settingsStore: printWorkspaceStore,
                    activeFrame: frame,
                    frames: model.actionableSelectedFrames.isEmpty
                        ? [frame]
                        : model.actionableSelectedFrames
                )
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
