import SwiftUI
import Chromabase

extension LocalDodgeBurnMask.Kind {
    var systemImage: String {
        switch self {
        case .brush: "paintbrush"
        case .radial: "circle.dashed"
        case .linear: "rectangle.split.3x1"
        case .polygon: "pentagon"
        }
    }

    func localizedName(language: AppLanguage) -> String {
        let text: LocalAdjustmentLocalizedText = switch self {
        case .brush: .brush
        case .radial: .radial
        case .linear: .linear
        case .polygon: .polygon
        }
        return text.resolved(language: language)
    }
}

extension LocalDodgeBurnAdjustment {
    var normalizedFeather: Double {
        switch mask.kind {
        case .brush:
            return min(max((mask.strokes.first?.feather ?? 0) / 0.25, 0), 1)
        case .radial, .linear, .polygon:
            return min(max(mask.feather, 0), 1)
        }
    }

    mutating func setNormalizedFeather(_ value: Double) {
        let value = min(max(value, 0), 1)
        switch mask.kind {
        case .brush:
            for index in mask.strokes.indices {
                mask.strokes[index].feather = value * 0.25
            }
        case .radial, .linear, .polygon:
            mask.feather = value
        }
    }
}
