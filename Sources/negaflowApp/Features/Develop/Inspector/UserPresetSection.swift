import SwiftUI
import Chromabase

struct UserPresetSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @State private var selectedPresetID: UUID?

    var selectedPreset: DevelopUserPreset? {
        guard let selectedPresetID else { return model.userDevelopPresets.last }
        return model.userDevelopPresets.first(where: { $0.id == selectedPresetID }) ?? model.userDevelopPresets.last
    }

    var body: some View {
        Section {
            Picker(model.text(AppLocalizedPhrase.userPreset), selection: $selectedPresetID) {
                if model.userDevelopPresets.isEmpty {
                    Text(model.text(AppLocalizedPhrase.noUserPresets)).tag(UUID?.none)
                } else {
                    ForEach(model.userDevelopPresets) { preset in
                        Text(preset.name).tag(preset.id as UUID?)
                    }
                }
            }
            .disabled(model.userDevelopPresets.isEmpty)

            HStack(spacing: 8) {
                TransferButton(
                    title: model.text(AppLocalizedPhrase.save),
                    systemName: "square.and.arrow.down",
                    help: model.text(AppLocalizedPhrase.saveUserPresetHelp)
                ) {
                    selectedPresetID = model.saveUserDevelopPreset(from: frame)
                }

                TransferButton(
                    title: model.text(AppLocalizedPhrase.apply),
                    systemName: "checkmark.circle",
                    help: model.text(AppLocalizedPhrase.applyUserPresetHelp),
                    isDisabled: selectedPreset == nil
                ) {
                    guard let selectedPreset else { return }
                    model.applyUserDevelopPreset(selectedPreset, to: frame)
                }

                TransferButton(
                    title: model.text(AppLocalizedPhrase.delete),
                    systemName: "trash",
                    help: model.text(AppLocalizedPhrase.deleteUserPresetHelp),
                    isDisabled: selectedPreset == nil
                ) {
                    guard let selectedPreset else { return }
                    model.deleteUserDevelopPreset(selectedPreset)
                    selectedPresetID = model.userDevelopPresets.last?.id
                }
            }
        } header: {
            sectionHeader(model.text(AppLocalizedPhrase.userPreset), systemImage: "slider.horizontal.below.square.and.square.filled")
        }
        .onAppear { ensureSelection() }
        .onChange(of: model.userDevelopPresets.map(\.id)) { _, _ in ensureSelection() }
    }

    func ensureSelection() {
        if let selectedPresetID,
           model.userDevelopPresets.contains(where: { $0.id == selectedPresetID }) {
            return
        }
        selectedPresetID = model.userDevelopPresets.last?.id
    }
}
