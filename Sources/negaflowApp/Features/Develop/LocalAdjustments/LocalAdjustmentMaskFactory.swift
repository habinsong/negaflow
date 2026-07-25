import Foundation
import CoreGraphics
import Chromabase

enum LocalAdjustmentMaskFactory {
    static func make(
        kind: LocalDodgeBurnMask.Kind,
        points: [LocalDodgeBurnPoint],
        thickness: Double,
        feather: Double,
        imageSize: CGSize? = nil
    ) -> LocalDodgeBurnMask? {
        let feather = min(max(feather, 0), 1)
        switch kind {
        case .brush:
            guard !points.isEmpty else { return nil }
            return .brush(strokes: [LocalDodgeBurnStroke(
                points: points,
                thickness: min(max(thickness, 0.005), 0.25),
                feather: feather * 0.25
            )])
        case .radial:
            guard let start = points.first, let end = points.last, points.count >= 2 else { return nil }
            let radius = radialRadius(from: start, to: end, imageSize: imageSize)
            return .radial(
                center: start,
                radius: max(0.005, radius),
                feather: feather
            )
        case .linear:
            guard let start = points.first, let end = points.last, points.count >= 2,
                  hypot(start.x - end.x, start.y - end.y) > 0.001 else { return nil }
            return .linear(start: start, end: end, feather: feather)
        case .polygon:
            guard points.count >= 3 else { return nil }
            return .polygon(points: points, feather: feather)
        }
    }

    private static func radialRadius(
        from start: LocalDodgeBurnPoint,
        to end: LocalDodgeBurnPoint,
        imageSize: CGSize?
    ) -> Double {
        guard let imageSize, imageSize.width > 0, imageSize.height > 0 else {
            return hypot(start.x - end.x, start.y - end.y)
        }
        let minimumDimension = min(imageSize.width, imageSize.height)
        let dx = (start.x - end.x) * imageSize.width
        let dy = (start.y - end.y) * imageSize.height
        return hypot(dx, dy) / minimumDimension
    }
}
