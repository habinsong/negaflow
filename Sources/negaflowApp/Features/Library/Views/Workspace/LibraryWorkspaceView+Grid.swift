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
        let contextFrames = model.framesForContextAction(frame, within: orderedFrameIDs)
        return FrameStripItemView(
            frame: frame,
            isSelected: model.isFrameSelected(frame),
            itemSize: cardSize,
            presentationMode: .raw,
            thumbnailAspectRatio: LibraryGridCardLayout.thumbnailAspectRatio,
            thumbnailTitleSpacing: LibraryGridCardLayout.thumbnailTitleSpacing,
            ratingControlHeight: LibraryGridCardLayout.ratingControlHeight,
            onSelect: {
                if let folderID { selectedFolderID = folderID }
                model.selectFrame(frame, orderedFrameIDs: orderedFrameIDs)
            }
        )
        .librarySourceDraggable(
            item: LibrarySourceDragItem(frameIDs: contextFrames.map(\.id))
        )
        .contextMenu {
            LibraryStackMenu(frame: frame, orderedFrameIDs: orderedFrameIDs)
            Divider()
            Button(model.text(.menuDevelop)) {
                if let folderID { selectedFolderID = folderID }
                model.selectFrame(frame, orderedFrameIDs: orderedFrameIDs, modifiers: [])
                onOpenDevelop()
            }
            Button(model.text(AppLocalizedPhrase.renamePhoto)) {
                renameFrame = frame
            }
            Menu(model.text(AppLocalizedPhrase.rating)) {
                Button(model.text(AppLocalizedPhrase.resetRating)) { frame.setRating(0) }
                ForEach(1...5, id: \.self) { value in
                    Button(model.text(AppLocalizedPhrase.starHelpFormat, value)) { frame.toggleRating(value) }
                }
            }
            Button(frame.pickState == .picked ? model.text(AppLocalizedPhrase.clearPick) : model.text(AppLocalizedPhrase.picked)) {
                frame.pickState = frame.pickState == .picked ? .unflagged : .picked
            }
            Button(frame.pickState == .rejected ? model.text(AppLocalizedPhrase.clearReject) : model.text(AppLocalizedPhrase.rejected)) {
                frame.pickState = frame.pickState == .rejected ? .unflagged : .rejected
            }
            if !model.manualCollections.isEmpty {
                let contextFrameIDs = model.framesForContextAction(
                    frame,
                    within: orderedFrameIDs
                ).map(\.id)
                Menu(model.text(AppLocalizedPhrase.libraryAddToCollection)) {
                    ForEach(model.manualCollections) { collection in
                        Button(collection.name) {
                            _ = model.addFrameIDs(
                                contextFrameIDs,
                                toManualCollection: collection.id
                            )
                        }
                    }
                }
                if let collection = activeManualCollection {
                    Button(model.text(AppLocalizedPhrase.libraryRemoveFromCollection)) {
                        _ = model.removeFrameIDs(
                            Set(contextFrameIDs),
                            fromManualCollection: collection.id
                        )
                    }
                }
            }
            Divider()
            Button(model.text(AppLocalizedPhrase.virtualCopy)) { model.createVirtualCopy(from: frame) }
            if !model.isSourceAvailable(frame) {
                Button(model.text(AppLocalizedPhrase.locateOriginal)) {
                    model.presentRelinkPanel(for: frame)
                }
            }
            Button(model.text(AppLocalizedPhrase.showInFinder)) {
                model.revealSourceFilesInFinder(contextFrames)
            }
            Button(model.text(AppLocalizedPhrase.removeFromLibrary), role: .destructive) {
                model.removeFramesFromLibrary(
                    model.framesForContextAction(frame, within: orderedFrameIDs)
                )
            }
            if let plan = model.sourceDeletionPlan(
                for: model.framesForContextAction(frame, within: orderedFrameIDs)
            ) {
                Button(role: .destructive) {
                    pendingSourceDeletion = plan
                } label: {
                    Text(model.text(AppLocalizedPhrase.moveSourceToTrash))
                        .foregroundStyle(.red)
                }
            }
        }
    }


}
