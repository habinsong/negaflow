import SwiftUI

struct DevelopQuickActionsSection: View {
    @EnvironmentObject private var model: AppModel
    let canAutoAdjust: Bool
    let showsAutoCorrections: Bool
    let autoLevels: Binding<Bool>
    let autoNeutralBalance: Binding<Bool>
    var showsResetAll = true
    let onResetAll: () -> Void
    let onAutoTone: () -> Void
    let onAutoWhiteBalance: () -> Void
    let onResetAutoTone: () -> Void
    let onResetAutoWhiteBalance: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if showsResetAll {
                Button(role: .destructive, action: onResetAll) {
                    Label(model.text(.commandResetAdjustments), systemImage: "arrow.counterclockwise.circle")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .help(model.text(AppLocalizedPhrase.resetAdjustmentsHelp))
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                spacing: 8
            ) {
                if showsAutoCorrections {
                    QuickTogglePill(
                        title: model.text(AppLocalizedPhrase.autoColor),
                        systemImage: "camera.filters",
                        isOn: autoNeutralBalance
                    )

                    QuickTogglePill(
                        title: model.text(AppLocalizedPhrase.autoLevels),
                        systemImage: "chart.bar.xaxis",
                        isOn: autoLevels
                    )
                }

                QuickActionPill(
                    title: model.text(.commandAutoTone),
                    systemImage: "circle.lefthalf.filled",
                    help: model.text(AppLocalizedPhrase.autoToneHelp),
                    trailingHelp: model.text(AppLocalizedPhrase.reset),
                    action: onAutoTone,
                    trailingAction: onResetAutoTone
                )
                .disabled(!canAutoAdjust)

                QuickActionPill(
                    title: model.text(.commandAutoWhiteBalance),
                    systemImage: "thermometer.medium",
                    help: model.text(AppLocalizedPhrase.autoWhiteBalanceHelp),
                    trailingHelp: model.text(AppLocalizedPhrase.reset),
                    action: onAutoWhiteBalance,
                    trailingAction: onResetAutoWhiteBalance
                )
                .disabled(!canAutoAdjust)
            }
            .controlSize(.large)
        }
    }
}

private struct QuickTogglePill: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let systemImage: String
    let isOn: Binding<Bool>
    @State private var isHovered = false

    var body: some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)
                .frame(maxWidth: .infinity, minHeight: 32)
                .padding(.horizontal, 8)
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.primary)
                .background(
                    isOn.wrappedValue
                        ? Color.accentColor.opacity(0.2)
                        : Color.primary.opacity(isHovered ? 0.12 : 0),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .frame(maxWidth: .infinity)
        .liquidSurface(cornerRadius: 15, interactive: true)
        .help(title)
        .accessibilityLabel(title)
        .accessibilitySelectionState(
            isOn.wrappedValue,
            selectedValue: model.accessibilityText(.selected),
            unselectedValue: model.accessibilityText(.notSelected),
            unselectedHint: model.accessibilityText(.select)
        )
    }
}
