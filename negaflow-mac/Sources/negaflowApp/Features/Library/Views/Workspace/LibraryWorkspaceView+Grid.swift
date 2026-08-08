import SwiftUI

extension LibraryWorkspaceView {
    func libraryGrid(
        projection: LibraryBrowserProjection,
        framesByID: [UUID: ScanFrame]
    ) -> some View {
        ScrollView {
            if viewMode.groupsByFolder {
                folderGrid(projection: projection, framesByID: framesByID)
            } else {
                allPhotosGrid(projection: projection, framesByID: framesByID)
            }
        }
        .contextMenu {
            Button(model.text(AppLocalizedPhrase.newFolder)) {
                model.presentCreateLibraryFolder(
                    in: model.defaultLibraryFolderCreationParent(
                        selectedFolderID: selectedFolderID
                    )
                )
            }
        }
    }

    func allPhotosGrid(
        projection: LibraryBrowserProjection,
        framesByID: [UUID: ScanFrame]
    ) -> some View {
        let orderedFrameIDs = projection.orderedFrameIDs
        let visibleFrameIDs = model.stackProjectedFrameIDs(orderedFrameIDs)
        let frames = frames(orderedBy: visibleFrameIDs, framesByID: framesByID)
        return LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
            ForEach(frames) { frame in
                frameCard(frame, orderedFrameIDs: visibleFrameIDs)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func folderGrid(
        projection: LibraryBrowserProjection,
        framesByID: [UUID: ScanFrame]
    ) -> some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            ForEach(projection.folderSections, id: \.id) { section in
                let folderFrames = section.orderedFrameIDs.compactMap { framesByID[$0] }
                let visibleFrameIDs = model.stackProjectedFrameIDs(section.orderedFrameIDs)
                let sectionFrames = frames(
                    orderedBy: visibleFrameIDs,
                    framesByID: framesByID
                )
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(section.title)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        Text(model.text(AppLocalizedPhrase.frameCountFormat, sectionFrames.count))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        LibraryFolderDevelopmentControls(
                            frames: folderFrames,
                            fallbackProcess: DevelopmentProcess(
                                filmType: model.filmType,
                                isDigitalSource: model.isDigitalSource
                            ),
                            fallbackTarget: model.developTarget
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .contentShape(Rectangle())
                    .librarySourceDropDestination(
                        destinationFolder: URL(fileURLWithPath: section.id, isDirectory: true)
                    )
                    .contextMenu {
                        let folderURL = URL(fileURLWithPath: section.id, isDirectory: true)
                        Button(model.text(AppLocalizedPhrase.newFolder)) {
                            model.presentCreateLibraryFolder(
                                in: folderURL.deletingLastPathComponent()
                            )
                        }
                        Button(model.text(AppLocalizedPhrase.showInFinder)) {
                            model.revealLibraryFolderInFinder(folderURL)
                        }
                        Button(model.text(AppLocalizedPhrase.renameFolder)) {
                            organizerNameRequest = LibraryOrganizerNameRequest(
                                action: .renameFolder(
                                    url: folderURL
                                ),
                                title: .renameFolder,
                                fieldLabel: .filmName,
                                initialName: section.title
                            )
                        }
                    }

                    if !sectionFrames.isEmpty {
                        LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                            ForEach(sectionFrames) { frame in
                                frameCard(
                                    frame,
                                    orderedFrameIDs: visibleFrameIDs,
                                    folderID: section.id
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func frameCard(
        _ frame: ScanFrame,
        orderedFrameIDs: [UUID],
        folderID: String? = nil
    ) -> some View {
        FrameStripItemView(
            frame: frame,
            isSelected: model.isFrameSelected(frame),
            itemSize: cardSize,
            presentationPolicy: .developedWhenAvailable,
            thumbnailAspectRatio: LibraryGridCardLayout.thumbnailAspectRatio,
            thumbnailTitleSpacing: LibraryGridCardLayout.thumbnailTitleSpacing,
            ratingControlHeight: LibraryGridCardLayout.ratingControlHeight,
            onSelect: {
                if let folderID { selectedFolderID = folderID }
                model.selectFrame(frame, orderedFrameIDs: orderedFrameIDs)
            }
        )
        .librarySourceDraggable(count: model.contextActionFrameCount(for: frame)) {
            LibrarySourceDragItem(
                frameIDs: model.framesForContextAction(
                    frame,
                    within: orderedFrameIDs
                ).map(\.id)
            )
        }
        .contextMenu {
            LibraryFrameContextMenu(
                frame: frame,
                orderedFrameIDs: orderedFrameIDs,
                folderID: folderID,
                showsDevelopCommand: true,
                showsCollectionCommands: true,
                activeManualCollection: activeManualCollection,
                onRename: { renameFrame = $0 },
                onOpenDevelop: onOpenDevelop,
                onRequestSourceDeletion: { pendingSourceDeletion = $0 },
                onSelectFolder: { selectedFolderID = $0 }
            )
        }
    }


}
