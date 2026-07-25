import Foundation

struct WorkspaceAdaptiveLayout: Equatable {
    static let regularWidthThreshold: CGFloat = 1_340
    /// 좌측탭/우측탭의 **기본** 폭. 저장된 값이 없으면 이 폭으로 시작한다.
    static let developPanelDefaultWidth: CGFloat = 430
    static let libraryControlsDefaultWidth: CGFloat = 430
    /// 사용자가 끌어서 갈 수 있는 패널 폭 범위. 하한은 탭 레일(76pt)과 폼 컨트롤이 눌리지 않고
    /// 들어가는 폭, 상한은 중앙을 지나치게 밀어내지 않는 선이다. 실제 상한은 창 폭에 맞춰 다시
    /// 좁혀진다 — 패널과 중앙 최소폭이 항상 창 안에 들어가야 한다.
    static let panelResizableMinimumWidth: CGFloat = 300
    static let panelResizableMaximumWidth: CGFloat = 560

    let panelMinimumWidth: CGFloat
    let panelMaximumWidth: CGFloat
    let centerMinimumWidth: CGFloat
    let libraryControlsMinimumWidth: CGFloat
    let libraryControlsMaximumWidth: CGFloat
    let libraryBrowserMinimumWidth: CGFloat

    init(availableWidth: CGFloat) {
        let width = max(900, availableWidth)
        let isRegular = width >= Self.regularWidthThreshold
        panelMinimumWidth = isRegular ? Self.panelResizableMinimumWidth : 220
        centerMinimumWidth = isRegular ? 480 : 400
        // 좌우 패널이 둘 다 열려도 중앙이 최소폭을 지키도록 상한을 창 폭에서 유도한다.
        panelMaximumWidth = max(
            panelMinimumWidth,
            min(Self.panelResizableMaximumWidth, (width - centerMinimumWidth) / 2)
        )
        libraryControlsMinimumWidth = isRegular ? Self.panelResizableMinimumWidth : 240
        libraryBrowserMinimumWidth = isRegular ? 560 : 420
        libraryControlsMaximumWidth = max(
            libraryControlsMinimumWidth,
            min(Self.panelResizableMaximumWidth, width - libraryBrowserMinimumWidth)
        )
    }

    /// 현상/인화 좌우 패널이 가질 수 있는 폭 범위.
    var panelWidthRange: ClosedRange<CGFloat> { panelMinimumWidth...panelMaximumWidth }

    /// 라이브러리 좌측 패널이 가질 수 있는 폭 범위.
    var libraryControlsWidthRange: ClosedRange<CGFloat> {
        libraryControlsMinimumWidth...libraryControlsMaximumWidth
    }
}
