import SwiftUI
import Chromabase

struct ToolLabelButton: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let systemName: String
    let help: String
    var isActive: Bool? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive == true ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)
                .frame(maxWidth: .infinity, minHeight: 34)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isActive == true ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityActiveState(
            isActive,
            activeValue: model.accessibilityText(.active),
            inactiveValue: model.accessibilityText(.inactive),
            activateHint: model.accessibilityText(.activate),
            deactivateHint: model.accessibilityText(.deactivate)
        )
    }
}

struct ToolIconButton: View {
    @EnvironmentObject private var model: AppModel
    let systemName: String
    let help: String
    var isActive: Bool? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive == true ? Color.accentColor : Color.primary)
            .frame(width: 36, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive == true ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityActiveState(
            isActive,
            activeValue: model.accessibilityText(.active),
            inactiveValue: model.accessibilityText(.inactive),
            activateHint: model.accessibilityText(.activate),
            deactivateHint: model.accessibilityText(.deactivate)
        )
    }
}
