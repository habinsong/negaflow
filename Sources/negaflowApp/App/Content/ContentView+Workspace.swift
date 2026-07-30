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
                    onOpenDevelop: { selectWorkspaceModule(.develop) }
                )
                .zIndex(0)
            case .develop:
                let layout = WorkspaceAdaptiveLayout(availableWidth: availableWidth)
                HStack(spacing: 0) {
                    if isSidebarVisible {
                        WorkspaceResizablePanel(
                            storedWidth: $sidebarPanelWidth,
                            range: layout.panelWidthRange,
                            edge: .trailing
                        ) {
                            WorkflowSidebar(
                                selectedTab: $selectedSidebarTab,
                                frame: model.actionableFrame
                            )
                        }
                        Divider()
                    }
                    centerPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if isInspectorVisible {
                        Divider()
                        WorkspaceResizablePanel(
                            storedWidth: $inspectorPanelWidth,
                            range: layout.panelWidthRange,
                            edge: .leading
                        ) {
                            WorkspaceInspectorPane(
                                cropMode: { cropModeBinding(for: $0) },
                                brushMode: { brushModeBinding(for: $0) },
                                regionDefectMode: { regionDefectModeBinding(for: $0) },
                                cloneStampMode: { cloneStampModeBinding(for: $0) },
                                basePickerMode: { basePickerModeBinding(for: $0) }
                            )
                        }
                    }
                }
                .zIndex(0)
            case .print:
                printWorkspaceContent(availableWidth: availableWidth)
                    .zIndex(0)
            }
        }
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
