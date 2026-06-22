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
    /// 정규화 crop 사각형 (x, y, w, h ∈ [0,1], post-transform 기준).
    /// nil이면 crop 없음(원본 전체). 색감 엔진과 무관하게 픽셀 단위 crop만.
    public var cropRect: SIMD4<Double>?

    public init(
        rotation: ImageRotation = .deg0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        cropRect: SIMD4<Double>? = nil
    ) {
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.cropRect = cropRect
    }

    public static let identity = ImageTransform()

    public var orientationTemplate: ImageTransform {
        ImageTransform(
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical
        )
    }

    public var isIdentity: Bool {
        rotation == .deg0 && !flipHorizontal && !flipVertical && cropRect == nil
    }

    public var displayName: String {
        var parts = ["R\(rotation.displayName)"]
        if flipHorizontal { parts.append("H") }
        if flipVertical { parts.append("V") }
        if let c = cropRect {
            parts.append(String(format: "crop%.0f×%.0f", c.z * 100, c.w * 100))
        }
        return parts.joined(separator: " ")
    }
}

public enum ImageTransformStage {
    public static func apply(to image: CIImage, transform: ImageTransform) -> CIImage {
        // 회전/플립(crop 없이도 동작).
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
        img = normalize(img)

        // crop — 회전/플립 정규화 후 적용. 정규화(0~1) 사각형을 절대 좌표로 변환.
        if let crop = transform.cropRect {
            let extent = img.extent
            let rect = CGRect(
                x: extent.minX + crop.x * extent.width,
                y: extent.minY + crop.y * extent.height,
                width: crop.z * extent.width,
                height: crop.w * extent.height
            )
            img = img.cropped(to: rect)
            img = normalize(img)
        }
        return img
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
