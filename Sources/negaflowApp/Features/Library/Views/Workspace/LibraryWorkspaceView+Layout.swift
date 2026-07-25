import SwiftUI

extension LibraryWorkspaceView {
    func librarySplit(
        projection: LibraryBrowserProjection,
        framesByID: [UUID: ScanFrame],
        availableWidth: CGFloat
    ) -> some View {
        let layout = WorkspaceAdaptiveLayout(availableWidth: availableWidth)
        return HStack(spacing: 0) {
            WorkspaceResizablePanel(
                storedWidth: $controlsWidth,
                range: layout.libraryControlsWidthRange,
                edge: .trailing
            ) {
                libraryControls(projection: projection)
            }

            Divider()

            libraryBrowser(projection: projection, framesByID: framesByID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func libraryControls(projection: LibraryBrowserProjection) -> some View {
        HStack(spacing: 0) {
            libraryControlsTabRail

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: controlsTab.systemImage)
                        .frame(width: 16)
                    Text(libraryControlsTabTitle(controlsTab))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(model.text(AppLocalizedPhrase.frameCountFormat, model.frames.count))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 9)

                Divider()

                libraryControlsTabContent(projection: projection)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaptivePanelSurface(.regular)
        .clipped()
    }

    @ViewBuilder
    func libraryControlsTabContent(projection: LibraryBrowserProjection) -> some View {
        switch controlsTab {
        case .importing:
            LibrarySourceSection(
                content: .importing,
                showsDevelopDefaults: false,
                orderedResultFrameIDs: projection.orderedFrameIDs,
                selectedFolderID: $selectedFolderID
            )
        case .files:
            LibrarySourceSection(
                content: .files,
                showsDevelopDefaults: false,
                orderedResultFrameIDs: projection.orderedFrameIDs,
                selectedFolderID: $selectedFolderID
            )
        case .collections:
            LibraryOrganizerSection(
                selection: $organizerSelection,
                nameRequest: $organizerNameRequest,
                currentSearchDefinition: currentSearchDefinition,
                selectedFrameIDs: selectedFrameIDsInInteractionOrder,
                sectionHeight: organizerSectionHeight,
                onSelect: selectOrganizer
            )
        }
    }

    var libraryControlsTabRail: some View {
        VStack(spacing: 7) {
            ForEach(LibraryControlsTab.allCases) { tab in
                LibraryControlsTabButton(
                    tab: tab,
                    title: libraryControlsTabTitle(tab),
                    isSelected: controlsTab == tab,
                    action: {
                        withAnimation(.snappy(duration: 0.18)) {
                            controlsTab = tab
                        }
                    }
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(.horizontal, 7)
        .frame(width: 76)
        .frame(maxHeight: .infinity)
        .adaptivePanelSurface(.bar)
    }

    func libraryControlsTabTitle(_ tab: LibraryControlsTab) -> String {
        switch tab {
        case .importing:
            model.text(.importSection)
        case .files:
            model.text(AppLocalizedPhrase.libraryFiles)
        case .collections:
            model.text(AppLocalizedPhrase.libraryCollections)
        }
    }

    func libraryBrowser(
        projection: LibraryBrowserProjection,
        framesByID: [UUID: ScanFrame]
    ) -> some View {
        VStack(spacing: 0) {
            browserHeader(projection: projection)
            Divider()
            Group {
                if model.libraryCullingMode != .grid {
                    LibraryCullingContent(
                        mode: model.libraryCullingMode,
                        orderedFrameIDs: projection.orderedFrameIDs
                    )
                } else if viewMode.groupsByFolder, !projection.folderSections.isEmpty {
                    libraryGrid(projection: projection, framesByID: framesByID)
                } else if model.frames.isEmpty {
                    emptyLibrary
                } else if projection.orderedFrameIDs.isEmpty {
                    noMatchingPhotos
                } else {
                    libraryGrid(projection: projection, framesByID: framesByID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                VStack(spacing: 6) {
                    LibraryViewModePicker(
                        viewModeRaw: $viewModeRaw,
                        filmTypeRaw: $filmTypeRaw,
                        isDisabled: activeStoredDefinition != nil
                    )
                    if activeStoredDefinition == nil {
                        LibrarySearchField(
                            searchText: $searchText,
                            onClearSearch: clearSearch
                        )
                    }
                }
                .padding(.bottom, 14)
                .zIndex(100)
                .allowsHitTesting(true)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.snappy(duration: 0.2), value: viewModeRaw)
        .animation(.snappy(duration: 0.2), value: cardScale)
    }

    func browserHeader(projection: LibraryBrowserProjection) -> some View {
        LibraryBrowserHeader(
            projection: projection,
            organizerTitle: organizerTitle,
            organizerSelection: organizerSelection,
            usesStoredDefinition: activeStoredDefinition != nil,
            effectiveSortKey: effectiveSortDescriptor.key,
            effectiveSortAscending: effectiveSortDescriptor.ascending,
            quickFilters: $quickFilters,
            viewModeRaw: $viewModeRaw,
            sortKeyRaw: $sortKeyRaw,
            sortAscending: $sortAscending,
            cardScale: $cardScale,
            cullingMode: $model.libraryCullingMode,
            onClearAllFilters: clearAllFilters,
            onSelectAll: { selectOrganizer(.all) }
        )
    }

    var emptyLibrary: some View {
        ContentUnavailableView {
            Label(model.text(.noImages), systemImage: "rectangle.stack.badge.plus")
        } actions: {
            Button {
                model.presentImportPanel()
            } label: {
                Label(model.text(.importImages), systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var noMatchingPhotos: some View {
        ContentUnavailableView {
            Label(
                model.text(AppLocalizedPhrase.noMatchingPhotos),
                systemImage: "line.3.horizontal.decrease.circle"
            )
        } actions: {
            if hasActiveFilter {
                Button(model.text(AppLocalizedPhrase.clearFilters)) {
                    clearAllFilters()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


}

private struct LibraryControlsTabButton: View {
    let tab: LibraryControlsTab
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("negaflow.library.controls.\(tab.rawValue)")
    }
}
