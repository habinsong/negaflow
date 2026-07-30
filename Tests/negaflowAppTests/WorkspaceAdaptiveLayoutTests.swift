import AppKit
import Chromabase
import XCTest
@testable import negaflowApp

@MainActor
final class WorkspaceAdaptiveLayoutTests: XCTestCase {
    func testFilmstripSkipsAutomaticFarScrollForLargeCatalogs() {
        XCTAssertTrue(WorkspaceFilmstrip.allowsAutomaticScroll(frameCount: 256))
        XCTAssertFalse(WorkspaceFilmstrip.allowsAutomaticScroll(frameCount: 257))
        XCTAssertFalse(WorkspaceFilmstrip.allowsAutomaticScroll(frameCount: 2_000))
    }

    func testDevelopAndPrintFilmstripsUseDevelopedScannerThumbnailForEveryFilmType() {
        for (index, filmType) in FilmType.allCases.enumerated() {
            let frame = ScanFrame(
                scanIndex: index + 1,
                rawScanURL: URL(fileURLWithPath: "/tmp/scanner-\(index).tiff"),
                filmType: filmType,
                sourceKind: .scannerTIFF
            )
            frame.rawPreviewImage = NSImage(size: NSSize(width: 2, height: 2))
            let developed = NSImage(size: NSSize(width: 3, height: 3))
            frame.thumbnailImage = developed
            frame.hasDevelopedOnce = true

            XCTAssertEqual(presentationMode(for: frame, in: .library), .raw)
            XCTAssertEqual(presentationMode(for: frame, in: .develop), .developed)
            XCTAssertEqual(presentationMode(for: frame, in: .print), .developed)
            XCTAssertTrue(
                presentationMode(for: frame, in: .develop).previewImage(for: frame) === developed
            )
        }
    }

    func testNegativeFastPreviewSwitchesFilmstripBeforeFullDevelopmentSettles() {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/scanner-fast-preview.tiff"),
            filmType: .colorNegative,
            sourceKind: .scannerTIFF
        )
        frame.thumbnailImage = NSImage(size: NSSize(width: 3, height: 3))

        XCTAssertFalse(frame.hasDevelopedOnce)
        XCTAssertEqual(presentationMode(for: frame, in: .develop), .developed)
        XCTAssertEqual(presentationMode(for: frame, in: .print), .developed)
    }

    /// 현상 결과가 올라오면 곧바로 현상본으로 바뀌어야 한다 — 카드가 프레임을 관찰하며 직접
    /// 판단하므로, 부모 화면이 다시 그려지기를 기다리지 않는다.
    func testGridCardSwitchesToDevelopedRenditionAsSoonAsDevelopmentFinishes() {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/scanner-folder-apply.tiff"),
            filmType: .colorPositive,
            sourceKind: .importedFile
        )
        let raw = NSImage(size: NSSize(width: 2, height: 2))
        frame.rawPreviewImage = raw

        XCTAssertEqual(
            FrameStripPresentationMode.resolve(for: frame, policy: .developedWhenAvailable),
            .raw
        )

        let developed = NSImage(size: NSSize(width: 3, height: 3))
        frame.thumbnailImage = developed
        frame.hasDevelopedOnce = true

        let mode = FrameStripPresentationMode.resolve(for: frame, policy: .developedWhenAvailable)
        XCTAssertEqual(mode, .developed)
        XCTAssertTrue(mode.previewImage(for: frame) === developed)
        // 라이브러리 필름스트립은 규칙상 언제나 원본이다.
        XCTAssertEqual(FrameStripPresentationMode.resolve(for: frame, policy: .raw), .raw)
    }

    private func presentationMode(
        for frame: ScanFrame,
        in workspace: WorkspaceModule
    ) -> FrameStripPresentationMode {
        FrameStripPresentationMode.resolve(
            for: frame,
            policy: WorkspaceFilmstrip.presentationPolicy(for: workspace)
        )
    }

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
