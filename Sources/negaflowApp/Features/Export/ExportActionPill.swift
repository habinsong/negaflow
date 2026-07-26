import SwiftUI

// 내보내기 액션 캡슐 — 좌측은 실행 버튼, 우측은 대상 폴더를 Finder 로 여는 보조 버튼이다.
// 자동 톤/자동 화이트 밸런스(QuickActionPill)와 같은 구조다: 한 캡슐 안에 독립된 두 버튼이
// 들어가고 각자 hover 음영을 가진다. 폴더 버튼은 아직 내보낸 적이 없어도 늘 쓸 수 있다 —
// 대상 폴더를 미리 확인하는 용도이기 때문이다.
struct ExportActionPill: View {
    let title: String
    let systemImage: String
    let revealHelp: String
    /// 주 동작(내보내기)이면 강조색을 쓴다.
    var isProminent = false
    var isActionEnabled = true
    let action: () -> Void
    let reveal: () -> Void

    @State private var actionHovered = false
    @State private var revealHovered = false

    var body: some View {
        HStack(spacing: 2) {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .padding(.leading, 8)
                    .foregroundStyle(actionForeground)
                    .background(actionBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { actionHovered = $0 }
            .disabled(!isActionEnabled)
            .help(title)
            .accessibilityLabel(title)

            Button(action: reveal) {
                Image(systemName: "folder")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(revealHovered ? 0.12 : 0), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { revealHovered = $0 }
            .help(revealHelp)
            .accessibilityLabel(revealHelp)
            .padding(.trailing, 3)
        }
        .frame(maxWidth: .infinity)
        .liquidSurface(cornerRadius: 15, interactive: true)
    }

    private var actionForeground: Color {
        guard isActionEnabled else { return .secondary }
        return isProminent ? .accentColor : .primary
    }

    private var actionBackground: Color {
        guard isActionEnabled else { return .clear }
        if isProminent {
            return Color.accentColor.opacity(actionHovered ? 0.28 : 0.2)
        }
        return Color.primary.opacity(actionHovered ? 0.12 : 0)
    }
}
