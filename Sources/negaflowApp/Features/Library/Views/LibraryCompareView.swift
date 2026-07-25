import SwiftUI

struct LibraryCompareView: View {
    @EnvironmentObject private var model: AppModel
    let frames: [ScanFrame]

    var body: some View {
        if frames.count == 2 {
            GeometryReader { proxy in
                let horizontal = proxy.size.width >= proxy.size.height * 1.15
                Group {
                    if horizontal {
                        HStack(spacing: 1) { compareSurfaces }
                    } else {
                        VStack(spacing: 1) { compareSurfaces }
                    }
                }
                .padding(12)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
            ContentUnavailableView {
                Label(model.cullingText(.compareNeedsTwoTitle), systemImage: "rectangle.split.2x1")
            } description: {
                Text(model.cullingText(.compareNeedsTwoDescription))
            }
        }
    }

    @ViewBuilder
    private var compareSurfaces: some View {
        LibraryCullingFrameSurface(
            frame: frames[0],
            role: .reference,
            isActive: model.selectedFrameID == frames[0].id,
            onActivate: { model.activateFrame(frames[0].id) }
        )
        LibraryCullingFrameSurface(
            frame: frames[1],
            role: .candidate,
            isActive: model.selectedFrameID == frames[1].id,
            onActivate: { model.activateFrame(frames[1].id) }
        )
    }
}
