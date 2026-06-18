import Foundation
import CoreImage
import CoreGraphics
import ImageIO

public enum ImageRotation: Int, Codable, Sendable, CaseIterable {
    case deg0 = 0
    case deg90 = 1
    case deg180 = 2
    case deg270 = 3

    public var displayName: String {
        switch self {
        case .deg0: return "0"
        case .deg90: return "90"
        case .deg180: return "180"
        case .deg270: return "270"
        }
    }

    public func rotatedClockwise() -> ImageRotation {
        ImageRotation(rawValue: (rawValue + 1) % 4) ?? .deg0
    }

    public func rotatedCounterClockwise() -> ImageRotation {
        ImageRotation(rawValue: (rawValue + 3) % 4) ?? .deg0
    }
}

public struct ImageTransform: Codable, Sendable, Equatable {
    public var rotation: ImageRotation
    public var flipHorizontal: Bool
    public var flipVertical: Bool

    public init(
        rotation: ImageRotation = .deg0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false
    ) {
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
    }

    public static let identity = ImageTransform()

    public var isIdentity: Bool {
        rotation == .deg0 && !flipHorizontal && !flipVertical
    }

    public var displayName: String {
        var parts = ["R\(rotation.displayName)"]
        if flipHorizontal { parts.append("H") }
        if flipVertical { parts.append("V") }
        return parts.joined(separator: " ")
    }
}

public enum ImageTransformStage {
    public static func apply(to image: CIImage, transform: ImageTransform) -> CIImage {
        guard !transform.isIdentity else { return normalize(image) }

        var img = normalize(image)
        if transform.flipHorizontal {
            let extent = img.extent.integral
            img = applyAffine(
                img,
                CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: extent.width, ty: 0)
            )
        }
        if transform.flipVertical {
            let extent = img.extent.integral
            img = applyAffine(
                img,
                CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: extent.height)
            )
        }

        switch transform.rotation {
        case .deg0:
            break
        case .deg90:
            let extent = img.extent.integral
            img = applyAffine(
                img,
                CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: extent.width)
            )
        case .deg180:
            let extent = img.extent.integral
            img = applyAffine(
                img,
                CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: extent.width, ty: extent.height)
            )
        case .deg270:
            let extent = img.extent.integral
            img = applyAffine(
                img,
                CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: extent.height, ty: 0)
            )
        }
        return normalize(img)
    }

    private static func applyAffine(_ image: CIImage, _ transform: CGAffineTransform) -> CIImage {
        normalize(image.transformed(by: transform))
    }

    private static func normalize(_ image: CIImage) -> CIImage {
        let extent = image.extent.integral
        guard extent.origin != .zero else {
            return image.cropped(to: CGRect(origin: .zero, size: extent.size))
        }
        let translated = image.transformed(by: CGAffineTransform(
            translationX: -extent.origin.x,
            y: -extent.origin.y
        ))
        return translated.cropped(to: CGRect(origin: .zero, size: extent.size))
    }
}
