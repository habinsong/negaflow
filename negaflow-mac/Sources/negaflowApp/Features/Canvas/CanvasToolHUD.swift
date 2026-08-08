import SwiftUI

struct CanvasToolHUD: View {
    @EnvironmentObject private var model: AppModel
    let zoomText: String
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onSetZoomPercent: (Double) -> Void
    let onFit: () -> Void
    let onActualSize: () -> Void
    @State private var isEditingZoom = false
    @State private var zoomPercentText = ""

    var body: some View {
        HStack(spacing: 4) {
            CanvasToolButton(systemName: "minus.magnifyingglass", help: model.text(AppLocalizedPhrase.zoomOut), action: onZoomOut)
            CanvasToolButton(systemName: "plus.magnifyingglass", help: model.text(AppLocalizedPhrase.zoomIn), action: onZoomIn)
            Button {
                zoomPercentText = zoomText.replacingOccurrences(of: "%", with: "")
                isEditingZoom = true
            } label: {
                Text(zoomText)
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .frame(width: 46, height: 22)
            }
            .buttonStyle(.plain)
            .help(model.text(AppLocalizedPhrase.zoomPercentHelp))
            .popover(isPresented: $isEditingZoom) {
                zoomEditor
            }
            CanvasToolButton(systemName: "arrow.up.left.and.arrow.down.right", help: model.text(AppLocalizedPhrase.fitToScreen), action: onFit)
            CanvasToolButton(systemName: "1.magnifyingglass", help: model.text(AppLocalizedPhrase.actualSize), action: onActualSize)
        }
        .padding(3)
        .liquidSurface(cornerRadius: 10, interactive: true)
    }

    private var zoomEditor: some View {
        HStack(spacing: 8) {
            TextField("100", text: $zoomPercentText)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospacedDigit())
                .frame(width: 72)
                .onSubmit(applyZoomPercent)
            Text("%")
                .foregroundStyle(.secondary)
            Button(model.text(AppLocalizedPhrase.apply), action: applyZoomPercent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .frame(width: 176)
    }

    private func applyZoomPercent() {
        let normalized = zoomPercentText
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(normalized), value.isFinite else { return }
        onSetZoomPercent(min(max(value, 5), 1600))
        isEditingZoom = false
    }
}

struct CanvasToolButton: View {
    @EnvironmentObject private var model: AppModel
    let systemName: String
    let help: String
    var isActive: Bool? = nil
    var activeTint: Color = .accentColor
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 22, height: 22)
                .foregroundStyle(isActive == true ? .white : Color.primary)
                .background(
                    isActive == true ? activeTint : Color.primary.opacity(isHovered ? 0.12 : 0),
                    in: RoundedRectangle(cornerRadius: 7)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
