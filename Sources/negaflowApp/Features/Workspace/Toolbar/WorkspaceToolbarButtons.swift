import SwiftUI
import AppKit
import Chromabase

struct PanelToggleButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var isHovered = false
    let systemName: String
    let isOn: Bool
    let help: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 24)
                .foregroundStyle(isOn ? Color.primary : Color.secondary.opacity(0.7))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityToggleState(
            isOn,
            onValue: model.accessibilityText(.on),
            offValue: model.accessibilityText(.off),
            onHint: model.accessibilityText(.turnOff),
            offHint: model.accessibilityText(.turnOn)
        )
        .onHover { isHovered = $0 }
    }
}

struct WorkspaceTextButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var isHovered = false
    let title: String
    let isSelected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14.5, weight: isSelected ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)
                .frame(minWidth: 74, maxWidth: 86, minHeight: 24)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilitySelectionState(
            isSelected,
            selectedValue: model.accessibilityText(.selected),
            unselectedValue: model.accessibilityText(.notSelected),
            unselectedHint: model.accessibilityText(.select)
        )
        .onHover { isHovered = $0 }
    }
}

struct ToolbarActionButton: View {
    @State private var isHovered = false
    let systemName: String
    var title: String? = nil
    let help: String
    var accessibilityIdentifier: String? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let title {
                HStack(spacing: 4) {
                    Image(systemName: systemName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(title)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 5)
                .frame(height: 24)
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.5) : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered && !isDisabled ? Color.primary.opacity(0.08) : Color.clear)
                )
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 24)
                    .foregroundStyle(isDisabled ? Color.secondary.opacity(0.5) : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovered && !isDisabled ? Color.primary.opacity(0.08) : Color.clear)
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
        .onHover { isHovered = $0 }
    }
}
