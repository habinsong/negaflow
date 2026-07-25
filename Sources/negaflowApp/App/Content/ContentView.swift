import SwiftUI
import AppKit
import Chromabase
import ScannerKit
import CoreImage
import UniformTypeIdentifiers

// MARK: - ContentView (명시적 3칼럼 — 겹침 없는 순정 레이아웃)
//
// NavigationSplitView 의 .inspector 겹침 버그를 피하기 위해 분리.
// 툴바는 캔버스 위에만. 인스펙터는 오른쪽 독립 패널.
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var localAdjustmentSession: LocalAdjustmentSession
    @Environment(\.undoManager) var undoManager
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @StateObject var workspacePresentationStore: WorkspacePresentationStore
    @AppStorage("workspace.leftPanelVisible") var isSidebarVisible = true
    @AppStorage("workspace.rightPanelVisible") var isInspectorVisible = true
    @AppStorage("workspace.bottomStripVisible") var isFilmstripVisible = true
    @AppStorage("workspace.panelWidth.v2") var panelWidth = Double(WorkspaceAdaptiveLayout.developPanelDefaultWidth)
    @State var showDiagnostics = false
    @State var cropFrameID: UUID?
    @State var brushFrameID: UUID?
    @State var regionDefectFrameID: UUID?
    @State var cloneStampFrameID: UUID?
    @State var basePickerFrameID: UUID?
    @State var selectedSidebarTab: WorkflowSidebarTab
    @State var selectedWorkspaceModule: WorkspaceModule
    @State var selectedPrintSidebarTab = PrintWorkspaceSidebarTab.files
    @State var librarySearchText: String
    @State var libraryQuickFilters = LibraryQuickFilterState()
    @State var librarySelectedFolderID: String?
    @State var libraryOrganizerSelection = LibraryOrganizerSelection.all
    @State var isDropTargeted = false
    @AppStorage("workspace.filmstripSortKey") var filmstripSortKeyRaw = LibrarySortKey.inputOrder.rawValue
    @AppStorage("workspace.filmstripSortAscending") var filmstripSortAscending = true
    @AppStorage("workspace.filmstripHeight") var filmstripHeight = FilmstripSizing.defaultHeight
    @AppStorage("workspace.filmstripItemScale") var filmstripItemScale = 1.0
    @State var didAttemptActiveFrameRestore = false
    let statusBarHeight: CGFloat = 30
    var printWorkspaceStore: PrintWorkspaceSettingsStore { model.printWorkspaceSettingsStore }

    @MainActor
    init() {
        self.init(
            workspacePresentationStore: AppModelFactory.makeWorkspacePresentationStore()
        )
    }

    @MainActor
    init(workspacePresentationStore: WorkspacePresentationStore) {
        _workspacePresentationStore = StateObject(wrappedValue: workspacePresentationStore)
        _selectedSidebarTab = State(initialValue: workspacePresentationStore.sidebarTab)
        _selectedWorkspaceModule = State(initialValue: workspacePresentationStore.module)
        _librarySearchText = State(initialValue: workspacePresentationStore.searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceToolbar(
                isSidebarVisible: $isSidebarVisible,
                isInspectorVisible: $isInspectorVisible,
                isFilmstripVisible: $isFilmstripVisible,
                selectedWorkspaceModule: $selectedWorkspaceModule,
                showDiagnostics: $showDiagnostics
            )
            .zIndex(1)
            Divider()
                .zIndex(1)
            workspaceContent
                .id(selectedWorkspaceModule)
                .transition(reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .move(
                        edge: selectedWorkspaceModule == .library ? .leading : .trailing
                    )))
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selectedWorkspaceModule)
        .transaction { transaction in
            if AppAccessibilityPresentation.disablesAnimations(reduceMotion: reduceMotion) {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("negaflow.main")
        .background(Color(nsColor: .windowBackgroundColor))
        .background(MainWindowChromeConfigurator())
        .ignoresSafeArea(.container, edges: .top)
        .onDrop(
            of: [.fileURL],
            delegate: ExternalFileImportDropDelegate(
                isTargeted: $isDropTargeted,
                handle: { model.handleDrop($0) }
            )
        )
        .onExitCommand(perform: exitActiveDevelopInteraction)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.06))
                    .allowsHitTesting(false)
                    .padding(6)
            }
        }
        .task {
            await model.startApplication()
        }
        .onAppear {
            model.catalogUndoManager = undoManager
            model.activeWorkspaceModule = selectedWorkspaceModule
            synchronizeDevelopInteractionScope()
            model.refreshExternalBackupDestinationStatus()
            restoreWorkspaceActiveFrameIfReady()
        }
        .onChange(of: selectedWorkspaceModule) { _, module in
            workspacePresentationStore.module = module
            model.activeWorkspaceModule = module
            synchronizeDevelopInteractionScope()
            selectMostRecentDevelopFrameIfNeeded()
        }
        .onChange(of: model.activeWorkspaceModule) { _, module in
            guard selectedWorkspaceModule != module else { return }
            withAnimation(.snappy(duration: 0.18)) {
                selectedWorkspaceModule = module
            }
        }
        .onChange(of: model.developToolShortcutRequest) { _, _ in
            handleDevelopToolShortcutRequest()
        }
        .onChange(of: selectedSidebarTab) { _, tab in
            workspacePresentationStore.sidebarTab = tab
        }
        .onChange(of: librarySearchText) { _, searchText in
            workspacePresentationStore.searchText = searchText
        }
        .onChange(of: model.libraryLifecycleState) { _, _ in
            restoreWorkspaceActiveFrameIfReady()
        }
        .onChange(of: model.selectedFrameID) { _, frameID in
            guard didAttemptActiveFrameRestore else { return }
            workspacePresentationStore.recordActiveFrameID(frameID)
        }
        .onChange(of: activeDevelopInteractionScopeFrameIDs) { _, _ in
            synchronizeDevelopInteractionScope()
            selectMostRecentDevelopFrameIfNeeded()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            model.refreshSourceAvailability()
            model.refreshExternalBackupDestinationStatus()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            model.refreshSourceAvailability()
            model.refreshExternalBackupDestinationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshSourceAvailability()
        }
    }

    func exitActiveDevelopInteraction() {
        let activeRegionFrameID = regionDefectFrameID
        withAnimation(.snappy(duration: 0.18)) {
            cropFrameID = nil
            brushFrameID = nil
            regionDefectFrameID = nil
            cloneStampFrameID = nil
            basePickerFrameID = nil
            localAdjustmentSession.deactivate()
        }
        if let activeRegionFrameID,
           let frame = model.frames.first(where: { $0.id == activeRegionFrameID }) {
            model.cancelRegionDefect(frame)
        }
    }


}
