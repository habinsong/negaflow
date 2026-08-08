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

    /// 격자의 열. **`.adaptive` 를 쓰지 않는다.**
    ///
    /// `.adaptive` 는 열 수를 SwiftUI 가 정하므로, 항목 수가 바뀔 때마다 그 계산을 다시 한다.
    /// 실측(GT-X900 라이브러리, 폴더 14개·그중 한 폴더 100장, 폴더 접기/펼치기): `.adaptive`
    /// 에서는 토글 한 번에 카드 뷰 131개가 만들어지고 48ms 가 걸렸다. 열 수를 우리가 정해서
    /// 넘기면 같은 동작이 카드 68개, 25~33ms 로 떨어진다 — 화면에 보이는 카드는 열 두 줄
    /// 남짓뿐인데 `.adaptive` 가 그 두 배를 실체화하고 있었다.
    ///
    /// 폭 계산은 `.adaptive(minimum: w, maximum: w + 22)` 와 같은 규칙을 그대로 쓰므로 열
    /// 개수와 카드 폭은 이전과 같다.
    func gridColumns(contentWidth: CGFloat) -> [GridItem] {
        let minimum = cardSize.width
        let maximum = minimum + 22
        let usable = max(minimum, contentWidth)
        let count = max(1, Int((usable + gridSpacing) / (minimum + gridSpacing)))
        return Array(
            repeating: GridItem(
                .flexible(minimum: minimum, maximum: maximum),
                spacing: gridSpacing,
                alignment: .top
            ),
            count: count
        )
    }

    var sourceDeletionPresented: Binding<Bool> {
        Binding(
            get: { pendingSourceDeletion != nil },
            set: { if !$0 { pendingSourceDeletion = nil } }
        )
    }

}
