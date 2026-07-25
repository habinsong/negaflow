import SwiftUI
import AppKit
import Chromabase
import ScannerKit
import CoreImage
import UniformTypeIdentifiers

extension ContentView {
    @ViewBuilder
    var workspaceContent: some View {
        GeometryReader { proxy in
            workspaceContent(availableWidth: proxy.size.width)
        }
    }

    @ViewBuilder
    func workspaceContent(availableWidth: CGFloat) -> some View {
        if model.libraryLifecycleState == .blocked {
            LibraryBlockedRecoveryView()
        } else {
            switch selectedWorkspaceModule {
            case .library:
                LibraryWorkspaceView(
                    searchText: $librarySearchText,
                    quickFilters: $libraryQuickFilters,
                    selectedFolderID: $librarySelectedFolderID,
                    organizerSelection: $libraryOrganizerSelection,
                    onOpenDevelop: { selectedWorkspaceModule = .develop }
                )
                .zIndex(0)
            case .develop:
                let layout = WorkspaceAdaptiveLayout(availableWidth: availableWidth)
                let sharedPanelWidth = layout.panelIdealWidth(CGFloat(panelWidth))
                HSplitView {
                    if isSidebarVisible {
                        WorkflowSidebar(
                            selectedTab: $selectedSidebarTab,
                            frame: model.actionableFrame
                        )
                        .frame(
                            minWidth: layout.panelMinimumWidth,
                            idealWidth: sharedPanelWidth,
                            maxWidth: layout.panelIdealMaximumWidth
                        )
                        .reportWorkspacePanelWidth(.sidebar)
                    }
                    centerPane
                        .frame(
                            minWidth: layout.centerMinimumWidth,
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                    if isInspectorVisible {
                        WorkspaceInspectorPane(
                            cropMode: { cropModeBinding(for: $0) },
                            brushMode: { brushModeBinding(for: $0) },
                            regionDefectMode: { regionDefectModeBinding(for: $0) },
                            cloneStampMode: { cloneStampModeBinding(for: $0) },
                            basePickerMode: { basePickerModeBinding(for: $0) }
                        )
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
                .zIndex(0)
            case .print:
                printWorkspaceContent(availableWidth: availableWidth)
                    .zIndex(0)
            }
        }
    }

    func persistWorkspacePanelWidths(
        _ widths: [WorkspacePanelID: CGFloat],
        layout: WorkspaceAdaptiveLayout
    ) {
        guard layout.persistsPanelWidths else { return }
        let currentWidth = CGFloat(panelWidth)
        let changedWidth = [widths[.sidebar], widths[.inspector]]
            .compactMap { $0 }
            .max { abs($0 - currentWidth) < abs($1 - currentWidth) }
        guard let changedWidth, abs(currentWidth - changedWidth) > 0.5 else { return }
        panelWidth = Double(layout.panelIdealWidth(changedWidth))
    }

    func restoreWorkspaceActiveFrameIfReady() {
        guard !didAttemptActiveFrameRestore,
              model.libraryLifecycleState == .ready else { return }
        didAttemptActiveFrameRestore = true
        let availableFrameIDs = Set(model.frames.map(\.id))
        let sourceAvailableFrameIDs = Set(model.frames.compactMap { frame in
            model.isSourceAvailable(frame) ? frame.id : nil
        })
        if let frameID = workspacePresentationStore.restorableActiveFrameID(
            availableFrameIDs: availableFrameIDs,
            sourceAvailableFrameIDs: sourceAvailableFrameIDs
        ) {
            model.selectedFrameID = frameID
        } else if workspacePresentationStore.activeFrameID != nil {
            workspacePresentationStore.discardStaleActiveFrame()
        }
        selectMostRecentDevelopFrameIfNeeded()
    }

    func selectMostRecentDevelopFrameIfNeeded() {
        guard selectedWorkspaceModule == .develop,
              model.libraryLifecycleState == .ready else { return }
        model.selectMostRecentAvailableFrameIfNeeded()
    }


}
