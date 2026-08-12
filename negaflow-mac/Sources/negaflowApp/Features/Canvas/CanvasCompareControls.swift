import SwiftUI

enum CanvasCompareOrientation {
    case vertical
    case horizontal
}

struct CanvasCompareBeforeOption: Identifiable, Hashable {
    let id: String
    let label: String
    let systemImage: String
}

struct CanvasCompareLabels: View {
    @EnvironmentObject private var model: AppModel
    let imageFrame: CGRect
    let orientation: CanvasCompareOrientation
    let beforeLabel: String
    let selectedBeforeID: String
    let primaryBeforeOptions: [CanvasCompareBeforeOption]
    let frameBeforeOptions: [CanvasCompareBeforeOption]
    let onSelectBefore: (String) -> Void
    let onSelectCurrent: () -> Void

    var body: some View {
        ZStack {
            Menu {
                Text(model.text(AppLocalizedPhrase.before))
                ForEach(primaryBeforeOptions) { option in
                    beforeOptionButton(option)
                }
                if !frameBeforeOptions.isEmpty {
                    Menu {
                        ForEach(frameBeforeOptions) { option in
                            beforeOptionButton(option)
                        }
                    } label: {
                        Label(model.text(.menuPhoto), systemImage: "photo.stack")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(beforeLabel)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(AppTypography.microIcon)
                        .foregroundStyle(.secondary)
                }
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .liquidSurface(cornerRadius: 6)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 112)
            .help(model.text(AppLocalizedPhrase.beforeSourceHelp))
            .accessibilitySelectionState(
                true,
                selectedValue: model.accessibilityText(.selected),
                unselectedValue: model.accessibilityText(.notSelected)
            )
            .position(
                x: imageFrame.minX + 60,
                y: imageFrame.minY + 48
            )

            Button(action: onSelectCurrent) {
                Text(model.text(AppLocalizedPhrase.currentImage))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .liquidSurface(cornerRadius: 6, interactive: true)
            }
            .buttonStyle(.plain)
            .help(model.text(AppLocalizedPhrase.currentImage))
            .accessibilityLabel(model.text(AppLocalizedPhrase.currentImage))
            .accessibilitySelectionState(
                true,
                selectedValue: model.accessibilityText(.selected),
                unselectedValue: model.accessibilityText(.notSelected)
            )
            .position(
                x: afterLabelX,
                y: afterLabelY
            )
        }
    }

    private func beforeOptionButton(_ option: CanvasCompareBeforeOption) -> some View {
        Button {
            onSelectBefore(option.id)
        } label: {
            if option.id == selectedBeforeID {
                Label(option.label, systemImage: "checkmark")
            } else {
                Label(option.label, systemImage: option.systemImage)
            }
        }
        .accessibilityLabel(option.label)
        .accessibilitySelectionState(
            option.id == selectedBeforeID,
            selectedValue: model.accessibilityText(.selected),
            unselectedValue: model.accessibilityText(.notSelected),
            unselectedHint: model.accessibilityText(.select)
        )
    }

    private var afterLabelX: CGFloat {
        switch orientation {
        case .vertical:
            return imageFrame.maxX - 38
        case .horizontal:
            return imageFrame.minX + 36
        }
    }

    private var afterLabelY: CGFloat {
        switch orientation {
        case .vertical:
            return imageFrame.minY + 48
        case .horizontal:
            return imageFrame.maxY - 18
        }
    }

}

struct CanvasCompareToggle: View {
    @EnvironmentObject private var model: AppModel
    let activeMode: CanvasCompareMode
    let onSelectMode: (CanvasCompareMode) -> Void

    private var content: Color { model.canvasBackground.hudContentColor }

    var body: some View {
        HStack(spacing: 2) {
            compareButton(title: model.text(AppLocalizedPhrase.raw), mode: .raw)
            compareButton(title: model.text(AppLocalizedPhrase.developed), mode: .developed)
            compareIconButton(
                systemName: "rectangle.lefthalf.inset.filled",
                help: model.text(AppLocalizedPhrase.compareSplitVertical),
                mode: .splitVertical
            )
            compareIconButton(
                systemName: "rectangle.tophalf.inset.filled",
                help: model.text(AppLocalizedPhrase.compareSplitHorizontal),
                mode: .splitHorizontal
            )
        }
        .padding(2)
        .canvasControlSurface(model.canvasBackground, cornerRadius: 10)
    }

    private func compareButton(title: String, mode: CanvasCompareMode) -> some View {
        let active = activeMode == mode
        return Button {
            onSelectMode(mode)
        } label: {
            Text(title)
                .font(.caption.weight(active ? .semibold : .regular))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .foregroundStyle(active ? content : content.opacity(0.65))
                .background(active ? content.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilitySelectionState(
            active,
            selectedValue: model.accessibilityText(.selected),
            unselectedValue: model.accessibilityText(.notSelected),
            unselectedHint: model.accessibilityText(.select)
        )
    }

    private func compareIconButton(systemName: String, help: String, mode: CanvasCompareMode) -> some View {
        let active = activeMode == mode
        return Button {
            onSelectMode(mode)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 24)
                .foregroundStyle(active ? content : content.opacity(0.65))
                .background(active ? content.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilitySelectionState(
            active,
            selectedValue: model.accessibilityText(.selected),
            unselectedValue: model.accessibilityText(.notSelected),
            unselectedHint: model.accessibilityText(.select)
        )
    }
}
