import CoreGraphics
import CoreImage
import Foundation

public struct PixelCoordinate: Sendable, Equatable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct PixelColorReading: Sendable, Equatable {
    public let rgb: SIMD3<Double>
    public let lab: SIMD3<Double>
    public let colorSpaceName: String

    public init(rgb: SIMD3<Double>, lab: SIMD3<Double>, colorSpaceName: String) {
        self.rgb = rgb
        self.lab = lab
        self.colorSpaceName = colorSpaceName
    }
}

public enum PixelSampler {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    public static func sourceCoordinate(
        at unitPoint: CGPoint,
        width: Int,
        height: Int
    ) -> PixelCoordinate? {
        guard width > 0, height > 0 else { return nil }
        return PixelCoordinate(
            x: min(max(Int(floor(unitPoint.x * Double(width))), 0), width - 1),
            y: min(max(Int(floor(unitPoint.y * Double(height))), 0), height - 1)
        )
    }

    public static func sample(
        _ image: CGImage,
        at unitPoint: CGPoint,
        rgbColorSpace: CGColorSpace? = nil
    ) -> PixelColorReading? {
        guard let coordinate = sourceCoordinate(
            at: unitPoint,
            width: image.width,
            height: image.height
        ) else { return nil }
        let target = rgbColorSpace ?? image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let ciImage = CIImage(cgImage: image)
        let yUp = image.height - 1 - coordinate.y
        var pixel = [Float](repeating: 0, count: 4)
        context.render(
            ciImage,
            toBitmap: &pixel,
            rowBytes: MemoryLayout<Float>.size * 4,
            bounds: CGRect(x: coordinate.x, y: yUp, width: 1, height: 1),
            format: .RGBAf,
            colorSpace: target
        )
        let rgb = SIMD3<Double>(Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
        guard let lab = lab(rgb: rgb, colorSpace: target) else { return nil }
        return PixelColorReading(
            rgb: rgb,
            lab: lab,
            colorSpaceName: target.name.map { $0 as String } ?? "RGB"
        )
    }

    private static func lab(rgb: SIMD3<Double>, colorSpace: CGColorSpace) -> SIMD3<Double>? {
        let components = [clamp(rgb.x), clamp(rgb.y), clamp(rgb.z), 1]
        guard let color = CGColor(colorSpace: colorSpace, components: components),
              let labSpace = CGColorSpace(name: CGColorSpace.genericLab),
              let converted = color.converted(to: labSpace, intent: .relativeColorimetric, options: nil),
              let values = converted.components,
              values.count >= 3 else { return nil }
        return SIMD3<Double>(values[0], values[1], values[2])
    }

    private static func clamp(_ value: Double) -> CGFloat {
        CGFloat(min(max(value, 0), 1))
    }
}
