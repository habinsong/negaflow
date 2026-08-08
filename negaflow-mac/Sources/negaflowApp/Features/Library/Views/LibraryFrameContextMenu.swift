import SwiftUI

/// 사진 카드의 컨텍스트 메뉴.
///
/// 메뉴 내용을 `.contextMenu { ... }` 클로저에 직접 펼치면 카드가 만들어질 때마다 메뉴가 함께
/// 만들어진다. 대상 프레임 계산(`framesForContextAction`)과 삭제 계획(`sourceDeletionPlan`)은
/// 라이브러리 전체를 훑기 때문에, 카드 한 장당 O(전체 사진 수)가 되어 스크롤이 끊겼다.
/// 별도 View 로 감싸면 body 는 메뉴가 실제로 열릴 때 평가된다.
struct LibraryFrameContextMenu: View {
    @EnvironmentObject private var model: AppModel

    let frame: ScanFrame
    let orderedFrameIDs: [UUID]
    var folderID: String? = nil
    var showsDevelopCommand = false
    var showsCollectionCommands = false
    var activeManualCollection: LibraryManualCollection? = nil
    let onRename: (ScanFrame) -> Void
    let onOpenDevelop: () -> Void
    let onRequestSourceDeletion: (SourceDeletionPlan) -> Void
    var onSelectFolder: (String) -> Void = { _ in }

    var body: some View {
        let contextFrames = model.framesForContextAction(frame, within: orderedFrameIDs)
        let contextFrameIDs = contextFrames.map(\.id)
        Group {
            frameCommands(contextFrameIDs: contextFrameIDs)
        }
        Group {
            sourceCommands(contextFrames: contextFrames)
        }
    }

    @ViewBuilder
    private func frameCommands(contextFrameIDs: [UUID]) -> some View {
        LibraryStackMenu(frame: frame, orderedFrameIDs: orderedFrameIDs)
        Divider()

        if showsDevelopCommand {
            Button(model.text(.menuDevelop)) {
                if let folderID { onSelectFolder(folderID) }
                model.selectFrame(frame, orderedFrameIDs: orderedFrameIDs, modifiers: [])
                onOpenDevelop()
            }
        }

        Button(model.text(AppLocalizedPhrase.renamePhoto)) { onRename(frame) }

        Menu(model.text(AppLocalizedPhrase.rating)) {
            Button(model.text(AppLocalizedPhrase.resetRating)) { frame.setRating(0) }
            ForEach(1...5, id: \.self) { value in
                Button(model.text(AppLocalizedPhrase.starHelpFormat, value)) {
                    frame.toggleRating(value)
                }
            }
        }
        Button(
            frame.pickState == .picked
                ? model.text(AppLocalizedPhrase.clearPick)
                : model.text(AppLocalizedPhrase.picked)
        ) {
            frame.pickState = frame.pickState == .picked ? .unflagged : .picked
        }
        Button(
            frame.pickState == .rejected
                ? model.text(AppLocalizedPhrase.clearReject)
                : model.text(AppLocalizedPhrase.rejected)
        ) {
            frame.pickState = frame.pickState == .rejected ? .unflagged : .rejected
        }

        if showsCollectionCommands, !model.manualCollections.isEmpty {
            Menu(model.text(AppLocalizedPhrase.libraryAddToCollection)) {
                ForEach(model.manualCollections) { collection in
                    Button(collection.name) {
                        _ = model.addFrameIDs(contextFrameIDs, toManualCollection: collection.id)
                    }
                }
            }
            if let activeManualCollection {
                Button(model.text(AppLocalizedPhrase.libraryRemoveFromCollection)) {
                    _ = model.removeFrameIDs(
                        Set(contextFrameIDs),
                        fromManualCollection: activeManualCollection.id
                    )
                }
            }
        }

    }

    @ViewBuilder
    private func sourceCommands(contextFrames: [ScanFrame]) -> some View {
        Divider()
        Button(model.text(AppLocalizedPhrase.virtualCopy)) {
            model.createVirtualCopy(from: frame)
        }
        if !model.isSourceAvailable(frame) {
            Button(model.text(AppLocalizedPhrase.locateOriginal)) {
                model.presentRelinkPanel(for: frame)
            }
            .accessibilityIdentifier("negaflow.relink-source")
        }
        Button(model.text(AppLocalizedPhrase.showInFinder)) {
            model.revealSourceFilesInFinder(contextFrames)
        }
        Button(model.text(AppLocalizedPhrase.removeFromLibrary), role: .destructive) {
            model.removeFramesFromLibrary(contextFrames)
        }
        if let plan = model.sourceDeletionPlan(for: contextFrames) {
            Button(role: .destructive) {
                onRequestSourceDeletion(plan)
            } label: {
                Text(model.text(AppLocalizedPhrase.moveSourceToTrash))
                    .foregroundStyle(.red)
            }
        }
    }
}
