import Foundation
import CoreImage
import CoreGraphics

public enum BWToningMode: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case none
    case selenium
    case sepia

    public var displayName: String {
        switch self {
        case .none: return "Off"
        case .selenium: return "Selenium"
        case .sepia: return "Sepia"
        }
    }

    public var defaultShadowHue: Double {
        switch self {
        case .none: return 285
        case .selenium: return 285
        case .sepia: return 32
        }
    }

    public var defaultHighlightHue: Double {
        switch self {
        case .none: return 34
        case .selenium: return 34
        case .sepia: return 48
        }
    }
}

public struct BWToning: Codable, Sendable, Equatable {
    public var mode: BWToningMode
    public var shadowHue: Double
    public var highlightHue: Double
    public var strength: Double

    public static let none = BWToning()

    public init(
        mode: BWToningMode = .none,
        shadowHue: Double? = nil,
        highlightHue: Double? = nil,
        strength: Double = 0
    ) {
        self.mode = mode
        self.shadowHue = shadowHue ?? mode.defaultShadowHue
        self.highlightHue = highlightHue ?? mode.defaultHighlightHue
        self.strength = strength
    }

    enum CodingKeys: String, CodingKey {
        case mode, shadowHue, highlightHue, strength
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(BWToningMode.self, forKey: .mode) ?? .none
        shadowHue = try c.decodeIfPresent(Double.self, forKey: .shadowHue) ?? mode.defaultShadowHue
        highlightHue = try c.decodeIfPresent(Double.self, forKey: .highlightHue) ?? mode.defaultHighlightHue
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? 0
    }

    public var isIdentity: Bool {
        mode == .none || clampedStrength <= 1e-4
    }

    public var clampedStrength: Double {
        min(max(strength, 0), 1)
    }
}

public enum BWToningStage {
    public static func apply(to image: CIImage, toning: BWToning, filmType: FilmType) -> CIImage {
        guard filmType == .bwNegative || filmType == .bwPositive,
              !toning.isIdentity,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "bwToning") else {
            return image
        }

        let modeBias: Double
        switch toning.mode {
        case .none:
            return image
        case .selenium:
            modeBias = 0
        case .sepia:
            modeBias = 1
        }

        return kernel.apply(extent: image.extent, arguments: [
            image,
            tintVector(hue: toning.shadowHue),
            tintVector(hue: toning.highlightHue),
            CIVector(x: CGFloat(toning.clampedStrength), y: CGFloat(modeBias)),
        ])?.cropped(to: image.extent) ?? image
    }

    private static func tintVector(hue: Double) -> CIVector {
        let rgb = hsv2rgb(hue: hue / 360.0, s: 0.78, v: 1.0)
        return CIVector(x: CGFloat(rgb.0), y: CGFloat(rgb.1), z: CGFloat(rgb.2))
    }
}
