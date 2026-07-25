import Foundation
import SwiftUI

struct WorkspaceFilmstrip: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("workspace.filmstripHeight") private var storedFilmstripHeight = FilmstripSizing.defaultHeight
    @AppStorage("workspace.filmstripItemScale") private var itemScale = 1.0
    @AppStorage("workspace.filmstripSortKey") private var sortKeyRaw = LibrarySortKey.inputOrder.rawValue
    @AppStorage("workspace.filmstripSortAscending") private var sortAscending = true
    @State private var liveFilmstripHeight = FilmstripSizing.defaultHeight
    @State private var resizeStartHeight: Double?
    @State private var lockedRowCount: Int?
    @State private var renameFrame: ScanFrame?
    @State private var pendingSourceDeletion: SourceDeletionPlan?
    @State private var isFilmstripHovered = false

    private let minFilmstripHeight = 112.0
    private let maxFilmstripHeight = 340.0
    private let resizeHandleHeight: CGFloat = 7
    private let gridPaddingHeight: CGFloat = 20
    private let gridSpacing: CGFloat = 10
    private let minItemScale = 0.56
    private let maxItemScale = 1.34

    var body: some View {
        let visibleFrames = displayedFrames
        let orderedFrameIDs = visibleFrames.map(\.id)
        let selectedIndex = model.selectedFrameID.flatMap { selectedID in
            visibleFrames.firstIndex { $0.id == selectedID }
        }
        return VStack(spacing: 0) {
            resizeHandle
            Divider()
            ScrollViewReader { proxy in
                HStack(spacing: 0) {
                    FrameStepButton(
                        systemName: "chevron.left",
                        help: model.text(AppLocalizedPhrase.previousFrame),
                        height: max(70, contentHeight - 20),
                        isDisabled: selectedIndex.map { $0 <= 0 } ?? true
                    ) {
                        selectAdjacentFrame(
                            -1,
                            displayedFrames: visibleFrames,
                            orderedFrameIDs: orderedFrameIDs
                        )
                    }

                    if model.frames.isEmpty {
                        ContentUnavailableView(
                            model.text(AppLocalizedPhrase.noImages),
                            systemImage: "film"
                        )
                        .frame(maxWidth: .infinity, minHeight: contentHeight, maxHeight: contentHeight)
                        .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: true) {
                            LazyHGrid(rows: gridRows, spacing: gridSpacing) {
                                ForEach(visibleFrames) { frame in
                                    FrameStripItemView(
                                        frame: frame,
                                        isSelected: model.isFrameSelected(frame),
                                        itemSize: itemSize,
                                        presentationMode: .raw,
                                        thumbnailAspectRatio: FilmstripSizing.thumbnailAspectRatio,
                                        onSelect: { model.selectFrame(frame, orderedFrameIDs: orderedFrameIDs) }
                                    )
                                    .id(frame.id)
                                    .contextMenu {
                                        LibraryStackMenu(
                                            frame: frame,
                                            orderedFrameIDs: orderedFrameIDs
                                        )
                                        Divider()
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
                                        Divider()
                                        Button(model.text(AppLocalizedPhrase.renamePhoto)) { renameFrame = frame }
                                        Button(model.text(AppLocalizedPhrase.virtualCopy)) { model.createVirtualCopy(from: frame) }
                                        if !model.isSourceAvailable(frame) {
                                            Button(model.text(AppLocalizedPhrase.locateOriginal)) {
                                                model.presentRelinkPanel(for: frame)
                                            }
                                            .accessibilityIdentifier("negaflow.relink-source")
                                        }
                                        Button(model.text(AppLocalizedPhrase.removeFromLibrary), role: .destructive) {
                                            model.removeFramesFromLibrary(
                                                model.framesForContextAction(
                                                    frame,
                                                    within: orderedFrameIDs
                                                )
                                            )
                                        }
                                        if let plan = model.sourceDeletionPlan(
                                            for: model.framesForContextAction(
                                                frame,
                                                within: orderedFrameIDs
                                            )
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
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(height: contentHeight, alignment: .center)
                        }
                        .background(HorizontalFilmstripWheelBridge(isActive: isFilmstripHovered))
                        .onHover { isFilmstripHovered = $0 }
                    }

                    FrameStepButton(
                        systemName: "chevron.right",
                        help: model.text(AppLocalizedPhrase.nextFrame),
                        height: max(70, contentHeight - 20),
                        isDisabled: selectedIndex.map { $0 >= visibleFrames.count - 1 } ?? true
                    ) {
                        selectAdjacentFrame(
                            1,
                            displayedFrames: visibleFrames,
                            orderedFrameIDs: orderedFrameIDs
                        )
                    }
                }
                .onChange(of: model.frames.count) { _, _ in
                    guard let id = model.frames.last?.id else { return }
                    withAnimation(.snappy(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .trailing)
                    }
                }
                .onChange(of: model.selectedFrameID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .frame(height: CGFloat(clampedFilmstripHeight))
        .adaptivePanelSurface(.bar)
        .onAppear {
            let preferredHeight = abs(storedFilmstripHeight - FilmstripSizing.legacyDefaultHeight) < 0.5
                ? FilmstripSizing.defaultHeight
                : storedFilmstripHeight
            let storedHeight = clampedHeight(preferredHeight)
            storedFilmstripHeight = storedHeight
            liveFilmstripHeight = storedHeight
            itemScale = clampedItemScale
        }
        .sheet(item: $renameFrame) { frame in
            FrameRenameSheet(frame: frame)
                .environmentObject(model)
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
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(height: 6)
            .overlay {
                Capsule()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 44, height: 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if resizeStartHeight == nil {
                            resizeStartHeight = clampedFilmstripHeight
                            lockedRowCount = rowCount
                        }
                        let start = resizeStartHeight ?? clampedFilmstripHeight
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            liveFilmstripHeight = clampedHeight(start - value.translation.height)
                        }
                    }
                    .onEnded { _ in
                        let finalHeight = clampedFilmstripHeight
                        liveFilmstripHeight = finalHeight
                        storedFilmstripHeight = finalHeight
                        itemScale = effectiveItemScale
                        lockedRowCount = nil
                        resizeStartHeight = nil
                    }
            )
            .help(model.text(AppLocalizedPhrase.filmstripHeightHelp))
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("negaflow.filmstrip-resize")
            .accessibilityLabel(model.text(AppLocalizedPhrase.filmstripHeightHelp))
            .accessibilityValue(model.accessibilityText(
                .filmstripHeightValueFormat,
                Int(clampedFilmstripHeight.rounded())
            ))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjustFilmstripHeight(16)
                case .decrement: adjustFilmstripHeight(-16)
                @unknown default: break
                }
            }
            .accessibilityAction(named: Text(model.text(AppLocalizedPhrase.reset))) {
                setFilmstripHeight(FilmstripSizing.defaultHeight)
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in
                adjustFilmstripHeight(16)
                return .handled
            }
            .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in
                adjustFilmstripHeight(-16)
                return .handled
            }
    }

    private var clampedFilmstripHeight: Double {
        clampedHeight(liveFilmstripHeight)
    }

    private var clampedItemScale: Double {
        min(max(itemScale, minItemScale), maxItemScale)
    }

    private var contentHeight: CGFloat {
        contentHeight(for: clampedFilmstripHeight)
    }

    private var sourceDeletionPresented: Binding<Bool> {
        Binding(
            get: { pendingSourceDeletion != nil },
            set: { if !$0 { pendingSourceDeletion = nil } }
        )
    }

    private var itemSize: CGSize {
        let height = min(autoItemHeight * CGFloat(effectiveItemScale), fittedRowHeight)
        return CGSize(
            width: CGFloat(FilmstripSizing.cardWidth(forItemHeight: Double(height))),
            height: height
        )
    }

    private var gridRows: [GridItem] {
        Array(repeating: GridItem(.fixed(itemSize.height), spacing: gridSpacing), count: rowCount)
    }

    private var rowCount: Int {
        if let lockedRowCount { return lockedRowCount }
        let nominalHeight = CGFloat(FilmstripSizing.nominalItemHeight * clampedItemScale)
        let rows = Int((availableGridHeight + gridSpacing) / (nominalHeight + gridSpacing))
        return min(3, max(1, rows))
    }

    private var availableGridHeight: CGFloat {
        max(72, contentHeight - gridPaddingHeight)
    }

    private var fittedRowHeight: CGFloat {
        let rowTotal = CGFloat(rowCount)
        return max(64, (availableGridHeight - (rowTotal - 1) * gridSpacing) / rowTotal)
    }

    private var autoItemHeight: CGFloat {
        min(
            CGFloat(FilmstripSizing.maximumAutoItemHeight),
            max(58, fittedRowHeight * CGFloat(FilmstripSizing.defaultRowFill))
        )
    }

    private var maxEffectiveItemScale: Double {
        min(maxItemScale, max(minItemScale, Double(fittedRowHeight / autoItemHeight)))
    }

    private var effectiveItemScale: Double {
        min(clampedItemScale, maxEffectiveItemScale)
    }

    private func contentHeight(for height: Double) -> CGFloat { max(72, CGFloat(height) - resizeHandleHeight) }

    private func clampedHeight(_ height: Double) -> Double {
        FilmstripSizing.clampedHeight(height, minimum: minFilmstripHeight, maximum: maxFilmstripHeight)
    }

    private func adjustFilmstripHeight(_ delta: Double) {
        setFilmstripHeight(clampedFilmstripHeight + delta)
    }

    private func setFilmstripHeight(_ height: Double) {
        let value = clampedHeight(height)
        liveFilmstripHeight = value
        storedFilmstripHeight = value
        itemScale = effectiveItemScale
    }

    private func selectAdjacentFrame(
        _ offset: Int,
        displayedFrames: [ScanFrame],
        orderedFrameIDs: [UUID]
    ) {
        guard let selectedID = model.selectedFrameID,
              let index = displayedFrames.firstIndex(where: { $0.id == selectedID }) else {
            return
        }
        let nextIndex = min(max(index + offset, 0), displayedFrames.count - 1)
        guard displayedFrames.indices.contains(nextIndex) else { return }
        model.selectFrame(
            displayedFrames[nextIndex],
            orderedFrameIDs: orderedFrameIDs,
            modifiers: []
        )
    }

    private var sortKey: LibrarySortKey {
        LibrarySortKey(rawValue: sortKeyRaw) ?? .inputOrder
    }

    private var sortKeyBinding: Binding<String> {
        Binding(
            get: { sortKeyRaw },
            set: { sortKeyRaw = $0 }
        )
    }

    private var displayedFrames: [ScanFrame] {
        let sorted = LibraryPresentation.sortedFrames(
            model.frames,
            key: sortKey,
            ascending: sortAscending
        )
        let framesByID = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0) })
        return model.stackProjectedFrameIDs(sorted.map(\.id)).compactMap { framesByID[$0] }
    }
}
