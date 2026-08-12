import SwiftUI

/// 캔버스 위에 떠 있는 컨트롤(비교 토글·줌 캡슐)의 표면.
///
/// 글래스(`liquidSurface`)는 뒤에 깔린 캔버스 색을 그대로 통과시켜, 배경을 흰색으로 두면
/// 캡슐도 글자도 흰색이 돼 컨트롤이 보이지 않았다. 여기서는 배경 설정에서 직접 유도한
/// 불투명 면 + 반대색 테두리를 쓴다 — 라이트/다크/자동 어느 외형에서도 결과가 같다.
struct CanvasControlSurface: ViewModifier {
    let background: CanvasBackground
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(background.hudContentColor)
            .background(
                background.hudSurfaceColor,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(background.hudContentColor.opacity(0.22))
            }
    }
}

extension View {
    func canvasControlSurface(_ background: CanvasBackground, cornerRadius: CGFloat) -> some View {
        modifier(CanvasControlSurface(background: background, cornerRadius: cornerRadius))
    }
}
