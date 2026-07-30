import CoreGraphics
import XCTest
@testable import Chromabase
@testable import ScannerKit
@testable import negaflowApp

/// 평판 프리뷰 위에 프레임을 놓는 위치/방향 규칙.
final class FlatbedScanRegionLayoutTests: XCTestCase {
    /// A4 평판(세로가 긴 유리면). 홀더는 긴 축을 따라 놓인다.
    private let portraitBed = ScanArea(
        originXMM: 0,
        originYMM: 0,
        widthMM: 216,
        heightMM: 297
    )
    private let landscapeBed = ScanArea(
        originXMM: 0,
        originYMM: 0,
        widthMM: 297,
        heightMM: 216
    )

    func testFirstFrameFollowsTheLongAxisOfTheScanArea() throws {
        let portrait = try XCTUnwrap(FlatbedScanRegionLayout.proposedRect(
            existing: [],
            frameFormat: .fullFrame35mm,
            previewArea: portraitBed
        ))
        // 세로로 긴 유리면 → 36mm가 세로(Y), 24mm가 가로(X).
        XCTAssertEqual(Double(portrait.width) * portraitBed.widthMM, 24, accuracy: 0.001)
        XCTAssertEqual(Double(portrait.height) * portraitBed.heightMM, 36, accuracy: 0.001)
        XCTAssertEqual(portrait.midX, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(portrait.midY, 0.5, accuracy: 0.000_001)

        let landscape = try XCTUnwrap(FlatbedScanRegionLayout.proposedRect(
            existing: [],
            frameFormat: .fullFrame35mm,
            previewArea: landscapeBed
        ))
        XCTAssertEqual(Double(landscape.width) * landscapeBed.widthMM, 36, accuracy: 0.001)
        XCTAssertEqual(Double(landscape.height) * landscapeBed.heightMM, 24, accuracy: 0.001)
    }

    /// 프레임 좌표는 프리뷰로 실제 훑은 영역 기준이다 — 최대 영역으로 계산하면 규격이 어긋난다.
    func testFrameKeepsItsPhysicalSizeWhenThePreviewAreaIsSmallerThanTheBed() throws {
        let previewArea = ScanArea(originXMM: 20, originYMM: 30, widthMM: 108, heightMM: 148)
        let capabilities = ScannerCapabilities(
            supportsScanArea: true,
            supportsPositionedScanArea: true,
            maxScanArea: portraitBed,
            minScanArea: ScanArea(originXMM: 0, originYMM: 0, widthMM: 1, heightMM: 1)
        )
        let rect = try XCTUnwrap(FlatbedScanRegionLayout.proposedRect(
            existing: [],
            frameFormat: .fullFrame35mm,
            previewArea: previewArea
        ))
        let physical = try XCTUnwrap(FlatbedScanRegionGeometry.physicalArea(
            for: FlatbedScanRegion(unitRect: rect),
            previewScanArea: previewArea,
            capabilities: capabilities
        ))
        XCTAssertEqual(physical.widthMM, 24, accuracy: 0.001)
        XCTAssertEqual(physical.heightMM, 36, accuracy: 0.001)
    }

    func testNextFrameContinuesTheStripFromTheLastFrame() throws {
        let first = try XCTUnwrap(FlatbedScanRegionLayout.proposedRect(
            existing: [],
            frameFormat: .fullFrame35mm,
            previewArea: portraitBed
        ))
        let second = try XCTUnwrap(FlatbedScanRegionLayout.proposedRect(
            existing: [first],
            frameFormat: .fullFrame35mm,
            previewArea: portraitBed
        ))
        XCTAssertEqual(second.size, first.size)
        XCTAssertEqual(second.minX, first.minX, accuracy: 0.000_001)
        // 스트립 진행 축(세로)으로 프레임 간격 2mm 만큼 띄우고 이어 붙는다.
        XCTAssertEqual(
            Double(second.minY - first.maxY) * portraitBed.heightMM,
            FlatbedScanRegionLayout.frameGapMM,
            accuracy: 0.001
        )
    }

    func testStripEndWrapsToTheNextStripAtTheStartingPosition() throws {
        let frame = CGRect(x: 0.1, y: 0.8, width: 0.1111, height: 0.1212)
        let first = CGRect(x: 0.1, y: 0.05, width: 0.1111, height: 0.1212)
        let wrapped = try XCTUnwrap(FlatbedScanRegionLayout.proposedRect(
            existing: [first, frame],
            frameFormat: .fullFrame35mm,
            previewArea: portraitBed
        ))
        XCTAssertEqual(wrapped.minY, first.minY, accuracy: 0.000_001)
        XCTAssertEqual(
            Double(wrapped.minX - frame.maxX) * portraitBed.widthMM,
            FlatbedScanRegionLayout.frameGapMM,
            accuracy: 0.001
        )
    }

    func testFrameFallsBackToTheCenterWhenNeitherDirectionFits() throws {
        let full = CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.96)
        let rect = try XCTUnwrap(FlatbedScanRegionLayout.proposedRect(
            existing: [full],
            frameFormat: .fullFrame35mm,
            previewArea: portraitBed
        ))
        XCTAssertEqual(rect.size, full.size)
        XCTAssertEqual(rect.midX, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(rect.midY, 0.5, accuracy: 0.000_001)
    }

    /// 손으로 그린 사각형은 규격 비율로 맞춰진다 — 눈으로는 6×7인지 알 수 없다.
    func testHandDrawnRectSnapsToTheFrameAspectInMillimetres() {
        let start = CGPoint(x: 0.1, y: 0.1)
        let drawn = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.3)
        let snapped = FlatbedScanRegionLayout.snappedToFrameAspect(
            drawn,
            anchoredTo: CGRect(origin: start, size: .zero),
            frameFormat: .medium67,
            previewArea: portraitBed
        )
        let aspect = Double(snapped.width) * portraitBed.widthMM
            / (Double(snapped.height) * portraitBed.heightMM)
        // 세로로 그렸으므로 세로 방향 6×7(55:69)로 맞는다.
        XCTAssertEqual(aspect, 55.0 / 69.0, accuracy: 0.002)
        // 그린 영역 밖으로 커지지 않고, 드래그를 시작한 모서리는 그대로다.
        XCTAssertEqual(snapped.minX, drawn.minX, accuracy: 0.000_001)
        XCTAssertEqual(snapped.minY, drawn.minY, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(snapped.maxX, drawn.maxX + 0.000_001)
        XCTAssertLessThanOrEqual(snapped.maxY, drawn.maxY + 0.000_001)
    }

    func testDraggingOneEdgeDrivesTheOtherAxisAroundTheUnchangedCentre() {
        let previous = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1824)
        let widened = CGRect(x: 0.1, y: 0.1, width: 0.25, height: 0.1824)
        let snapped = FlatbedScanRegionLayout.snappedToFrameAspect(
            widened,
            anchoredTo: previous,
            frameFormat: .medium67,
            previewArea: portraitBed
        )
        // 끈 축(가로)은 커서를 그대로 따르고, 세로가 따라온다.
        XCTAssertEqual(snapped.width, widened.width, accuracy: 0.000_001)
        XCTAssertEqual(snapped.minX, widened.minX, accuracy: 0.000_001)
        XCTAssertGreaterThan(snapped.height, previous.height)
        XCTAssertEqual(snapped.midY, previous.midY, accuracy: 0.000_001)
        let aspect = Double(snapped.width) * portraitBed.widthMM
            / (Double(snapped.height) * portraitBed.heightMM)
        XCTAssertEqual(aspect, 55.0 / 69.0, accuracy: 0.002)
    }

