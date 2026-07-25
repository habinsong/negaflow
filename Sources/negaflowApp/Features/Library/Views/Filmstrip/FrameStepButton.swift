import SwiftUI

struct FrameStepButton: View {
    let systemName: String
    let help: String
    let height: CGFloat
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: height)
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.45) : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(isDisabled ? 0.025 : 0.055))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .padding(.horizontal, 8)
        .help(help)
        .accessibilityLabel(help)
    }
}
