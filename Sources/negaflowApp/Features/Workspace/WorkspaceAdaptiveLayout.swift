import Foundation

struct WorkspaceAdaptiveLayout: Equatable {
    static let regularWidthThreshold: CGFloat = 1_340
    static let developPanelDefaultWidth: CGFloat = 430
    static let libraryControlsDefaultWidth: CGFloat = 430

    let panelMinimumWidth: CGFloat
    let panelIdealMaximumWidth: CGFloat
    let centerMinimumWidth: CGFloat
    let libraryControlsMinimumWidth: CGFloat
    let libraryControlsMaximumWidth: CGFloat
    let libraryBrowserMinimumWidth: CGFloat
    let persistsPanelWidths: Bool

    init(availableWidth: CGFloat) {
        let width = max(900, availableWidth)
        let isRegular = width >= Self.regularWidthThreshold
        panelMinimumWidth = isRegular ? Self.developPanelDefaultWidth : 220
        centerMinimumWidth = isRegular ? 480 : 400
        panelIdealMaximumWidth = isRegular
            ? Self.developPanelDefaultWidth
            : max(
                panelMinimumWidth,
                min(Self.developPanelDefaultWidth, (width - centerMinimumWidth) / 2)
            )
        libraryControlsMinimumWidth = isRegular ? Self.libraryControlsDefaultWidth : 240
        libraryControlsMaximumWidth = isRegular
            ? Self.libraryControlsDefaultWidth
            : min(Self.libraryControlsDefaultWidth, width * 0.38)
        libraryBrowserMinimumWidth = isRegular ? 560 : 420
        persistsPanelWidths = isRegular
    }

    func panelIdealWidth(_ storedWidth: CGFloat) -> CGFloat {
        min(max(storedWidth, panelMinimumWidth), panelIdealMaximumWidth)
    }

    func libraryControlsIdealWidth(_ storedWidth: CGFloat) -> CGFloat {
        min(max(storedWidth, libraryControlsMinimumWidth), libraryControlsMaximumWidth)
    }
}
