import SwiftUI

/// 주 동작 + 오른쪽 작은 보조 단추를 한 알약에 담는다. 현상 탭의 자동 톤/자동 화이트 밸런스와
/// 진단 패널의 카탈로그 복구/재설치가 같은 모양을 쓴다.
struct QuickActionPill: View {
    let title: String
    let systemImage: String
    let help: String
    var trailingSystemImage = "arrow.counterclockwise"
    let trailingHelp: String
    /// 주 동작만 막는다. 보조 단추(예: Finder에서 보기)는 계속 누를 수 있어야 한다.
    var isActionEnabled = true
    let action: () -> Void
    let trailingAction: () -> Void
    @State private var actionHovered = false
    @State private var trailingHovered = false

    var body: some View {
        HStack(spacing: 2) {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .padding(.leading, 8)
                    .background(
                        Color.primary.opacity(actionHovered ? 0.12 : 0),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { actionHovered = $0 }
            .disabled(!isActionEnabled)

            Button(action: trailingAction) {
                Image(systemName: trailingSystemImage)
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(trailingHovered ? 0.12 : 0), in: Circle())
            }
            .buttonStyle(.plain)
            .onHover { trailingHovered = $0 }
            .help(trailingHelp)
            .accessibilityLabel(trailingHelp)
            .padding(.trailing, 3)
        }
        .frame(maxWidth: .infinity)
        .liquidSurface(cornerRadius: 15, interactive: true)
        .help(help)
    }
}
