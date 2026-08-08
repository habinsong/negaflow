import SwiftUI

struct LibraryOrganizerSection: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selection: LibraryOrganizerSelection
    @Binding var nameRequest: LibraryOrganizerNameRequest?
    let currentSearchDefinition: LibrarySearchDefinition
    let selectedFrameIDs: [UUID]
    let sectionHeight: CGFloat
    let onSelect: (LibraryOrganizerSelection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    allPhotosRow
                    ForEach(model.manualCollections) { collection in
                        manualCollectionRow(collection)
                    }
                    if !model.smartCollections.isEmpty {
                        groupLabel(model.text(AppLocalizedPhrase.librarySmartCollections))
                        ForEach(model.smartCollections) { collection in
                            smartCollectionRow(collection)
                        }
                    }
                    if !model.savedSearches.isEmpty {
                        groupLabel(model.text(AppLocalizedPhrase.librarySavedSearches))
                        ForEach(model.savedSearches) { savedSearch in
                            savedSearchRow(savedSearch)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .frame(height: sectionHeight, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Menu {
                Button(model.text(AppLocalizedPhrase.libraryNewCollection)) {
                    nameRequest = LibraryOrganizerNameRequest(
                        action: .createManual(frameIDs: selectedFrameIDs),
                        title: .libraryNewCollection,
                        fieldLabel: .libraryCollectionName
                    )
                }
                Button(model.text(AppLocalizedPhrase.libraryNewSmartCollection)) {
                    nameRequest = LibraryOrganizerNameRequest(
                        action: .createSmart(definition: currentSearchDefinition),
                        title: .libraryNewSmartCollection,
                        fieldLabel: .libraryCollectionName
                    )
                }
                Button(model.text(AppLocalizedPhrase.librarySaveCurrentSearch)) {
                    nameRequest = LibraryOrganizerNameRequest(
                        action: .createSavedSearch(definition: currentSearchDefinition),
                        title: .librarySaveCurrentSearch,
                        fieldLabel: .librarySearchName
                    )
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var allPhotosRow: some View {
        organizerRow(
            title: model.text(AppLocalizedPhrase.libraryAllPhotos),
            systemImage: "photo.on.rectangle.angled",
            count: model.frames.count,
            isSelected: selection == .all,
            isEnabled: true
        ) {
            onSelect(.all)
        }
    }

    private func manualCollectionRow(_ collection: LibraryManualCollection) -> some View {
        organizerRow(
            title: collection.name,
            systemImage: "rectangle.stack",
            count: collection.frameIDs.count,
            isSelected: selection == .manual(collection.id),
            isEnabled: true
        ) {
            onSelect(.manual(collection.id))
        }
        .contextMenu {
            if !selectedFrameIDs.isEmpty {
                Button(model.text(AppLocalizedPhrase.libraryAddToCollection)) {
                    _ = model.addFrameIDs(selectedFrameIDs, toManualCollection: collection.id)
                }
                Button(model.text(AppLocalizedPhrase.libraryRemoveFromCollection)) {
                    _ = model.removeFrameIDs(Set(selectedFrameIDs), fromManualCollection: collection.id)
                }
                Divider()
            }
            Button(model.text(AppLocalizedPhrase.rename)) {
                nameRequest = LibraryOrganizerNameRequest(
                    action: .renameManual(id: collection.id),
                    title: .rename,
                    fieldLabel: .libraryCollectionName,
                    initialName: collection.name
                )
            }
            Button(model.text(AppLocalizedPhrase.delete), role: .destructive) {
                _ = model.deleteManualCollection(id: collection.id)
            }
        }
    }

    private func smartCollectionRow(_ collection: LibrarySmartCollection) -> some View {
        let isValid = collection.definition.decodedDefinition() != nil
        return organizerRow(
            title: collection.name,
            systemImage: isValid ? "gearshape.2" : "exclamationmark.triangle",
            count: nil,
            isSelected: selection == .smart(collection.id),
            isEnabled: isValid
        ) {
            guard isValid else { return }
            onSelect(.smart(collection.id))
        }
        .help(isValid ? "" : model.text(AppLocalizedPhrase.libraryInvalidStoredSearch))
        .contextMenu {
            Button(model.text(AppLocalizedPhrase.rename)) {
                nameRequest = LibraryOrganizerNameRequest(
                    action: .renameSmart(id: collection.id),
                    title: .rename,
                    fieldLabel: .libraryCollectionName,
                    initialName: collection.name
                )
            }
            Button(model.text(AppLocalizedPhrase.delete), role: .destructive) {
                _ = model.deleteSmartCollection(id: collection.id)
            }
        }
    }

    private func savedSearchRow(_ savedSearch: LibrarySavedSearch) -> some View {
        let isValid = savedSearch.definition.decodedDefinition() != nil
        return organizerRow(
            title: savedSearch.name,
            systemImage: isValid ? "magnifyingglass" : "exclamationmark.triangle",
            count: nil,
            isSelected: selection == .savedSearch(savedSearch.id),
            isEnabled: isValid
        ) {
            guard isValid else { return }
            onSelect(.savedSearch(savedSearch.id))
        }
        .help(isValid ? "" : model.text(AppLocalizedPhrase.libraryInvalidStoredSearch))
        .contextMenu {
            Button(model.text(AppLocalizedPhrase.rename)) {
                nameRequest = LibraryOrganizerNameRequest(
                    action: .renameSavedSearch(id: savedSearch.id),
                    title: .rename,
                    fieldLabel: .librarySearchName,
                    initialName: savedSearch.name
                )
            }
            Button(model.text(AppLocalizedPhrase.delete), role: .destructive) {
                _ = model.deleteSavedSearch(id: savedSearch.id)
            }
        }
    }

    private func organizerRow(
        title: String,
        systemImage: String,
        count: Int?,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(isEnabled ? Color.secondary : Color.orange)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let count {
                    Text(verbatim: "\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .frame(height: 27)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.72)
        .accessibilityLabel(title)
        .accessibilitySelectionState(
            isSelected,
            selectedValue: model.accessibilityText(.selected),
            unselectedValue: model.accessibilityText(.notSelected),
            unselectedHint: model.accessibilityText(.select)
        )
    }

    private func groupLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}
