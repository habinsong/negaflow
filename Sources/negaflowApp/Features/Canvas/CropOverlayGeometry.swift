import CoreGraphics

enum CropOverlayGeometry {
    static func selectionRect(
        from start: CGPoint,
        to end: CGPoint,
        unitAspectRatio: CGFloat?
    ) -> CGRect {
        guard let unitAspectRatio else { return unitRect(from: start, to: end) }
        return lockedCornerRect(
            anchor: start,
            point: end,
            unitAspectRatio: unitAspectRatio
        )
    }

    static func lockedHandleRect(
        _ handle: CropHandle,
        start: CGRect,
        point: CGPoint,
        unitAspectRatio: CGFloat
    ) -> CGRect {
        switch handle {
        case .topLeft:
            lockedCornerRect(anchor: CGPoint(x: start.maxX, y: start.maxY), point: point, unitAspectRatio: unitAspectRatio)
        case .topRight:
            lockedCornerRect(anchor: CGPoint(x: start.minX, y: start.maxY), point: point, unitAspectRatio: unitAspectRatio)
        case .bottomRight:
            lockedCornerRect(anchor: CGPoint(x: start.minX, y: start.minY), point: point, unitAspectRatio: unitAspectRatio)
        case .bottomLeft:
            lockedCornerRect(anchor: CGPoint(x: start.maxX, y: start.minY), point: point, unitAspectRatio: unitAspectRatio)
        case .top:
            lockedHorizontalEdgeRect(start: start, point: point, fixedY: start.maxY, growsDown: false, unitAspectRatio: unitAspectRatio)
        case .bottom:
            lockedHorizontalEdgeRect(start: start, point: point, fixedY: start.minY, growsDown: true, unitAspectRatio: unitAspectRatio)
        case .left:
            lockedVerticalEdgeRect(start: start, point: point, fixedX: start.maxX, growsRight: false, unitAspectRatio: unitAspectRatio)
        case .right:
            lockedVerticalEdgeRect(start: start, point: point, fixedX: start.minX, growsRight: true, unitAspectRatio: unitAspectRatio)
        }
    }

    private static func lockedCornerRect(
        anchor: CGPoint,
        point: CGPoint,
        unitAspectRatio: CGFloat
    ) -> CGRect {
        let signX: CGFloat = point.x >= anchor.x ? 1 : -1
        let signY: CGFloat = point.y >= anchor.y ? 1 : -1
        let maxWidth = signX > 0 ? 1 - anchor.x : anchor.x
        let maxHeight = signY > 0 ? 1 - anchor.y : anchor.y
        var width = min(max(abs(point.x - anchor.x), 0.035), maxWidth)
        var height = min(max(abs(point.y - anchor.y), 0.035), maxHeight)
        if width / max(height, 0.0001) > unitAspectRatio {
            width = height * unitAspectRatio
        } else {
            height = width / unitAspectRatio
        }
        if width > maxWidth {
            width = maxWidth
            height = width / unitAspectRatio
        }
        if height > maxHeight {
            height = maxHeight
            width = height * unitAspectRatio
        }
        return clampedUnitRect(CGRect(
            x: signX > 0 ? anchor.x : anchor.x - width,
            y: signY > 0 ? anchor.y : anchor.y - height,
            width: width,
            height: height
        ))
    }

    private static func lockedHorizontalEdgeRect(
        start: CGRect,
        point: CGPoint,
        fixedY: CGFloat,
        growsDown: Bool,
        unitAspectRatio: CGFloat
    ) -> CGRect {
        let centerX = start.midX
        let maxHeight = growsDown ? 1 - fixedY : fixedY
        var height = min(max(abs(point.y - fixedY), 0.035), maxHeight)
        var width = height * unitAspectRatio
        let maxWidth = max(0.035, 2 * min(centerX, 1 - centerX))
        if width > maxWidth {
            width = maxWidth
            height = width / unitAspectRatio
        }
        return clampedUnitRect(CGRect(
            x: centerX - width / 2,
            y: growsDown ? fixedY : fixedY - height,
            width: width,
            height: height
        ))
    }

    private static func lockedVerticalEdgeRect(
        start: CGRect,
        point: CGPoint,
        fixedX: CGFloat,
        growsRight: Bool,
        unitAspectRatio: CGFloat
    ) -> CGRect {
        let centerY = start.midY
        let maxWidth = growsRight ? 1 - fixedX : fixedX
        var width = min(max(abs(point.x - fixedX), 0.035), maxWidth)
        var height = width / unitAspectRatio
        let maxHeight = max(0.035, 2 * min(centerY, 1 - centerY))
        if height > maxHeight {
            height = maxHeight
            width = height * unitAspectRatio
        }
        return clampedUnitRect(CGRect(
            x: growsRight ? fixedX : fixedX - width,
            y: centerY - height / 2,
            width: width,
            height: height
        ))
    }
}
