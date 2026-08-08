import Chromabase
import SwiftUI

enum LibraryControlsTab: String, CaseIterable, Identifiable {
    case importing
    case files
    case collections

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .importing: "square.and.arrow.down"
        case .files: "folder"
        case .collections: "rectangle.stack"
        }
    }
}

struct LibraryWorkspaceView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("library.viewMode") var viewModeRaw = LibraryViewMode.folders.rawValue
    @AppStorage("library.filmTypeSelection") var filmTypeRaw = FilmType.colorNegative.rawValue
    @AppStorage("library.sortKey") var sortKeyRaw = LibrarySortKey.inputOrder.rawValue
    @AppStorage("library.sortAscending") var sortAscending = true
    @AppStorage("library.cardScale") var cardScale = 1.0
    @AppStorage("library.controlsWidth.v2") var controlsWidth = Double(WorkspaceAdaptiveLayout.libraryControlsDefaultWidth)
    @Binding var searchText: String
    @Binding var quickFilters: LibraryQuickFilterState
    @Binding var selectedFolderID: String?
    @Binding var organizerSelection: LibraryOrganizerSelection
    @State var appliedSearchText = ""
    @State var searchUpdateTask: Task<Void, Never>?
    @State var renameFrame: ScanFrame?
    @State var pendingSourceDeletion: SourceDeletionPlan?
    @State var organizerNameRequest: LibraryOrganizerNameRequest?
    @State var controlsTab = LibraryControlsTab.importing
    @StateObject var folderCollapse = LibraryFolderExpansionStore(
        defaultsKey: LibraryFolderExpansionStore.gridDefaultsKey
    )
    let onOpenDevelop: () -> Void

    var body: some View {
        let projection = libraryProjection
        let scopeFrameIDs = interactionScopeFrameIDs(for: projection)
        let framesByID = model.uniqueLibraryFramesByID()
        GeometryReader { proxy in
            librarySplit(
                projection: projection,
                framesByID: framesByID,
                availableWidth: proxy.size.width
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $renameFrame) { frame in
            FrameRenameSheet(frame: frame)
                .environmentObject(model)
        }
        .sheet(item: $organizerNameRequest) { request in
            LibraryOrganizerNameSheet(
                title: model.text(request.title),
                fieldLabel: model.text(request.fieldLabel),
                initialName: request.initialName
            ) { name in
                applyOrganizerNameRequest(request, name: name)
            }
        }
        .confirmationDialog(
            model.text(AppLocalizedPhrase.deleteSourceConfirmationTitle),
            isPresented: sourceDeletionPresented,
            titleVisibility: .visible,
            presenting: pendingSourceDeletion
        ) { plan in
            Button(role: .destructive) {
                model.deleteSourceFiles(plan)
                pendingSourceDeletion = nil
            } label: {
                Text(model.text(AppLocalizedPhrase.moveSourceToTrash))
                    .foregroundStyle(.red)
            }
            Button(model.text(AppLocalizedPhrase.cancel), role: .cancel) {
                pendingSourceDeletion = nil
            }
        } message: { plan in
            Text(model.text(
                AppLocalizedPhrase.deleteSourceConfirmationMessageFormat,
                plan.frameCount,
                plan.sourceCount,
                plan.firstSourcePath
            ))
        }
        .onAppear {
            reconcileOrganizerSelection()
            appliedSearchText = searchText
            reconcileSelectedFolder(in: projection)
            model.updateInteractionScope(scopeFrameIDs)
        }
        .onChange(of: scopeFrameIDs) { _, frameIDs in
            model.updateInteractionScope(frameIDs)
        }
        .onChange(of: searchText) { _, value in
            scheduleSearchUpdate(value)
        }
        .onChange(of: viewModeRaw) { _, _ in
            reconcileSelectedFolder(in: libraryProjection)
        }
        .onChange(of: filmTypeRaw) { _, _ in
            reconcileSelectedFolder(in: libraryProjection)
        }
        .onChange(of: model.selectedFrameID) { _, selectedFrameID in
            if let selectedFrameID,
               model.interactionFrameIDs.contains(selectedFrameID) {
                return
            }
            reconcileSelectedFolder(in: libraryProjection)
            let currentProjection = libraryProjection
            let currentScopeFrameIDs = interactionScopeFrameIDs(for: currentProjection)
            guard let selectedFrameID,
                  !currentScopeFrameIDs.contains(selectedFrameID) else { return }
            model.reconcileSelection(with: currentScopeFrameIDs)
        }
        .onChange(of: model.manualCollections.map(\.id)) { _, _ in
            reconcileOrganizerSelection()
        }
        .onChange(of: model.smartCollections.map(\.id)) { _, _ in
            reconcileOrganizerSelection()
        }
        .onChange(of: model.savedSearches.map(\.id)) { _, _ in
            reconcileOrganizerSelection()
        }
        .onDisappear {
            searchUpdateTask?.cancel()
        }
    }


}
