import AppKit
import XCTest
@testable import negaflowApp

final class CanvasViewportStateTests: XCTestCase {
    func testSetScaleClampsAndKeepsCommittedStateInSync() {
        var viewport = CanvasViewportState()

        viewport.setScale(40, imageSize: NSSize(width: 1000, height: 800), canvasSize: CGSize(width: 500, height: 400))

        XCTAssertEqual(viewport.scale, viewport.maxScale)
        XCTAssertEqual(viewport.lastScale, viewport.maxScale)
        XCTAssertEqual(viewport.offset, viewport.lastOffset)
    }

    func testPanUsesCommittedOffsetAndClampsToCanvasBounds() {
        var viewport = CanvasViewportState()
        let imageSize = NSSize(width: 1000, height: 800)
        let canvasSize = CGSize(width: 500, height: 400)

        viewport.setScale(2, imageSize: imageSize, canvasSize: canvasSize)
        viewport.updatePan(translation: CGSize(width: 10_000, height: -10_000), imageSize: imageSize, canvasSize: canvasSize)

        XCTAssertEqual(viewport.offset.width, 266)
        XCTAssertEqual(viewport.offset.height, -232)

        viewport.endPan()
        XCTAssertEqual(viewport.lastOffset, viewport.offset)
    }

    func testMagnificationUsesLastCommittedScaleUntilEnded() {
        var viewport = CanvasViewportState()
        let imageSize = NSSize(width: 1000, height: 800)
        let canvasSize = CGSize(width: 500, height: 400)

        viewport.setScale(2, imageSize: imageSize, canvasSize: canvasSize)
        viewport.updateMagnification(1.5, imageSize: imageSize, canvasSize: canvasSize)

        XCTAssertEqual(viewport.scale, 3)
        XCTAssertEqual(viewport.lastScale, 2)

        viewport.endMagnification()

        XCTAssertEqual(viewport.lastScale, 3)
        XCTAssertEqual(viewport.lastOffset, viewport.offset)
    }
}
