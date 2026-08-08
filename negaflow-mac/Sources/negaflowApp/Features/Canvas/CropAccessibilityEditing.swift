import CoreGraphics

enum CropAccessibilityEditing {
    static func move(_ rect: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        clampedUnitRect(rect.offsetBy(dx: dx, dy: dy))
    }

    static func resize(_ rect: CGRect, scaleDelta: CGFloat) -> CGRect {
        let minimumScale = max(0.035 / max(rect.width, 0.035), 0.035 / max(rect.height, 0.035))
        let maximumScale = min(1 / max(rect.width, 0.035), 1 / max(rect.height, 0.035))
        let scale = min(max(1 + scaleDelta, minimumScale), maximumScale)
        let width = rect.width * scale
        let height = rect.height * scale
        return clampedUnitRect(CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        ))
    }
}
