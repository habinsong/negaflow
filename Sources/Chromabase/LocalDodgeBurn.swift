import Foundation
import CoreGraphics
import CoreImage

public struct LocalDodgeBurnPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct LocalDodgeBurnStroke: Codable, Sendable, Equatable {
    public var points: [LocalDodgeBurnPoint]
    public var thickness: Double
    public var feather: Double

    public init(points: [LocalDodgeBurnPoint], thickness: Double = 0.04, feather: Double = 0.02) {
        self.points = points
        self.thickness = thickness
        self.feather = feather
    }

    enum CodingKeys: String, CodingKey { case points, thickness, feather }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decodeIfPresent([LocalDodgeBurnPoint].self, forKey: .points) ?? []
        thickness = try c.decodeIfPresent(Double.self, forKey: .thickness) ?? 0.04
        feather = try c.decodeIfPresent(Double.self, forKey: .feather) ?? 0.02
    }
}

public enum LocalDodgeBurnMode: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case dodge
    case burn
}

public struct LocalDodgeBurnMask: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case brush
        case radial
        case linear
        case polygon
    }

    public var kind: Kind
    public var strokes: [LocalDodgeBurnStroke]
    public var center: LocalDodgeBurnPoint
    public var radius: Double
    public var feather: Double
    public var start: LocalDodgeBurnPoint
    public var end: LocalDodgeBurnPoint
    public var points: [LocalDodgeBurnPoint]

    public static func brush(strokes: [LocalDodgeBurnStroke]) -> LocalDodgeBurnMask {
        LocalDodgeBurnMask(kind: .brush, strokes: strokes)
    }

    public static func radial(center: LocalDodgeBurnPoint, radius: Double, feather: Double) -> LocalDodgeBurnMask {
        LocalDodgeBurnMask(kind: .radial, center: center, radius: radius, feather: feather)
    }

    public static func linear(
        start: LocalDodgeBurnPoint,
        end: LocalDodgeBurnPoint,
        feather: Double
    ) -> LocalDodgeBurnMask {
        LocalDodgeBurnMask(kind: .linear, feather: feather, start: start, end: end)
    }

    public static func polygon(points: [LocalDodgeBurnPoint], feather: Double) -> LocalDodgeBurnMask {
        LocalDodgeBurnMask(kind: .polygon, feather: feather, points: points)
    }

    public init(
        kind: Kind,
        strokes: [LocalDodgeBurnStroke] = [],
        center: LocalDodgeBurnPoint = LocalDodgeBurnPoint(x: 0.5, y: 0.5),
        radius: Double = 0.25,
        feather: Double = 0.25,
        start: LocalDodgeBurnPoint = LocalDodgeBurnPoint(x: 0.5, y: 0.0),
        end: LocalDodgeBurnPoint = LocalDodgeBurnPoint(x: 0.5, y: 1.0),
        points: [LocalDodgeBurnPoint] = []
    ) {
        self.kind = kind
        self.strokes = strokes
        self.center = center
        self.radius = radius
        self.feather = feather
        self.start = start
        self.end = end
        self.points = points
    }

    enum CodingKeys: String, CodingKey {
        case kind, strokes, center, radius, feather, start, end, points
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        strokes = try c.decodeIfPresent([LocalDodgeBurnStroke].self, forKey: .strokes) ?? []
        center = try c.decodeIfPresent(LocalDodgeBurnPoint.self, forKey: .center) ?? LocalDodgeBurnPoint(x: 0.5, y: 0.5)
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0.25
        feather = try c.decodeIfPresent(Double.self, forKey: .feather) ?? 0.25
        start = try c.decodeIfPresent(LocalDodgeBurnPoint.self, forKey: .start) ?? LocalDodgeBurnPoint(x: 0.5, y: 0.0)
        end = try c.decodeIfPresent(LocalDodgeBurnPoint.self, forKey: .end) ?? LocalDodgeBurnPoint(x: 0.5, y: 1.0)
        points = try c.decodeIfPresent([LocalDodgeBurnPoint].self, forKey: .points) ?? []
    }
}

public struct LocalDodgeBurnAdjustment: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var mode: LocalDodgeBurnMode
    public var amount: Double
    public var mask: LocalDodgeBurnMask

    public init(
        id: UUID = UUID(),
        mode: LocalDodgeBurnMode,
        amount: Double,
        mask: LocalDodgeBurnMask
    ) {
        self.id = id
        self.mode = mode
        self.amount = amount
        self.mask = mask
    }

    enum CodingKeys: String, CodingKey { case id, mode, amount, mask }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mode = try c.decodeIfPresent(LocalDodgeBurnMode.self, forKey: .mode) ?? .dodge
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        mask = try c.decode(LocalDodgeBurnMask.self, forKey: .mask)
    }
}

