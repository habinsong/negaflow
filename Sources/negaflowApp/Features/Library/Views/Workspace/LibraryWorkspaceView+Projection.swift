import Chromabase
import SwiftUI

extension LibraryWorkspaceView {
    var viewMode: LibraryViewMode {
        LibraryViewMode(rawValue: viewModeRaw) ?? .folders
    }

    var sortKey: LibrarySortKey {
        LibrarySortKey(rawValue: sortKeyRaw) ?? .inputOrder
    }

    var selectedLibraryFilmType: FilmType {
        FilmType(rawValue: filmTypeRaw) ?? .colorNegative
    }

    var currentSortDescriptor: LibrarySortDescriptor {
        LibrarySortDescriptor(key: sortKey, ascending: sortAscending)
    }

    var effectiveSortDescriptor: LibrarySortDescriptor {
        activeStoredDefinition?.sort ?? currentSortDescriptor
    }

    var currentQuickFilterQuery: LibraryQuery {
        quickFilters.query(
            searchText: appliedSearchText,
            offlineSourceMode: viewMode == .offline
        )
    }

    var currentSearchDefinition: LibrarySearchDefinition {
        activeStoredDefinition ?? LibrarySearchDefinition(
            query: currentQuickFilterQuery,
            sort: currentSortDescriptor
        )
    }

    var activeManualCollection: LibraryManualCollection? {
        guard case let .manual(id) = organizerSelection else { return nil }
        let matches = model.manualCollections.filter { $0.id == id }
        return matches.count == 1 ? matches[0] : nil
    }

    var activeStoredDefinition: LibrarySearchDefinition? {
        switch organizerSelection {
        case .all, .manual:
            return nil
        case let .smart(id):
            let matches = model.smartCollections.filter { $0.id == id }
            guard matches.count == 1 else { return nil }
            return matches[0].definition.decodedDefinition()
        case let .savedSearch(id):
            let matches = model.savedSearches.filter { $0.id == id }
            guard matches.count == 1 else { return nil }
            return matches[0].definition.decodedDefinition()
        }
    }

    var organizerTitle: String {
        switch organizerSelection {
        case .all:
            model.text(AppLocalizedPhrase.libraryAllPhotos)
        case let .manual(id):
            model.manualCollections.first(where: { $0.id == id })?.name
                ?? model.text(AppLocalizedPhrase.libraryAllPhotos)
        case let .smart(id):
            model.smartCollections.first(where: { $0.id == id })?.name
                ?? model.text(AppLocalizedPhrase.libraryAllPhotos)
        case let .savedSearch(id):
            model.savedSearches.first(where: { $0.id == id })?.name
                ?? model.text(AppLocalizedPhrase.libraryAllPhotos)
        }
    }

    var organizerSectionHeight: CGFloat {
        let rowCount = 1
            + model.manualCollections.count
            + model.smartCollections.count
            + model.savedSearches.count
        let groupCount = (model.smartCollections.isEmpty ? 0 : 1)
            + (model.savedSearches.isEmpty ? 0 : 1)
        return min(245, max(84, 30 + CGFloat(rowCount * 29 + groupCount * 22)))
    }

    var selectedFrameIDsInInteractionOrder: [UUID] {
        model.interactionFrameIDs.filter { model.selectedFrameIDs.contains($0) }
    }

    var libraryProjection: LibraryBrowserProjection {
        guard let request = LibraryOrganizerProjectionRequest.resolve(
            selection: organizerSelection,
            manualCollections: model.manualCollections,
            smartCollections: model.smartCollections,
            savedSearches: model.savedSearches,
            currentQuery: currentQuickFilterQuery,
            currentSort: currentSortDescriptor
        ) else {
            return model.makeLibraryBrowserProjection(
                query: LibraryQuery(version: LibraryQuery.currentVersion + 1),
                sort: currentSortDescriptor
            )
        }
        let sourceFrameIDs: [UUID]?
        if viewMode == .filmType {
            let candidates = request.sourceFrameIDs ?? model.frames.map(\.id)
            sourceFrameIDs = LibraryPresentation.frameIDs(
                candidates,
                storedUnder: selectedLibraryFilmType,
                framesByID: model.uniqueLibraryFramesByID()
            )
        } else {
            sourceFrameIDs = request.sourceFrameIDs
        }
        let projection = model.makeLibraryBrowserProjection(
            sourceFrameIDs: sourceFrameIDs,
            query: request.query,
            sort: request.sort
        )
        return viewMode == .filmType
            ? projection.restrictingFolderSections(toStoredFilmType: selectedLibraryFilmType)
            : projection
    }

    var hasActiveFilter: Bool {
        organizerSelection != .all
            || quickFilters.isActive
            || !LibrarySearchText.normalize(searchText).isEmpty
    }


}
