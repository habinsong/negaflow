import SwiftUI

struct LibrarySurveyView: View {
    @EnvironmentObject private var model: AppModel
    let frames: [ScanFrame]

    var body: some View {
        if frames.isEmpty {
            ContentUnavailableView {
                Label(model.cullingText(.surveyNeedsSelectionTitle), systemImage: "rectangle.grid.3x2")
            } description: {
                Text(model.cullingText(.surveyNeedsSelectionDescription))
            }
        } else {
            GeometryReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns(for: proxy.size.width), spacing: 10) {
                        ForEach(frames) { frame in
                            LibraryCullingFrameSurface(
                                frame: frame,
                                role: nil,
                                isActive: model.selectedFrameID == frame.id,
                                onActivate: { model.activateFrame(frame.id) }
                            )
                            .aspectRatio(4 / 3, contentMode: .fit)
                        }
                    }
                    .padding(12)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        let count = min(4, max(1, Int(width / 290)))
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }
}
