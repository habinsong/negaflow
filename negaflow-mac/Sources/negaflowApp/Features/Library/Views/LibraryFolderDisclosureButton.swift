import SwiftUI

/// 폴더 띠의 접기·펼치기 삼각형.
///
/// 삼각형 글리프만 눌리게 두면 조금만 벗어나도 클릭이 먹지 않는다. 눌리는 영역은 눈에 보이는
/// 네모 음영과 같아야 하고, 그 네모가 포인터를 올렸을 때와 누르는 동안 각각 다르게 보여야
/// 어디를 누르면 되는지 알 수 있다.
struct LibraryFolderDisclosureButton: View {
    let isExpanded: Bool
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    private static let side: CGFloat = 20
    private static let cornerRadius: CGFloat = 5

    var body: some View {
        Button(action: action) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.bold))
                .frame(width: Self.side, height: Self.side)
                .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(DisclosureSquareButtonStyle(
            isHovering: isHovering,
            side: Self.side,
            cornerRadius: Self.cornerRadius
        ))
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityIdentifier("negaflow.library.folder-disclosure")
        .accessibilityLabel(label)
    }
}

/// 음영은 버튼 스타일에서 그린다. `configuration.isPressed` 를 볼 수 있는 곳이 여기뿐이라,
/// 누르는 동안의 표시를 별도 상태 없이 정확한 시점에 낼 수 있다.
private struct DisclosureSquareButtonStyle: ButtonStyle {
    let isHovering: Bool
    let side: CGFloat
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(pressed || isHovering ? Color.primary : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.primary.opacity(pressed ? 0.16 : (isHovering ? 0.08 : 0)))
            )
            .frame(width: side, height: side)
    }
}