    func testResizingFromAHandleKeepsTheOppositeEdgeInPlace() {
        let previous = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.25)
        let dragged = CGRect(x: 0.15, y: 0.12, width: 0.35, height: 0.43)
        let snapped = FlatbedScanRegionLayout.snappedToFrameAspect(
            dragged,
            anchoredTo: previous,
            frameFormat: .fullFrame35mm,
            previewArea: portraitBed
        )
        XCTAssertEqual(snapped.maxX, previous.maxX, accuracy: 0.000_001)
        XCTAssertEqual(snapped.maxY, previous.maxY, accuracy: 0.000_001)
        let aspect = Double(snapped.width) * portraitBed.widthMM
            / (Double(snapped.height) * portraitBed.heightMM)
        XCTAssertEqual(aspect, 24.0 / 36.0, accuracy: 0.002)
    }

    /// 이동은 크기를 건드리지 않는다 — 비율에도 손대지 않는다.
    func testMovingAFrameLeavesItUntouched() {
        let previous = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
        let moved = previous.offsetBy(dx: 0.2, dy: 0.1)
        XCTAssertEqual(
            FlatbedScanRegionLayout.snappedToFrameAspect(
                moved,
                anchoredTo: moved,
                frameFormat: .medium67,
                previewArea: portraitBed
            ),
            moved
        )
    }

    /// 붙여넣기는 규격이 아니라 복사해 둔 크기로 놓는다 — 손으로 맞춘 크기를 복제하려는 것이다.
    func testPasteSizeOverridesTheFormatAndStillAdvancesPastTheLastFrame() throws {
        let last = CGRect(x: 0.4, y: 0.1, width: 0.1, height: 0.2)
        let copied = CGSize(width: 0.13, height: 0.26)

        let pasted = try XCTUnwrap(FlatbedScanRegionLayout.proposedRect(
            existing: [last],
            frameFormat: .fullFrame35mm,
            previewArea: portraitBed,
            size: copied
        ))

        XCTAssertEqual(pasted.size, copied)
        let gap = CGFloat(FlatbedScanRegionLayout.frameGapMM / portraitBed.heightMM)
        // 세로가 긴 프레임이므로 아래로 진행한다.
        XCTAssertEqual(pasted.minY, last.maxY + gap, accuracy: 0.000_001)
        XCTAssertEqual(pasted.minX, last.minX, accuracy: 0.000_001)
    }

    func testNudgeStepIsMeasuredInMillimetres() {
        let fine = FlatbedScanRegionLayout.nudgeStep(previewArea: portraitBed, coarse: false)
        XCTAssertEqual(
            Double(fine.width) * portraitBed.widthMM,
            FlatbedScanRegionLayout.nudgeStepMM,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            Double(fine.height) * portraitBed.heightMM,
            FlatbedScanRegionLayout.nudgeStepMM,
            accuracy: 0.000_001
        )

        let coarse = FlatbedScanRegionLayout.nudgeStep(previewArea: portraitBed, coarse: true)
        XCTAssertEqual(
            Double(coarse.height) * portraitBed.heightMM,
            FlatbedScanRegionLayout.frameGapMM,
            accuracy: 0.000_001
        )

        // 프리뷰 영역을 모르면 물리 거리로 환산할 수 없다. 그래도 움직이기는 해야 한다.
        let unknown = FlatbedScanRegionLayout.nudgeStep(previewArea: nil, coarse: false)
        XCTAssertGreaterThan(unknown.width, 0)
        XCTAssertGreaterThan(unknown.height, 0)
    }

    func testDegenerateScanAreaProposesNothing() {
        XCTAssertNil(FlatbedScanRegionLayout.proposedRect(
            existing: [],
            frameFormat: .fullFrame35mm,
            previewArea: ScanArea(originXMM: 0, originYMM: 0, widthMM: 0, heightMM: 297)
        ))
    }
}
