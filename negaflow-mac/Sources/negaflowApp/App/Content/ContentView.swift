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
    // 좌측탭/우측탭 폭은 각각 따로 기억한다 — 한쪽을 끌었다고 반대쪽이 따라 움직이지 않는다.
    @AppStorage("workspace.sidebarWidth.v3") var sidebarPanelWidth
        = Double(WorkspaceAdaptiveLayout.developPanelDefaultWidth)
    @AppStorage("workspace.inspectorWidth.v3") var inspectorPanelWidth
        = Double(WorkspaceAdaptiveLayout.developPanelDefaultWidth)
    @State var showDiagnostics = false
    @State var isWindowFullScreen = false
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
    @State var workspaceTransitionTask: Task<Void, Never>?
    @State private var workspaceTransitionMovesForward = true
    @AppStorage("workspace.filmstripSortKey") var filmstripSortKeyRaw = LibrarySortKey.inputOrder.rawValue
    @AppStorage("workspace.filmstripSortAscending") var filmstripSortAscending = true
    @AppStorage("workspace.filmstripScope") var filmstripScopeRaw = FilmstripScope.folder.rawValue
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
                selectedWorkspaceModule: workspaceModuleBinding,
                showDiagnostics: $showDiagnostics,
                isWindowFullScreen: isWindowFullScreen
            )
            .zIndex(1)
            Divider()
                .zIndex(1)
            // **`.id(module)` 를 걸지 않는다.** 그 한 줄이 모듈을 바꿀 때마다 바깥 컨테이너
            // 전체를 새로 만들게 해서, 라이브러리로 돌아올 때 카드까지 전부 다시 세웠다
            // (실측: 전환 4.5초, 카드 250장 재생성). 안쪽 `switch` 의 가지들은 이미 서로 다른
            // 정체성을 가지므로, 전환 효과는 가지에 직접 달아 준다.
            workspaceContent
                // 진단은 창 안 오른쪽에 세로로 꽉 채워 얹는다. 팝오버로 띄우면 여는 단추가
                // 도구막대 오른쪽 끝이라 창 밖으로 나가 잘렸다.
                .overlay(alignment: .trailing) {
                    if showDiagnostics {
                        DiagnosticsReportView(
                            center: model.diagnosticsCenter,
                            onClose: { showDiagnostics = false }
                        )
                        .environmentObject(model)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(2)
                    }
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: showDiagnostics)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.14), value: selectedWorkspaceModule)
        .transaction { transaction in
            if AppAccessibilityPresentation.disablesAnimations(reduceMotion: reduceMotion) {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("negaflow.main")
        .background(Color(nsColor: .windowBackgroundColor))
        .background(MainWindowChromeConfigurator(isFullScreen: $isWindowFullScreen))
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
        .onChange(of: selectedWorkspaceModule) { previousModule, module in
            workspacePresentationStore.module = module
            model.activeWorkspaceModule = module
            if module == .develop {
                model.handleSelectedFrameChange(from: nil)
            }
            scheduleWorkspaceTransitionCompletion(
                from: previousModule,
                to: module
            )
        }
        .onChange(of: model.activeWorkspaceModule) { _, module in
            guard selectedWorkspaceModule != module else { return }
            withAnimation(.snappy(duration: 0.14)) {
                selectWorkspaceModule(module)
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
            // 범위가 활성 사진 기준이라 사진이 바뀌면 보여줄 목록도 다시 맞춘다.
            if bottomFilmstripScope != .all {
                synchronizeDevelopInteractionScope()
            }
            guard didAttemptActiveFrameRestore else { return }
            workspacePresentationStore.recordActiveFrameID(frameID)
        }
        .onChange(of: model.frames.map(\.id)) { _, _ in
            synchronizeDevelopInteractionScope()
            selectMostRecentDevelopFrameIfNeeded()
        }
        .onChange(of: filmstripSortKeyRaw) { _, _ in
            synchronizeDevelopInteractionScope()
            selectMostRecentDevelopFrameIfNeeded()
        }
        .onChange(of: filmstripSortAscending) { _, _ in
            synchronizeDevelopInteractionScope()
            selectMostRecentDevelopFrameIfNeeded()
        }
        .onChange(of: filmstripScopeRaw) { _, _ in
            synchronizeDevelopInteractionScope()
            selectMostRecentDevelopFrameIfNeeded()
        }
        .onDisappear {
            workspaceTransitionTask?.cancel()
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

    func scheduleWorkspaceTransitionCompletion(
        from previousModule: WorkspaceModule,
        to module: WorkspaceModule
    ) {
        workspaceTransitionTask?.cancel()
        workspaceTransitionTask = Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(140))
            }
            guard !Task.isCancelled,
                  selectedWorkspaceModule == module,
                  module == .develop || module == .print else { return }
            if previousModule == .library {
                synchronizeDevelopInteractionScope()
            }
            selectMostRecentDevelopFrameIfNeeded()
            model.refreshWorkspaceSoftProofPreviewIfNeeded()
        }
    }

    var workspaceModuleBinding: Binding<WorkspaceModule> {
        Binding(
            get: { selectedWorkspaceModule },
            set: { selectWorkspaceModule($0) }
        )
    }

    var workspaceModuleTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertionEdge: Edge = workspaceTransitionMovesForward ? .trailing : .leading
        let removalEdge: Edge = workspaceTransitionMovesForward ? .leading : .trailing
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: insertionEdge)),
            removal: .opacity.combined(with: .move(edge: removalEdge))
        )
    }

    func selectWorkspaceModule(_ module: WorkspaceModule) {
        guard module != selectedWorkspaceModule else { return }
        workspaceTransitionMovesForward =
            module.navigationIndex > selectedWorkspaceModule.navigationIndex
        selectedWorkspaceModule = module
    }

}

