import AppKit
import SwiftUI

/// 유리(liquid/material) 대신 쓰는 평범한 카드 표면.
///
/// 캔버스 위에 떠 있는 정보는 배경이 비치면 사진에 따라 읽히는 정도가 달라진다. 카드는 불투명한
/// 컨트롤 배경과 가는 테두리만 쓰고 그림자는 두지 않는다.
extension View {
    func cardSurface(cornerRadius: CGFloat) -> some View {
        modifier(CardSurfaceModifier(cornerRadius: cornerRadius))
    }
}

private struct CardSurfaceModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.primary.opacity(strokeOpacity))
            }
    }

    private var strokeOpacity: Double {
        colorSchemeContrast == .increased ? 0.5 : 0.12
    }
}
