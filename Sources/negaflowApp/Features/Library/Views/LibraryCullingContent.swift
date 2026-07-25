import SwiftUI

struct LibraryCullingContent: View {
    @EnvironmentObject private var model: AppModel
    let mode: LibraryCullingMode
    let orderedFrameIDs: [UUID]

    var body: some View {
        switch mode {
        case .grid:
            EmptyView()
        case .compare:
            LibraryCompareView(frames: resolvedFrames(compareFrameIDs))
        case .survey:
            LibrarySurveyView(frames: resolvedFrames(selectedFrameIDs))
        }
    }

    private var selectedFrameIDs: [UUID] {
        LibraryCullingProjection.selectedFrameIDs(
            orderedFrameIDs: orderedFrameIDs,
            selectedFrameIDs: model.selectedFrameIDs
        )
    }

    private var compareFrameIDs: [UUID] {
        LibraryCullingProjection.compareFrameIDs(
            orderedFrameIDs: orderedFrameIDs,
            selectedFrameIDs: model.selectedFrameIDs,
            activeFrameID: model.selectedFrameID
        )
    }

    private func resolvedFrames(_ ids: [UUID]) -> [ScanFrame] {
        let framesByID = model.uniqueLibraryFramesByID()
        return ids.compactMap { framesByID[$0] }
    }
}
