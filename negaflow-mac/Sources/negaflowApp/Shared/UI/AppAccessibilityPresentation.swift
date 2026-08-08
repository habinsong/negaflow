import Foundation

enum AppAccessibilityPresentation {
    static func disablesAnimations(reduceMotion: Bool) -> Bool {
        reduceMotion
    }

    static func usesOpaqueSurfaces(reduceTransparency: Bool) -> Bool {
        reduceTransparency
    }

    static func surfaceStrokeOpacity(
        reduceTransparency: Bool,
        increasedContrast: Bool
    ) -> Double {
        if increasedContrast { return 0.5 }
        if reduceTransparency { return 0.2 }
        return 0
    }
}
