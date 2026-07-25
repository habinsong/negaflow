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

        XCTAssertFalse(layout.persistsPanelWidths)
        XCTAssertGreaterThanOrEqual(layout.panelMinimumWidth, 220)
        XCTAssertLessThanOrEqual(
            layout.panelIdealMaximumWidth * 2 + layout.centerMinimumWidth,
            900
        )
        XCTAssertLessThanOrEqual(
            layout.libraryControlsMaximumWidth + layout.libraryBrowserMinimumWidth,
            900
        )
    }

    func testRegularLayoutRestoresResizablePanelRange() {
        let layout = WorkspaceAdaptiveLayout(availableWidth: 1_400)

        XCTAssertTrue(layout.persistsPanelWidths)
        XCTAssertEqual(layout.panelMinimumWidth, 430)
        XCTAssertEqual(
            layout.panelIdealMaximumWidth,
            WorkspaceAdaptiveLayout.developPanelDefaultWidth
        )
        XCTAssertEqual(layout.libraryControlsMinimumWidth, 430)
        XCTAssertEqual(
            layout.libraryControlsMaximumWidth,
            WorkspaceAdaptiveLayout.libraryControlsDefaultWidth
        )
        XCTAssertEqual(layout.panelIdealWidth(440), WorkspaceAdaptiveLayout.developPanelDefaultWidth)
        XCTAssertEqual(
            layout.libraryControlsIdealWidth(432),
            WorkspaceAdaptiveLayout.libraryControlsDefaultWidth
        )
    }

    func testStoredWidthsAreClampedWithoutBreakingCompactLayout() {
        let layout = WorkspaceAdaptiveLayout(availableWidth: 900)

        XCTAssertEqual(layout.panelIdealWidth(100), layout.panelMinimumWidth)
        XCTAssertEqual(layout.panelIdealWidth(900), layout.panelIdealMaximumWidth)
        XCTAssertEqual(
            layout.libraryControlsIdealWidth(900),
            layout.libraryControlsMaximumWidth
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
