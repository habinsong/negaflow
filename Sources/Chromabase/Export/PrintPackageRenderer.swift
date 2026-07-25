import CoreGraphics
import CoreImage
import CoreText
import Foundation

public struct PrintPackageRenderSource {
    public let image: CIImage
    public let caption: String?

    public init(image: CIImage, caption: String? = nil) {
        self.image = image
        self.caption = caption
    }
}

public enum PrintPackageRenderer {
    public static func renderPage(
        sources: [PrintPackageRenderSource],
        layout: PrintPackagePageLayout,
        dpi: Int,
        paperColor: CIColor = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
    ) -> CIImage? {
        guard (72...600).contains(dpi),
              !sources.isEmpty,
              validSize(layout.canvasSizePoints),
              layout.items.allSatisfy({
                  sources.indices.contains($0.sourceIndex)
                      && validRect($0.cellRectPoints)
                      && validRect($0.destinationRectPoints)
                      && validUnitRect($0.sourceUnitCropRect)
                      && (0...1).contains($0.quarterTurns)
                      && ($0.captionRectPoints.map(validRect) ?? true)
              }),
              layout.cropMarkSegments.allSatisfy({
                  validPoint($0.start) && validPoint($0.end) && $0.start != $0.end
              }),
              sources.allSatisfy({ source in
                  validRect(source.image.extent)
                      && (source.caption?.utf8.count ?? 0) <= 512
              }) else { return nil }

        let pixelsPerPoint = CGFloat(dpi) / 72
        let canvasSize = CGSize(
            width: max(1, (layout.canvasSizePoints.width * pixelsPerPoint).rounded()),
            height: max(1, (layout.canvasSizePoints.height * pixelsPerPoint).rounded())
        )
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        var result = CIImage(color: paperColor).cropped(to: canvasRect)

        for item in layout.items {
            guard let placed = placedImage(
                sources[item.sourceIndex].image,
                item: item,
                pixelsPerPoint: pixelsPerPoint
            ) else { return nil }
            result = placed.composited(over: result)

            if let captionRect = item.captionRectPoints,
               let caption = sources[item.sourceIndex].caption,
               !caption.isEmpty,
               let captionImage = textImage(
                    caption,
                    rect: scaled(captionRect, by: pixelsPerPoint),
                    pixelsPerPoint: pixelsPerPoint
               ) {
                result = captionImage.composited(over: result)
            }
        }

        let lineWidth = max(1, 0.35 * pixelsPerPoint)
        for segment in layout.cropMarkSegments {
            guard let mark = lineImage(
                from: scaled(segment.start, by: pixelsPerPoint),
                to: scaled(segment.end, by: pixelsPerPoint),
                width: lineWidth
            ) else { return nil }
            result = mark.composited(over: result)
        }
        return result.cropped(to: canvasRect)
    }

    private static func placedImage(
        _ source: CIImage,
        item: PrintPackageItemLayout,
        pixelsPerPoint: CGFloat
    ) -> CIImage? {
        var image = normalize(source)
        if item.quarterTurns == 1 {
            let height = image.extent.height
            image = image.transformed(by: CGAffineTransform(
                a: 0,
                b: 1,
                c: -1,
                d: 0,
                tx: height,
                ty: 0
            ))
            image = normalize(image)
        }

        let extent = image.extent
        let unitCrop = item.sourceUnitCropRect
        let cropRect = CGRect(
            x: extent.minX + unitCrop.minX * extent.width,
            y: extent.minY + unitCrop.minY * extent.height,
            width: unitCrop.width * extent.width,
            height: unitCrop.height * extent.height
        ).intersection(extent)
        guard validRect(cropRect) else { return nil }
        image = normalize(image.cropped(to: cropRect))

        let destination = scaled(item.destinationRectPoints, by: pixelsPerPoint)
        guard validRect(destination) else { return nil }
        let scaleX = destination.width / image.extent.width
        let scaleY = destination.height / image.extent.height
        image = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        image = image.transformed(by: CGAffineTransform(
            translationX: destination.minX - image.extent.minX,
            y: destination.minY - image.extent.minY
        ))
        return image.cropped(to: scaled(item.cellRectPoints, by: pixelsPerPoint))
    }

    private static func textImage(
        _ text: String,
        rect: CGRect,
        pixelsPerPoint: CGFloat
    ) -> CIImage? {
        let width = max(1, Int(rect.width.rounded(.up)))
        let height = max(1, Int(rect.height.rounded(.up)))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let fontSize = max(6 * pixelsPerPoint, min(CGFloat(height) * 0.58, 10 * pixelsPerPoint))
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0.08, alpha: 1),
        ]
        let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
        let line = CTLineCreateWithAttributedString(attributed!)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let padding = max(1, 2 * pixelsPerPoint)
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: width, height: height))
        context.textPosition = CGPoint(
            x: padding,
            y: max(0, (CGFloat(height) - ascent - descent) / 2 + descent)
        )
        CTLineDraw(line, context)
        context.restoreGState()
        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(
            translationX: rect.minX,
            y: rect.minY
        ))
    }

    private static func lineImage(
        from start: CGPoint,
        to end: CGPoint,
        width: CGFloat
    ) -> CIImage? {
        let color = CIImage(color: CIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 0.78))
        if abs(start.y - end.y) < 1e-6 {
            let rect = CGRect(
                x: min(start.x, end.x),
                y: start.y - width / 2,
                width: abs(end.x - start.x),
                height: width
            )
            return validRect(rect) ? color.cropped(to: rect) : nil
        }
        if abs(start.x - end.x) < 1e-6 {
            let rect = CGRect(
                x: start.x - width / 2,
                y: min(start.y, end.y),
                width: width,
                height: abs(end.y - start.y)
            )
            return validRect(rect) ? color.cropped(to: rect) : nil
        }
        return nil
    }

    private static func normalize(_ image: CIImage) -> CIImage {
        guard image.extent.origin != .zero else { return image }
        return image.transformed(by: CGAffineTransform(
            translationX: -image.extent.minX,
            y: -image.extent.minY
        ))
    }

    private static func scaled(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private static func scaled(_ point: CGPoint, by scale: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }

    private static func validUnitRect(_ rect: CGRect) -> Bool {
        validRect(rect)
            && rect.minX >= 0
            && rect.minY >= 0
            && rect.maxX <= 1
            && rect.maxY <= 1
    }

    private static func validRect(_ rect: CGRect) -> Bool {
        rect.minX.isFinite
            && rect.minY.isFinite
            && rect.width.isFinite
            && rect.height.isFinite
            && rect.width > 0
            && rect.height > 0
    }

    private static func validSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func validPoint(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }
}
