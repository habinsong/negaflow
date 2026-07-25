import SwiftUI

enum WorkspacePanelID: Hashable {
    case sidebar
    case inspector
    case libraryControls
}

struct WorkspacePanelWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [WorkspacePanelID: CGFloat] { [:] }

    static func reduce(
        value: inout [WorkspacePanelID: CGFloat],
        nextValue: () -> [WorkspacePanelID: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func reportWorkspacePanelWidth(_ id: WorkspacePanelID) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: WorkspacePanelWidthPreferenceKey.self,
                    value: [id: proxy.size.width]
                )
            }
        }
    }
}
