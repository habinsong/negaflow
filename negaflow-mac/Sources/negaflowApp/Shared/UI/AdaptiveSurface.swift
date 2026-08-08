import SwiftUI
import AppKit

enum AppSurfaceMaterial {
    case regular
    case bar
    case ultraThin
}

private struct AdaptivePanelSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let material: AppSurfaceMaterial

    @ViewBuilder
    func body(content: Content) -> some View {
        if AppAccessibilityPresentation.usesOpaqueSurfaces(
            reduceTransparency: reduceTransparency
        ) {
            content.background(opaqueColor)
        } else {
            switch material {
            case .regular: content.background(.regularMaterial)
            case .bar: content.background(.bar)
            case .ultraThin: content.background(.ultraThinMaterial)
            }
        }
    }

    private var opaqueColor: Color {
        switch material {
        case .bar: Color(nsColor: .windowBackgroundColor)
        case .regular, .ultraThin: Color(nsColor: .controlBackgroundColor)
        }
    }
}

private struct AdaptiveRoundedSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let cornerRadius: CGFloat
    let material: AppSurfaceMaterial

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            decorated(content.background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            ))
        } else {
            switch material {
            case .regular:
                decorated(content.background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                ))
            case .bar:
                decorated(content.background(
                    .bar,
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                ))
            case .ultraThin:
                decorated(content.background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                ))
            }
        }
    }

    private func decorated<Surface: View>(_ surface: Surface) -> some View {
        surface.overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.primary.opacity(strokeOpacity))
        }
    }

    private var strokeOpacity: Double {
        AppAccessibilityPresentation.surfaceStrokeOpacity(
            reduceTransparency: reduceTransparency,
            increasedContrast: colorSchemeContrast == .increased
        )
    }
}

private struct AdaptiveCapsuleSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let material: AppSurfaceMaterial

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            decorated(content.background(Color(nsColor: .controlBackgroundColor), in: Capsule()))
        } else {
            switch material {
            case .regular: decorated(content.background(.regularMaterial, in: Capsule()))
            case .bar: decorated(content.background(.bar, in: Capsule()))
            case .ultraThin: decorated(content.background(.ultraThinMaterial, in: Capsule()))
            }
        }
    }

    private func decorated<Surface: View>(_ surface: Surface) -> some View {
        surface.overlay {
            Capsule().strokeBorder(Color.primary.opacity(strokeOpacity))
        }
    }

    private var strokeOpacity: Double {
        AppAccessibilityPresentation.surfaceStrokeOpacity(
            reduceTransparency: reduceTransparency,
            increasedContrast: colorSchemeContrast == .increased
        )
    }
}

extension View {
    func adaptivePanelSurface(_ material: AppSurfaceMaterial) -> some View {
        modifier(AdaptivePanelSurfaceModifier(material: material))
    }

    func adaptiveRoundedSurface(
        cornerRadius: CGFloat,
        material: AppSurfaceMaterial
    ) -> some View {
        modifier(AdaptiveRoundedSurfaceModifier(
            cornerRadius: cornerRadius,
            material: material
        ))
    }

    func adaptiveCapsuleSurface(_ material: AppSurfaceMaterial) -> some View {
        modifier(AdaptiveCapsuleSurfaceModifier(material: material))
    }
}
