import CoreImage
import Foundation

public enum OutputSharpeningMedium: String, Codable, CaseIterable, Sendable {
    case screen
    case mattePaper
    case glossyPaper
}

public enum OutputSharpening {
    struct Parameters: Equatable {
        let radius: Double
        let intensity: Double
    }

    public static func apply(
        to image: CIImage,
        strength: Double,
        medium: OutputSharpeningMedium,
        dpi: Int
    ) -> CIImage {
        guard let parameters = parameters(strength: strength, medium: medium, dpi: dpi) else {
            return image
        }
        return image.applyingFilter("CIUnsharpMask", parameters: [
            "inputRadius": NSNumber(value: parameters.radius),
            "inputIntensity": NSNumber(value: parameters.intensity),
        ]).cropped(to: image.extent)
    }

    static func parameters(
        strength: Double,
        medium: OutputSharpeningMedium,
        dpi: Int
    ) -> Parameters? {
        guard strength > 0 else { return nil }
        let base: (radius: Double, intensity: Double, referenceDPI: Double)
        switch medium {
        case .screen:
            base = (0.45, 0.22, 144)
        case .mattePaper:
            base = (1.00, 0.34, 300)
        case .glossyPaper:
            base = (0.75, 0.28, 300)
        }
        let effectiveDPI = dpi > 0 ? Double(dpi) : base.referenceDPI
        let resolutionScale = min(max(effectiveDPI / base.referenceDPI, 0.5), 2.0)
        return Parameters(
            radius: base.radius * resolutionScale.squareRoot(),
            intensity: base.intensity * min(max(strength, 0), 1)
        )
    }
}
