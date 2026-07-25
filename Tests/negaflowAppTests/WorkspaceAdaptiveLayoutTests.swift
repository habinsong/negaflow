import XCTest
@testable import negaflowApp

@MainActor
final class WorkspaceAdaptiveLayoutTests: XCTestCase {
    func testRequestedDefaultPanelWidthsAreFourHundredThirtyPoints() {
        XCTAssertEqual(WorkspaceAdaptiveLayout.developPanelDefaultWidth, 430)
        XCTAssertEqual(WorkspaceAdaptiveLayout.libraryControlsDefaultWidth, 430)
    }

    func testCompactLayoutFitsBothPanelsAndCanvasAtMinimumWindowWidth() {
        let layout = WorkspaceAdaptiveLayout(availableWidth: 900)

        XCTAssertGreaterThanOrEqual(layout.panelMinimumWidth, 220)
        XCTAssertLessThanOrEqual(
            layout.panelMaximumWidth * 2 + layout.centerMinimumWidth,
            900
        )
        XCTAssertLessThanOrEqual(
            layout.libraryControlsMaximumWidth + layout.libraryBrowserMinimumWidth,
            900
        )
        XCTAssertLessThanOrEqual(layout.panelWidthRange.lowerBound, layout.panelWidthRange.upperBound)
    }

    /// 좌측탭/우측탭은 고정이 아니라 가변이다 — 기본값 430pt 는 범위 안에 들어 있어야 하고,
    /// 어떤 폭에서도 두 패널 + 중앙 최소폭이 창 안에 들어가야 한다.
    func testRegularLayoutAllowsResizingAroundTheDefaultPanelWidth() {
        let layout = WorkspaceAdaptiveLayout(availableWidth: 1_400)

        XCTAssertEqual(layout.panelMinimumWidth, WorkspaceAdaptiveLayout.panelResizableMinimumWidth)
        XCTAssertGreaterThan(
            layout.panelMaximumWidth,
            WorkspaceAdaptiveLayout.developPanelDefaultWidth
        )
        XCTAssertTrue(
            layout.panelWidthRange.contains(WorkspaceAdaptiveLayout.developPanelDefaultWidth),
            "기본 폭은 항상 조절 범위 안에 있어야 한다"
        )
        XCTAssertLessThanOrEqual(
            layout.panelMaximumWidth * 2 + layout.centerMinimumWidth,
            1_400
        )

        XCTAssertTrue(
            layout.libraryControlsWidthRange
                .contains(WorkspaceAdaptiveLayout.libraryControlsDefaultWidth),
            "라이브러리 좌측탭도 기본 폭을 포함한 범위여야 한다(고정 금지)"
        )
        XCTAssertGreaterThan(
            layout.libraryControlsMaximumWidth,
            layout.libraryControlsMinimumWidth,
            "라이브러리 좌측탭이 고정되면 크기 조절이 불가능하다"
        )
        XCTAssertLessThanOrEqual(
            layout.libraryControlsMaximumWidth + layout.libraryBrowserMinimumWidth,
            1_400
        )
    }

    /// 창을 임계 폭까지 좁혀도 패널 최대폭이 중앙 캔버스를 최소폭 아래로 밀지 않는다.
    func testRegularPanelMaximumNeverStarvesTheCanvasAtThresholdWidth() {
        let layout = WorkspaceAdaptiveLayout(
            availableWidth: WorkspaceAdaptiveLayout.regularWidthThreshold
        )

        XCTAssertLessThanOrEqual(
            layout.panelMaximumWidth * 2 + layout.centerMinimumWidth,
            WorkspaceAdaptiveLayout.regularWidthThreshold
        )
        XCTAssertGreaterThanOrEqual(
            layout.panelMaximumWidth,
            WorkspaceAdaptiveLayout.developPanelDefaultWidth
        )
    }

    func testToolbarPhotoControlsHideBeforeTheyCanOverlapWorkspaceLinks() {
        XCTAssertFalse(WorkspaceToolbarLayout.showsPhotoControls(availableWidth: 1_400))
        XCTAssertTrue(WorkspaceToolbarLayout.showsPhotoControls(availableWidth: 1_600))
    }

    func testLibraryBottomControlsUseSharedWidth() {
        XCTAssertEqual(LibraryViewModePicker.controlWidth, 280)
    }

    func testLibraryGridCardUsesHalvedMatchedMetadataSpacing() {
        XCTAssertEqual(LibraryGridCardLayout.thumbnailTitleSpacing, 3)
        XCTAssertEqual(LibraryGridCardLayout.ratingControlHeight, 14)
    }

    func testRegularFilmstripCardReservesAThreeByTwoThumbnail() {
        let height = 152.0
        let width = FilmstripSizing.cardWidth(forItemHeight: height)

        XCTAssertEqual((width - 16) / (height - 57), 1.5, accuracy: 1e-9)
    }
}
