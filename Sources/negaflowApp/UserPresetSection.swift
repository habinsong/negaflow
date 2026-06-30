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
            Picker("User Preset", selection: $selectedPresetID) {
                if model.userDevelopPresets.isEmpty {
                    Text("No user presets").tag(UUID?.none)
                } else {
                    ForEach(model.userDevelopPresets) { preset in
                        Text(preset.name).tag(preset.id as UUID?)
                    }
                }
            }
            .disabled(model.userDevelopPresets.isEmpty)

            HStack(spacing: 8) {
                TransferButton(
                    title: "Save",
                    systemName: "square.and.arrow.down",
                    help: "현재 현상 조합을 사용자 프리셋으로 저장"
                ) {
                    selectedPresetID = model.saveUserDevelopPreset(from: frame)
                }

                TransferButton(
                    title: "Apply",
                    systemName: "wand.and.stars",
                    help: "선택한 사용자 프리셋 적용",
                    isDisabled: selectedPreset == nil
                ) {
                    guard let selectedPreset else { return }
                    model.applyUserDevelopPreset(selectedPreset, to: frame)
                }

                TransferButton(
                    title: "Delete",
                    systemName: "trash",
                    help: "선택한 사용자 프리셋 삭제",
                    isDisabled: selectedPreset == nil
                ) {
                    guard let selectedPreset else { return }
                    model.deleteUserDevelopPreset(selectedPreset)
                    selectedPresetID = model.userDevelopPresets.last?.id
                }
            }
        } header: {
            sectionHeader("User Preset", systemImage: "slider.horizontal.below.square.and.square.filled")
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
