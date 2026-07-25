import CoreGraphics

enum CanvasHUDKind: Hashable {
    case compare
    case zoom
}
struct CanvasHUDOrigins: Equatable {
    var compare: CGPoint
    var zoom: CGPoint
}

struct CanvasHUDInteractionState {
    var compareOrigin: CGPoint?
    var zoomOrigin: CGPoint?
    var compareDragStart: CGPoint?
    var zoomDragStart: CGPoint?
    var compareSize = CGSize(width: 220, height: 32)
    var zoomSize = CGSize(width: 136, height: 32)
}

enum CanvasHUDPlacement {
    static let margin: CGFloat = 12
    static let collisionGap: CGFloat = 8

    static func defaultOrigins(
        canvasSize: CGSize,
        compareSize: CGSize,
        zoomSize: CGSize
    ) -> CanvasHUDOrigins {
        let compare = clampedOrigin(
            CGPoint(x: margin, y: margin),
            hudSize: compareSize,
            canvasSize: canvasSize
        )
        let proposedZoom = clampedOrigin(
            CGPoint(x: canvasSize.width - margin - zoomSize.width, y: margin),
            hudSize: zoomSize,
            canvasSize: canvasSize
        )
        let zoom = avoidingOverlap(
            proposedOrigin: proposedZoom,
            movingSize: zoomSize,
            otherOrigin: compare,
            otherSize: compareSize,
            canvasSize: canvasSize
        )
        return CanvasHUDOrigins(compare: compare, zoom: zoom)
    }

    static func clampedOrigin(
        _ origin: CGPoint,
        hudSize: CGSize,
        canvasSize: CGSize
    ) -> CGPoint {
        let maximumX = max(margin, canvasSize.width - margin - hudSize.width)
        let maximumY = max(margin, canvasSize.height - margin - hudSize.height)
        return CGPoint(
            x: min(max(origin.x, margin), maximumX),
            y: min(max(origin.y, margin), maximumY)
        )
    }

    static func avoidingOverlap(
        proposedOrigin: CGPoint,
        movingSize: CGSize,
        otherOrigin: CGPoint,
        otherSize: CGSize,
        canvasSize: CGSize
    ) -> CGPoint {
        let proposed = clampedOrigin(
            proposedOrigin,
            hudSize: movingSize,
            canvasSize: canvasSize
        )
        let movingRect = CGRect(origin: proposed, size: movingSize)
        let otherRect = CGRect(origin: otherOrigin, size: otherSize)
            .insetBy(dx: -collisionGap, dy: -collisionGap)
        guard movingRect.intersects(otherRect) else { return proposed }

        let movingCenter = CGPoint(
            x: proposed.x + movingSize.width / 2,
            y: proposed.y + movingSize.height / 2
        )
        let delta = CGPoint(
            x: movingCenter.x - otherRect.midX,
            y: movingCenter.y - otherRect.midY
        )
        let preferredSides = sidePriority(for: delta)

        for side in preferredSides {
            let candidate = candidateOrigin(
                on: side,
                proposed: proposed,
                movingSize: movingSize,
                expandedOtherRect: otherRect,
                canvasSize: canvasSize
            )
            let candidateRect = CGRect(origin: candidate, size: movingSize)
            if !candidateRect.intersects(otherRect) {
                return candidate
            }
        }
        return proposed
    }

    private enum Side {
        case left
        case right
        case top
        case bottom
    }

    private static func sidePriority(for delta: CGPoint) -> [Side] {
        let horizontal: [Side] = delta.x < 0 ? [.left, .right] : [.right, .left]
        let vertical: [Side] = delta.y < 0 ? [.top, .bottom] : [.bottom, .top]
        return abs(delta.x) >= abs(delta.y)
            ? [horizontal[0], vertical[0], vertical[1], horizontal[1]]
            : [vertical[0], horizontal[0], horizontal[1], vertical[1]]
    }

    private static func candidateOrigin(
        on side: Side,
        proposed: CGPoint,
        movingSize: CGSize,
        expandedOtherRect: CGRect,
        canvasSize: CGSize
    ) -> CGPoint {
        let raw: CGPoint
        switch side {
        case .left:
            raw = CGPoint(
                x: expandedOtherRect.minX - movingSize.width,
                y: proposed.y
            )
        case .right:
            raw = CGPoint(x: expandedOtherRect.maxX, y: proposed.y)
        case .top:
            raw = CGPoint(
                x: proposed.x,
                y: expandedOtherRect.minY - movingSize.height
            )
        case .bottom:
            raw = CGPoint(x: proposed.x, y: expandedOtherRect.maxY)
        }
        return clampedOrigin(raw, hudSize: movingSize, canvasSize: canvasSize)
    }
}
