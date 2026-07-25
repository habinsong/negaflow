import SwiftUI

enum LibraryGridCardLayout {
    static let thumbnailAspectRatio: CGFloat = 3.0 / 2.0
    static let thumbnailTitleSpacing: CGFloat = 3
    static let ratingControlHeight: CGFloat = 14
}

extension LibraryWorkspaceView {
    func scheduleSearchUpdate(_ value: String) {
        searchUpdateTask?.cancel()
        if LibrarySearchText.normalize(value).isEmpty {
            appliedSearchText = ""
            return
        }
        searchUpdateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(75))
            guard !Task.isCancelled else { return }
            appliedSearchText = value
        }
    }

    func clearSearch() {
        searchUpdateTask?.cancel()
        searchText = ""
        appliedSearchText = ""
    }

    func clearAllFilters() {
        clearSearch()
        quickFilters.clear()
        selectOrganizer(.all)
    }

    func selectOrganizer(_ selection: LibraryOrganizerSelection) {
        organizerSelection = selection
        switch selection {
        case .smart, .savedSearch:
            viewModeRaw = LibraryViewMode.all.rawValue
            selectedFolderID = nil
        case .all, .manual:
            break
        }
    }

    func reconcileOrganizerSelection() {
        let isValid: Bool
        switch organizerSelection {
        case .all:
            isValid = true
        case let .manual(id):
            isValid = model.manualCollections.filter { $0.id == id }.count == 1
        case let .smart(id):
            let matches = model.smartCollections.filter { $0.id == id }
            isValid = matches.count == 1 && matches[0].definition.decodedDefinition() != nil
        case let .savedSearch(id):
            let matches = model.savedSearches.filter { $0.id == id }
            isValid = matches.count == 1 && matches[0].definition.decodedDefinition() != nil
        }
        if !isValid { organizerSelection = .all }
    }

    func reconcileSelectedFolder(in projection: LibraryBrowserProjection) {
        guard viewMode.groupsByFolder else { return }
        if let selectedFolderID,
           projection.folderSections.contains(where: { $0.id == selectedFolderID }) {
            return
        }
        selectedFolderID = LibraryBrowserInteractionScope.folderID(
            containing: model.selectedFrameID,
            projection: projection
        )
    }

    func applyOrganizerNameRequest(
        _ request: LibraryOrganizerNameRequest,
        name: String
    ) {
        switch request.action {
        case let .createManual(frameIDs):
            if let id = model.createManualCollection(named: name, frameIDs: frameIDs) {
                selectOrganizer(.manual(id))
            }
        case let .createSmart(definition):
            if let id = model.createSmartCollection(named: name, definition: definition) {
                selectOrganizer(.smart(id))
            }
        case let .createSavedSearch(definition):
            if let id = model.createSavedSearch(named: name, definition: definition) {
                selectOrganizer(.savedSearch(id))
            }
        case let .renameManual(id):
            _ = model.renameManualCollection(id: id, to: name)
        case let .renameSmart(id):
            _ = model.renameSmartCollection(id: id, to: name)
        case let .renameSavedSearch(id):
            _ = model.renameSavedSearch(id: id, to: name)
        case let .renameFolder(url):
            model.renameLibraryFolder(at: url, to: name)
        }
    }

    func interactionScopeFrameIDs(
        for projection: LibraryBrowserProjection
    ) -> [UUID] {
        model.stackProjectedFrameIDs(LibraryBrowserInteractionScope.frameIDs(
            viewMode: viewMode,
            selectedFolderID: selectedFolderID,
            selectedFrameID: model.selectedFrameID,
            projection: projection
        ))
    }

    func frames(
        orderedBy frameIDs: [UUID],
        framesByID: [UUID: ScanFrame]
    ) -> [ScanFrame] {
        model.stackProjectedFrameIDs(frameIDs).compactMap { framesByID[$0] }
    }

    var cardSize: CGSize {
        let width = 190 * CGFloat(cardScale)
        let thumbnailHeight = (width - 16) / LibraryGridCardLayout.thumbnailAspectRatio
        let metadataHeight = 15
            + LibraryGridCardLayout.thumbnailTitleSpacing
            + LibraryGridCardLayout.ratingControlHeight
        return CGSize(
            width: width,
            height: thumbnailHeight + metadataHeight + 16
        )
    }

    var gridSpacing: CGFloat {
        max(10, 14 * CGFloat(cardScale))
    }

    var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardSize.width, maximum: cardSize.width + 22), spacing: gridSpacing, alignment: .top)]
    }

    var sourceDeletionPresented: Binding<Bool> {
        Binding(
            get: { pendingSourceDeletion != nil },
            set: { if !$0 { pendingSourceDeletion = nil } }
        )
    }

}
