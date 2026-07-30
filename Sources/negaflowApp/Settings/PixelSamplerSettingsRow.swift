import SwiftUI

struct PixelSamplerSettingsRow: View {
    @ObservedObject var store: PixelSamplerStore
    let language: AppLanguage
    let onSetEnabled: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        Group {
            AppSettingsToggleRow(
                label: PixelSamplerLocalizedText.enabled.resolved(language: language),
                isOn: Binding(
                    get: { store.isEnabled },
                    set: onSetEnabled
                )
            )
            if store.isEnabled {
                AppSettingsHelpText(
                    PixelSamplerLocalizedText.movePointer.resolved(language: language)
                )
            }
        }
    }
}
