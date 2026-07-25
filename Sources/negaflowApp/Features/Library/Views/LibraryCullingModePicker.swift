import SwiftUI

struct LibraryCullingModePicker: View {
    @EnvironmentObject private var model: AppModel
    @Binding var mode: LibraryCullingMode
    let selectionCount: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach([LibraryCullingMode.grid, .survey]) { option in
                Button {
                    mode = option
                } label: {
                    Image(systemName: option.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 27, height: 24)
                        .background(
                            mode == option ? Color.primary.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .help(label(option))
                .accessibilityLabel(label(option))
                .accessibilitySelectionState(
                    mode == option,
                    selectedValue: model.accessibilityText(.selected),
                    unselectedValue: model.accessibilityText(.notSelected),
                    unselectedHint: model.accessibilityText(.select)
                )
            }

            if mode != .grid {
                Text(selectionCount, format: .number)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22)
            }
        }
        .padding(2)
        .liquidSurface(cornerRadius: 8, interactive: true)
    }

    private func label(_ mode: LibraryCullingMode) -> String {
        switch mode {
        case .grid: return model.cullingText(.grid)
        case .compare: return model.cullingText(.compare)
        case .survey: return model.cullingText(.survey)
        }
    }
}
