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

func canvasFitScale(_ imageSize: NSSize, in canvasSize: CGSize) -> CGFloat {
    guard imageSize.width > 0, imageSize.height > 0, canvasSize.width > 0, canvasSize.height > 0 else { return 1 }
    let padding: CGFloat = canvasSize.width > 180 && canvasSize.height > 180 ? 32 : 12
    let availableWidth = max(1, canvasSize.width - padding * 2)
    let availableHeight = max(1, canvasSize.height - padding * 2)
    return min(availableWidth / imageSize.width, availableHeight / imageSize.height)
}

func canvasFittedImageFrame(for imageSize: NSSize, in canvasSize: CGSize, scale: CGFloat, offset: CGSize) -> CGRect {
    let fit = canvasFitScale(imageSize, in: canvasSize) * scale
    let width = imageSize.width * fit
    let height = imageSize.height * fit
    return CGRect(
        x: (canvasSize.width - width) / 2 + offset.width,
        y: (canvasSize.height - height) / 2 + offset.height,
        width: width,
        height: height
    )
}

func canvasActualSizeScale(_ imageSize: NSSize, in canvasSize: CGSize, minScale: CGFloat, maxScale: CGFloat) -> CGFloat {
    min(max(1 / canvasFitScale(imageSize, in: canvasSize), minScale), maxScale)
}

func canvasClampedOffset(
    _ proposed: CGSize,
    imageSize: NSSize,
    canvasSize: CGSize,
    scale: CGFloat
) -> CGSize {
    let fit = canvasFitScale(imageSize, in: canvasSize) * scale
    let imageWidth = imageSize.width * fit
    let imageHeight = imageSize.height * fit
    let limitX = max(48, (imageWidth - canvasSize.width) / 2 + 96)
    let limitY = max(48, (imageHeight - canvasSize.height) / 2 + 96)
    return CGSize(
        width: min(max(proposed.width, -limitX), limitX),
        height: min(max(proposed.height, -limitY), limitY)
    )
}