enum LocalDodgeBurnStage {
    static func apply(to image: CIImage, adjustments: [LocalDodgeBurnAdjustment]) -> CIImage {
        guard !adjustments.isEmpty else { return image }
        let extent = image.extent.integral
        guard extent.width >= 1, extent.height >= 1 else { return image }

        var output = image
        for adjustment in adjustments {
            let amount = clamp(adjustment.amount, 0, 1)
            guard amount > 1e-4,
                  let mask = makeMask(adjustment.mask, extent: extent) else {
                continue
            }
            let stops = (adjustment.mode == .dodge ? 1.0 : -1.0) * amount * 1.35
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

        switch mask.kind {
        case .brush:
            return brushMask(mask.strokes, extent: extent, width: width, height: height)
        case .radial:
            return radialMask(mask, extent: extent, width: width, height: height)
        case .linear:
            return linearMask(mask, extent: extent, width: width, height: height)
        case .polygon:
            return polygonMask(mask, extent: extent, width: width, height: height)
        }
    }

    private static func brushMask(
        _ strokes: [LocalDodgeBurnStroke],
        extent: CGRect,
        width: Int,
        height: Int
    ) -> CIImage? {
        guard !strokes.isEmpty, let ctx = maskContext(width: width, height: height) else { return nil }
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let minDim = CGFloat(min(width, height))
        var maxFeather: CGFloat = 0

        for stroke in strokes where !stroke.points.isEmpty {
            let lineWidth = max(1, CGFloat(clamp(stroke.thickness, 0.001, 0.25)) * minDim)
            maxFeather = max(maxFeather, CGFloat(clamp(stroke.feather, 0, 0.25)) * minDim)
            if stroke.points.count == 1 {
                let center = pixelPoint(stroke.points[0], width: width, height: height)
                let radius = lineWidth / 2
                ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                continue
            }
            let path = CGMutablePath()
            path.move(to: pixelPoint(stroke.points[0], width: width, height: height))
            for point in stroke.points.dropFirst() {
                path.addLine(to: pixelPoint(point, width: width, height: height))
            }
            ctx.setLineWidth(lineWidth)
            ctx.addPath(path)
            ctx.strokePath()
        }

        guard let hard = ciImage(from: ctx, extent: extent) else { return nil }
        return softened(hard, radius: maxFeather, extent: extent)
    }

    private static func radialMask(
        _ mask: LocalDodgeBurnMask,
        extent: CGRect,
        width: Int,
        height: Int
    ) -> CIImage? {
        guard let ctx = maskContext(width: width, height: height) else { return nil }
        let gray = CGColorSpaceCreateDeviceGray()
        let radius = max(1, CGFloat(clamp(mask.radius, 0.001, 2.0)) * CGFloat(min(width, height)))
        let feather = CGFloat(clamp(mask.feather, 0, 1))
        let inner = max(0, min(radius, radius * (1 - feather)))
        let center = pixelPoint(mask.center, width: width, height: height)
        let locations: [CGFloat] = [0, inner / radius, 1]
        let colors = [
            CGColor(gray: 1, alpha: 1),
            CGColor(gray: 1, alpha: 1),
            CGColor(gray: 0, alpha: 1),
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: gray, colors: colors, locations: locations) else { return nil }
        ctx.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: []
        )
        return ciImage(from: ctx, extent: extent)
    }

    private static func linearMask(
        _ mask: LocalDodgeBurnMask,
        extent: CGRect,
        width: Int,
        height: Int
    ) -> CIImage? {
        guard let ctx = maskContext(width: width, height: height) else { return nil }
        let start = pixelPoint(mask.start, width: width, height: height)
        let end = pixelPoint(mask.end, width: width, height: height)
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx * dx + dy * dy > 1 else { return nil }
        let gray = CGColorSpaceCreateDeviceGray()
        let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] as CFArray
        guard let gradient = CGGradient(colorsSpace: gray, colors: colors, locations: [0, 1]) else { return nil }
        ctx.drawLinearGradient(
            gradient,
            start: start,
            end: end,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        return ciImage(from: ctx, extent: extent)
    }

    private static func polygonMask(
        _ mask: LocalDodgeBurnMask,
        extent: CGRect,
        width: Int,
        height: Int
    ) -> CIImage? {
        guard mask.points.count >= 3, let ctx = maskContext(width: width, height: height) else { return nil }
        let path = CGMutablePath()
        path.move(to: pixelPoint(mask.points[0], width: width, height: height))
        for point in mask.points.dropFirst() {
            path.addLine(to: pixelPoint(point, width: width, height: height))
        }
        path.closeSubpath()
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.addPath(path)
        ctx.fillPath()

        guard let hard = ciImage(from: ctx, extent: extent) else { return nil }
        let radius = CGFloat(clamp(mask.feather, 0, 0.25)) * CGFloat(min(width, height))
        return softened(hard, radius: radius, extent: extent)
    }

    private static func maskContext(width: Int, height: Int) -> CGContext? {
        let gray = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: gray,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }

    private static func ciImage(from ctx: CGContext, extent: CGRect) -> CIImage? {
        ctx.makeImage().map {
            CIImage(cgImage: $0)
                .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
                .cropped(to: extent)
        }
    }

    private static func softened(_ image: CIImage, radius: CGFloat, extent: CGRect) -> CIImage {
        guard radius > 0.25 else { return image.cropped(to: extent) }
        return image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius])
            .cropped(to: extent)
    }

    private static func pixelPoint(_ point: LocalDodgeBurnPoint, width: Int, height: Int) -> CGPoint {
        CGPoint(
            x: clamp(point.x, 0, 1) * Double(width),
            y: (1 - clamp(point.y, 0, 1)) * Double(height)
        )
    }

    private static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }
}
