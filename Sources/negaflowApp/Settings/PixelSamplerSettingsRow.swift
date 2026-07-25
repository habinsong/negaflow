import SwiftUI

struct PixelSamplerSettingsRow: View {
    @ObservedObject var store: PixelSamplerStore
    let language: AppLanguage
    let onSetEnabled: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        LabeledContent(PixelSamplerLocalizedText.enabled.resolved(language: language)) {
            VStack(alignment: .trailing, spacing: 2) {
                Toggle("", isOn: Binding(
                    get: { store.isEnabled },
                    set: onSetEnabled
                ))
                .labelsHidden()
                if store.isEnabled {
                    Text(PixelSamplerLocalizedText.movePointer.resolved(language: language))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
