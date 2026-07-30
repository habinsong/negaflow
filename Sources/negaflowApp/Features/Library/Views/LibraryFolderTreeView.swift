import SwiftUI

struct LibraryFolderTreeView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var expansionStore = LibraryFolderExpansionStore()
    @State private var editingFolderID: String?
    @State private var folderNameDraft = ""
    @State private var renameFrame: ScanFrame?
    @FocusState private var focusedFolderID: String?
    let orderedResultFrameIDs: [UUID]?
    let selectedFolderID: Binding<String?>
    let visibleFolderPaths: Set<String>?
    let frameListMaxHeight: CGFloat?

    init(
        orderedResultFrameIDs: [UUID]? = nil,
        selectedFolderID: Binding<String?> = .constant(nil),
        visibleFolderPaths: Set<String>? = nil,
        frameListMaxHeight: CGFloat? = nil
    ) {
        self.orderedResultFrameIDs = orderedResultFrameIDs
        self.selectedFolderID = selectedFolderID
        self.visibleFolderPaths = visibleFolderPaths
        self.frameListMaxHeight = frameListMaxHeight
    }

    var body: some View {
        let displayedSections = sections
        VStack(alignment: .leading, spacing: 6) {
            if displayedSections.isEmpty {
                Text(model.text(AppLocalizedPhrase.noLibraryFolders))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(displayedSections) { section in
                    folderSection(section)
                }
            }
        }
        .onChange(of: displayedSections.map(\.id)) { _, ids in
            if let selectedID = selectedFolderID.wrappedValue,
               !ids.contains(selectedID) {
                selectedFolderID.wrappedValue = nil
            }
        }
        .onKeyPress(.return) {
            guard let selectedID = selectedFolderID.wrappedValue,
                  let section = displayedSections.first(where: { $0.id == selectedID }) else {
                return .ignored
            }
            beginRenaming(section)
            return .handled
        }
        .sheet(item: $renameFrame) { frame in
            FrameRenameSheet(frame: frame)
                .environmentObject(model)
        }
    }

    private var sections: [LibraryFolderSection] {
        LibraryPresentation.visibleFolderSections(
            model.makeLibraryFolderTreeSections(orderedFrameIDs: orderedResultFrameIDs),
            restrictedTo: visibleFolderPaths
        )
    }

    @ViewBuilder
    private func folderSection(_ section: LibraryFolderSection) -> some View {
        let isExpanded = expansionStore.isExpanded(section.id)
        let isSelected = selectedFolderID.wrappedValue == section.id
        let isFolderAvailable = section.folder.map(model.isLibraryFolderAvailable) ?? true
        let orderedFrameIDs = orderedResultFrameIDs ?? sections.flatMap(\.frames).map(\.id)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Button {
                    model.removeLibraryFolderSection(section)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help(model.text(AppLocalizedPhrase.removeFromLibrary))

                if editingFolderID == section.id {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .frame(width: 12)
                        Image(systemName: isFolderAvailable ? "folder" : "folder.badge.questionmark")
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .frame(width: 16)
                        TextField(model.text(AppLocalizedPhrase.renameFolder), text: $folderNameDraft)
                            .textFieldStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .focused($focusedFolderID, equals: section.id)
                            .onSubmit { finishRenaming(section) }
                            .onExitCommand { cancelRenaming() }
                        Spacer(minLength: 6)
                        Text(model.text(AppLocalizedPhrase.frameCountFormat, section.frames.count))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        selectedFolderID.wrappedValue = section.id
                        expansionStore.toggle(section.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .frame(width: 12)
                            Image(systemName: isFolderAvailable ? "folder" : "folder.badge.questionmark")
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .frame(width: 16)
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(model.text(AppLocalizedPhrase.frameCountFormat, section.frames.count))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("negaflow.library.folder-row")
                    .accessibilityLabel(section.title)
                    .accessibilitySelectionState(
                        isSelected,
                        selectedValue: model.accessibilityText(.selected),
                        unselectedValue: model.accessibilityText(.notSelected),
                        unselectedHint: model.accessibilityText(.select)
                    )
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            .librarySourceDropDestination(
                destinationFolder: URL(fileURLWithPath: section.id, isDirectory: true)
            )
            .contextMenu {
                if let folder = section.folder, !isFolderAvailable {
                    Button(model.text(AppLocalizedPhrase.locateMissingFolder)) {
                        model.presentRelinkFolderPanel(folder)
                    }
                }
                if isFolderAvailable {
                    let folderURL = URL(fileURLWithPath: section.id, isDirectory: true)
                    Button(model.text(AppLocalizedPhrase.newFolder)) {
                        model.presentCreateLibraryFolder(
                            in: folderURL.deletingLastPathComponent()
                        )
                    }
                    Button(model.text(AppLocalizedPhrase.showInFinder)) {
                        model.revealLibraryFolderInFinder(folderURL)
                    }
                    if !section.frames.isEmpty {
                        Button(model.text(AppLocalizedPhrase.renameFolder)) {
                            beginRenaming(section)
                        }
                    }
                }
            }

            if isExpanded {
                if !section.frames.isEmpty {
                    if let frameListMaxHeight {
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                frameRows(section.frames, sectionID: section.id, orderedFrameIDs: orderedFrameIDs)
                            }
                        }
                        .frame(
                            height: min(
                                frameListMaxHeight,
                                CGFloat(section.frames.count * 25 - 3)
                            )
                        )
                    } else {
                        frameRows(section.frames, sectionID: section.id, orderedFrameIDs: orderedFrameIDs)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func frameRows(
        _ frames: [ScanFrame],
        sectionID: String,
        orderedFrameIDs: [UUID]
    ) -> some View {
        ForEach(frames) { frame in
            Button {
                selectedFolderID.wrappedValue = sectionID
                model.selectFrame(frame, orderedFrameIDs: orderedFrameIDs)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.isSourceAvailable(frame) ? "photo" : "exclamationmark.circle")
                        .foregroundStyle(model.isFrameSelected(frame) ? Color.accentColor : Color.secondary)
                        .frame(width: 14)
                    if case .scannerTIFF = frame.sourceKind {
                        HStack(spacing: 4) {
                            Text(frame.displayName(language: model.appLanguage))
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            Text(verbatim: "(\(frame.sourceFileNameWithExtension))")
                                .font(AppTypography.minimumText())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .minimumScaleFactor(AppTypography.minimumScaleFactor)
                                .layoutPriority(-1)
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(frame.sourceFileNameWithExtension)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 28)
                .padding(.vertical, 2)
                .frame(height: frameListMaxHeight == nil ? nil : 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .librarySourceDraggable(count: model.contextActionFrameCount(for: frame)) {
                LibrarySourceDragItem(
                    frameIDs: model.framesForContextAction(
                        frame,
                        within: orderedFrameIDs
                    ).map(\.id)
                )
            }
            .foregroundStyle(model.isFrameSelected(frame) ? Color.accentColor : Color.primary)
            .accessibilityIdentifier("negaflow.library.file-row")
            .accessibilityLabel(frame.displayName(language: model.appLanguage))
            .accessibilitySelectionState(
                model.isFrameSelected(frame),
                selectedValue: model.accessibilityText(.selected),
                unselectedValue: model.accessibilityText(.notSelected),
                unselectedHint: model.accessibilityText(.select)
            )
            .contextMenu {
                Button(model.text(AppLocalizedPhrase.renamePhoto)) {
                    renameFrame = frame
                }
                Button(model.text(AppLocalizedPhrase.showInFinder)) {
                    model.revealSourceFilesInFinder(model.framesForContextAction(
                        frame,
                        within: orderedFrameIDs
                    ))
                }
                if !model.isSourceAvailable(frame) {
                    Button(model.text(AppLocalizedPhrase.locateOriginal)) {
                        model.presentRelinkPanel(for: frame)
                    }
                }
            }
        }
    }

    private func beginRenaming(_ section: LibraryFolderSection) {
        guard FileManager.default.fileExists(atPath: section.id), !section.frames.isEmpty else {
            return
        }
        selectedFolderID.wrappedValue = section.id
        editingFolderID = section.id
        folderNameDraft = section.title
        Task { @MainActor in focusedFolderID = section.id }
    }

    private func finishRenaming(_ section: LibraryFolderSection) {
        let draft = folderNameDraft
        cancelRenaming()
        model.renameLibraryFolder(
            at: URL(fileURLWithPath: section.id, isDirectory: true),
            to: draft
        )
    }

    private func cancelRenaming() {
        editingFolderID = nil
        focusedFolderID = nil
        folderNameDraft = ""
    }
}
