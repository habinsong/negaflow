import SwiftUI

struct CanvasViewportState: Equatable {
    var scale: CGFloat = 1
    var lastScale: CGFloat = 1
    var offset: CGSize = .zero
    var lastOffset: CGSize = .zero

    let minScale: CGFloat = 0.2
    let maxScale: CGFloat = 12

    var zoomText: String {
        "\(Int((scale * 100).rounded()))%"
    }

    mutating func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    mutating func setScale(_ newScale: CGFloat, imageSize: NSSize, canvasSize: CGSize) {
        let clamped = clampedScale(newScale)
        scale = clamped
        lastScale = clamped
        offset = canvasClampedOffset(offset, imageSize: imageSize, canvasSize: canvasSize, scale: clamped)
        lastOffset = offset
    }

    func actualSizeScale(for imageSize: NSSize, in canvasSize: CGSize) -> CGFloat {
        canvasActualSizeScale(imageSize, in: canvasSize, minScale: minScale, maxScale: maxScale)
    }

    mutating func updatePan(translation: CGSize, imageSize: NSSize, canvasSize: CGSize) {
        let proposed = CGSize(
            width: lastOffset.width + translation.width,
            height: lastOffset.height + translation.height
        )
        offset = canvasClampedOffset(proposed, imageSize: imageSize, canvasSize: canvasSize, scale: scale)
    }

    mutating func endPan() {
        lastOffset = offset
    }

    mutating func updateMagnification(_ value: CGFloat, imageSize: NSSize, canvasSize: CGSize) {
        let next = clampedScale(lastScale * value)
        scale = next
        offset = canvasClampedOffset(offset, imageSize: imageSize, canvasSize: canvasSize, scale: next)
    }

    mutating func endMagnification() {
        lastScale = scale
        lastOffset = offset
    }

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }
}
