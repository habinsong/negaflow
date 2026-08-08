import SwiftUI

extension LibraryWorkspaceView {
    /// 격자 바깥 여백. 열 수를 계산할 때 이 값을 빼야 마지막 열이 잘리지 않는다.
    static let gridPadding: CGFloat = 18

    func libraryGrid(
        projection: LibraryBrowserProjection,
        framesByID: [UUID: ScanFrame],
        browserWidth: CGFloat
    ) -> some View {
        let columns = gridColumns(contentWidth: browserWidth - Self.gridPadding * 2)
        return ScrollView {
            if viewMode.groupsByFolder {
                folderGrid(projection: projection, framesByID: framesByID, columns: columns)
            } else {
                allPhotosGrid(projection: projection, framesByID: framesByID, columns: columns)
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
        framesByID: [UUID: ScanFrame],
        columns: [GridItem]
    ) -> some View {
        let orderedFrameIDs = projection.orderedFrameIDs
        let visibleFrameIDs = model.stackProjectedFrameIDs(orderedFrameIDs)
        let frames = frames(orderedBy: visibleFrameIDs, framesByID: framesByID)
        return LazyVGrid(columns: columns, spacing: gridSpacing) {
            ForEach(frames) { frame in
                frameCard(frame, orderedFrameIDs: visibleFrameIDs)
            }
        }
        .padding(Self.gridPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 폴더별 보기. **격자를 하나만 둔다.**
    ///
    /// 폴더마다 `LazyVGrid` 를 따로 두고 그것을 `LazyVStack` 으로 감싸면 게으름이 사라진다.
    /// 바깥 스택은 자기 항목(= 폴더 한 덩어리)의 높이를 알아야 자리를 잡으므로 그 안의 격자를
    /// 통째로 펼친다. 폴더 하나에 100장이 들어 있으면 그 폴더가 화면에 걸치는 순간 카드 100장이
    /// 전부 만들어진다. 격자를 하나로 합치고 폴더를 `Section` 으로 두면 게으름의 단위가 폴더가
    /// 아니라 **격자 한 줄**이 되어, 보이는 줄만 만들어진다.
    func folderGrid(
        projection: LibraryBrowserProjection,
        framesByID: [UUID: ScanFrame],
        columns: [GridItem]
    ) -> some View {
        LazyVGrid(columns: columns, spacing: gridSpacing) {
            ForEach(projection.folderSections.indices, id: \.self) { index in
                let section = projection.folderSections[index]
                let visibleFrameIDs = model.stackProjectedFrameIDs(section.orderedFrameIDs)
                // 접힘은 `ForEach` 안의 `if` 가 아니라 **데이터 단계**에서 거른다. 게으른
                // 컨테이너 안에 조건부 가지를 두면 컨테이너가 항목 수를 다시 세게 된다.
                // 접힌 폴더는 프레임을 아예 꺼내지 않는다 — 머리띠에 필요한 건 개수뿐이다.
                let renderedFrames = folderCollapse.isExpanded(section.id)
                    ? visibleFrameIDs.compactMap { framesByID[$0] }
                    : []
                Section {
                    ForEach(renderedFrames) { frame in
                        frameCard(
                            frame,
                            orderedFrameIDs: visibleFrameIDs,
                            folderID: section.id
                        )
                    }
                } header: {
                    folderSectionHeader(
                        section,
                        isFirst: index == 0,
                        frameCount: visibleFrameIDs.count,
                        framesByID: framesByID
                    )
                }
            }
        }
        .padding(Self.gridPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func folderSectionHeader(
        _ section: LibraryBrowserFolderSection,
        isFirst: Bool,
        frameCount: Int,
        framesByID: [UUID: ScanFrame]
    ) -> some View {
        let isExpanded = folderCollapse.isExpanded(section.id)
        HStack(spacing: 8) {
            LibraryFolderDisclosureButton(
                isExpanded: isExpanded,
                label: model.text(isExpanded ? .collapseFolder : .expandFolder)
            ) {
                folderCollapse.toggle(section.id)
            }

            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(section.title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            Text(model.text(AppLocalizedPhrase.frameCountFormat, frameCount))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            LibraryFolderDevelopmentControls(
                frames: section.orderedFrameIDs.compactMap { framesByID[$0] },
                fallbackProcess: DevelopmentProcess(
                    filmType: model.filmType,
                    isDigitalSource: model.isDigitalSource
                ),
                fallbackTarget: model.developTarget
            )
            Spacer(minLength: 0)
        }
        .padding(6)
        // 머리띠는 격자의 한 줄을 통째로 차지한다. 폴더 사이 간격도 여기서 준다 — 격자에는
        // 줄 간격 하나뿐이라, 첫 폴더가 아닐 때만 위쪽에 여백을 더한다.
        .padding(.top, isFirst ? 0 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { folderCollapse.toggle(section.id) }
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
