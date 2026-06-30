import SwiftUI

let canvasCoordinateSpace = "negaflow.canvas"

func clampedUnitRect(_ rect: CGRect, minimumSize: CGFloat = 0.035) -> CGRect {
    let width = min(max(rect.width, minimumSize), 1)
    let height = min(max(rect.height, minimumSize), 1)
    let x = min(max(rect.minX, 0), 1 - width)
    let y = min(max(rect.minY, 0), 1 - height)
    return CGRect(x: x, y: y, width: width, height: height)
}

func unitRect(from a: CGPoint, to b: CGPoint) -> CGRect {
    clampedUnitRect(CGRect(
        x: min(a.x, b.x),
        y: min(a.y, b.y),
        width: abs(a.x - b.x),
        height: abs(a.y - b.y)
    ))
}

func engineCrop(from visibleCrop: CGRect, existingCrop: SIMD4<Double>?) -> SIMD4<Double>? {
    let visible = clampedUnitRect(visibleCrop)
    guard visible.width < 0.995 || visible.height < 0.995 else {
        return existingCrop
    }
    let crop = SIMD4(
        Double(visible.minX),
        Double(1 - visible.maxY),
        Double(visible.width),
        Double(visible.height)
    )
    guard let existingCrop else {
        return crop
    }
    return SIMD4(
        existingCrop.x + crop.x * existingCrop.z,
        existingCrop.y + crop.y * existingCrop.w,
        crop.z * existingCrop.z,
        crop.w * existingCrop.w
    )
}
