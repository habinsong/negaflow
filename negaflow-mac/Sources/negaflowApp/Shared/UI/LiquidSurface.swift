import SwiftUI
import AppKit

extension View {
    func liquidSurface(cornerRadius: CGFloat, interactive: Bool = false, glassEnabled: Bool = true) -> some View {
        modifier(LiquidSurfaceModifier(
            cornerRadius: cornerRadius,
            interactive: interactive,
            glassEnabled: glassEnabled
        ))
    }
}

private struct LiquidSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let cornerRadius: CGFloat
    let interactive: Bool
    let glassEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            decorated(content.background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            ))
        } else {
            glass(content)
        }
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        if #available(macOS 26.0, *), glassEnabled {
            if interactive {
                decorated(content
                    .glassEffect(.clear.interactive(), in: .rect(cornerRadius: cornerRadius))
                    .shadow(color: .clear, radius: 0))
            } else {
                decorated(content
                    .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
                    .shadow(color: .clear, radius: 0))
            }
        } else {
            decorated(content.background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            ))
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
