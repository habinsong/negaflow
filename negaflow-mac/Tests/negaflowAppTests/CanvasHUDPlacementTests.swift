import CoreGraphics
import XCTest
@testable import negaflowApp

final class CanvasHUDPlacementTests: XCTestCase {
    func testDefaultOriginsUseOppositeTopCornersWithoutOverlap() {
        let canvas = CGSize(width: 800, height: 600)
        let compare = CGSize(width: 220, height: 32)
        let zoom = CGSize(width: 136, height: 32)

        let origins = CanvasHUDPlacement.defaultOrigins(
            canvasSize: canvas,
            compareSize: compare,
            zoomSize: zoom
        )

        XCTAssertEqual(origins.compare, CGPoint(x: 12, y: 12))
        XCTAssertEqual(origins.zoom, CGPoint(x: 652, y: 12))
        XCTAssertFalse(
            CGRect(origin: origins.compare, size: compare)
                .insetBy(dx: -CanvasHUDPlacement.collisionGap, dy: -CanvasHUDPlacement.collisionGap)
                .intersects(CGRect(origin: origins.zoom, size: zoom))
        )
    }

    func testOriginStaysInsideCanvasMargins() {
        let canvas = CGSize(width: 500, height: 300)
        let size = CGSize(width: 120, height: 32)

        XCTAssertEqual(
            CanvasHUDPlacement.clampedOrigin(
                CGPoint(x: -100, y: 900),
                hudSize: size,
                canvasSize: canvas
            ),
            CGPoint(x: 12, y: 256)
        )
    }

    func testHorizontalDragPassesToOppositeSideWithoutOverlap() {
        let canvas = CGSize(width: 800, height: 600)
        let movingSize = CGSize(width: 136, height: 32)
        let otherOrigin = CGPoint(x: 300, y: 100)
        let otherSize = CGSize(width: 220, height: 32)

        let left = CanvasHUDPlacement.avoidingOverlap(
            proposedOrigin: CGPoint(x: 280, y: 100),
            movingSize: movingSize,
            otherOrigin: otherOrigin,
            otherSize: otherSize,
            canvasSize: canvas
        )
        let right = CanvasHUDPlacement.avoidingOverlap(
            proposedOrigin: CGPoint(x: 470, y: 100),
            movingSize: movingSize,
            otherOrigin: otherOrigin,
            otherSize: otherSize,
            canvasSize: canvas
        )

        XCTAssertEqual(left.x, 156)
        XCTAssertEqual(right.x, 528)
        let expandedOther = CGRect(origin: otherOrigin, size: otherSize)
            .insetBy(dx: -CanvasHUDPlacement.collisionGap, dy: -CanvasHUDPlacement.collisionGap)
        XCTAssertFalse(CGRect(origin: left, size: movingSize).intersects(expandedOther))
        XCTAssertFalse(CGRect(origin: right, size: movingSize).intersects(expandedOther))
    }

    func testVerticalDragPassesBelowWithoutOverlap() {
        let canvas = CGSize(width: 800, height: 600)
        let movingSize = CGSize(width: 136, height: 32)
        let otherOrigin = CGPoint(x: 300, y: 100)
        let otherSize = CGSize(width: 220, height: 32)

        let below = CanvasHUDPlacement.avoidingOverlap(
            proposedOrigin: CGPoint(x: 340, y: 125),
            movingSize: movingSize,
            otherOrigin: otherOrigin,
            otherSize: otherSize,
            canvasSize: canvas
        )

        XCTAssertEqual(below.y, 140)
        let expandedOther = CGRect(origin: otherOrigin, size: otherSize)
            .insetBy(dx: -CanvasHUDPlacement.collisionGap, dy: -CanvasHUDPlacement.collisionGap)
        XCTAssertFalse(CGRect(origin: below, size: movingSize).intersects(expandedOther))
    }
}
