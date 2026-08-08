import CoreGraphics
import CoreImage

enum LocalDodgeBurnStage {
    static func apply(to image: CIImage, adjustments: [LocalDodgeBurnAdjustment]) -> CIImage {
        guard !adjustments.isEmpty else { return image }
        let extent = image.extent.integral
        guard extent.width >= 1, extent.height >= 1 else { return image }

        var output = image
        for adjustment in adjustments where adjustment.isEnabled {
            let amount = clamp(adjustment.amount, 0, 1)
            guard amount > 1e-4, let mask = makeMask(adjustment.mask, extent: extent) else { continue }
            let stops = (adjustment.mode == .dodge ? 1.0 : -1.0) * amount
            let adjusted = output.applyingFilter("CIExposureAdjust", parameters: ["inputEV": stops])
            output = CIFilter(name: "CIBlendWithMask", parameters: [
                "inputImage": adjusted,
                "inputBackgroundImage": output,
                "inputMaskImage": mask,
            ])?.outputImage?.cropped(to: extent) ?? output
        }
        return output.cropped(to: extent)
    }

    private static func makeMask(_ mask: LocalDodgeBurnMask, extent: CGRect) -> CIImage? {
        let width = Int(extent.width.rounded(.toNearestOrAwayFromZero))
        let height = Int(extent.height.rounded(.toNearestOrAwayFromZero))
        guard width > 0, height > 0 else { return nil }
        return switch mask.kind {
        case .brush: brushMask(mask.strokes, extent: extent, width: width, height: height)
        case .radial: radialMask(mask, extent: extent, width: width, height: height)
        case .linear: linearMask(mask, extent: extent, width: width, height: height)
        case .polygon: polygonMask(mask, extent: extent, width: width, height: height)
        }
    }

    private static func brushMask(
        _ strokes: [LocalDodgeBurnStroke],
        extent: CGRect,
        width: Int,
        height: Int
    ) -> CIImage? {
        guard !strokes.isEmpty, let context = maskContext(width: width, height: height) else { return nil }
        context.setStrokeColor(gray: 1, alpha: 1)
        context.setFillColor(gray: 1, alpha: 1)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let minDimension = CGFloat(min(width, height))
        var maxFeather: CGFloat = 0

        for stroke in strokes where !stroke.points.isEmpty {
            let lineWidth = max(1, CGFloat(clamp(stroke.thickness, 0.001, 0.25)) * minDimension)
            maxFeather = max(maxFeather, CGFloat(clamp(stroke.feather, 0, 0.25)) * minDimension)
            if stroke.points.count == 1 {
                let center = pixelPoint(stroke.points[0], width: width, height: height)
                let radius = lineWidth / 2
                context.fillEllipse(in: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                ))
                continue
            }
            let path = CGMutablePath()
            path.move(to: pixelPoint(stroke.points[0], width: width, height: height))
            stroke.points.dropFirst().forEach { path.addLine(to: pixelPoint($0, width: width, height: height)) }
            context.setLineWidth(lineWidth)
            context.addPath(path)
            context.strokePath()
        }

        guard let hardMask = ciImage(from: context, extent: extent) else { return nil }
        return softened(hardMask, radius: maxFeather, extent: extent)
    }

    private static func radialMask(
        _ mask: LocalDodgeBurnMask,
        extent: CGRect,
        width: Int,
        height: Int
    ) -> CIImage? {
        guard let context = maskContext(width: width, height: height) else { return nil }
        let gray = CGColorSpaceCreateDeviceGray()
        let radius = max(1, CGFloat(clamp(mask.radius, 0.001, 2.0)) * CGFloat(min(width, height)))
        let feather = CGFloat(clamp(mask.feather, 0, 1))
        let inner = max(0, min(radius, radius * (1 - feather)))
        let colors = [
            CGColor(gray: 1, alpha: 1),
            CGColor(gray: 1, alpha: 1),
            CGColor(gray: 0, alpha: 1),
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: gray, colors: colors, locations: [0, inner / radius, 1]) else {
            return nil
        }
        let center = pixelPoint(mask.center, width: width, height: height)
        context.drawRadialGradient(
            gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: []
        )
        return ciImage(from: context, extent: extent)
    }

    private static func linearMask(
        _ mask: LocalDodgeBurnMask,
        extent: CGRect,
        width: Int,
        height: Int
    ) -> CIImage? {
        guard let context = maskContext(width: width, height: height) else { return nil }
        let start = pixelPoint(mask.start, width: width, height: height)
        let end = pixelPoint(mask.end, width: width, height: height)
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx * dx + dy * dy > 1 else { return nil }
        let feather = CGFloat(clamp(mask.feather, 0, 1))
        let colors = [
            CGColor(gray: 1, alpha: 1),
            CGColor(gray: 1, alpha: 1),
            CGColor(gray: 0, alpha: 1),
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1 - feather, 1]
        ) else { return nil }
        context.drawLinearGradient(
            gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        return ciImage(from: context, extent: extent)
    }

    private static func polygonMask(
        _ mask: LocalDodgeBurnMask,
        extent: CGRect,
        width: Int,
        height: Int
    ) -> CIImage? {
        guard mask.points.count >= 3, let context = maskContext(width: width, height: height) else { return nil }
        let path = CGMutablePath()
        path.move(to: pixelPoint(mask.points[0], width: width, height: height))
        mask.points.dropFirst().forEach { path.addLine(to: pixelPoint($0, width: width, height: height)) }
        path.closeSubpath()
        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(path)
        context.fillPath()
        guard let hardMask = ciImage(from: context, extent: extent) else { return nil }
        let radius = CGFloat(clamp(mask.feather, 0, 0.25)) * CGFloat(min(width, height))
        return softened(hardMask, radius: radius, extent: extent)
    }

    private static func maskContext(width: Int, height: Int) -> CGContext? {
        let gray = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    private static func ciImage(from context: CGContext, extent: CGRect) -> CIImage? {
        context.makeImage().map {
            CIImage(cgImage: $0)
                .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
                .cropped(to: extent)
        }
    }

    private static func softened(_ image: CIImage, radius: CGFloat, extent: CGRect) -> CIImage {
        guard radius > 0.25 else { return image.cropped(to: extent) }
        return image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius])
            .cropped(to: extent)
    }

    private static func pixelPoint(_ point: LocalDodgeBurnPoint, width: Int, height: Int) -> CGPoint {
        CGPoint(x: clamp(point.x, 0, 1) * Double(width), y: (1 - clamp(point.y, 0, 1)) * Double(height))
    }

    private static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }
}
