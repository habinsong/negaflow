import SwiftUI
import Chromabase

struct UserPresetSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @State private var selectedPresetID: UUID?
    @State private var isNamingPreset = false
    @State private var presetName = ""
    @State private var showsDuplicateWarning = false
    @FocusState private var isNameFieldFocused: Bool

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
            .accessibilityIdentifier("negaflow.develop.presets.selector")

            if isNamingPreset {
                HStack(spacing: 8) {
                    TextField(
                        text: $presetName,
                        prompt: Text(model.text(AppLocalizedPhrase.userPresetNamePlaceholder))
                    ) {
                        Text(model.text(AppLocalizedPhrase.userPresetNamePlaceholder))
                    }
                    .labelsHidden()
                    .focused($isNameFieldFocused)
                    .onSubmit { commitPresetName() }
                    .onExitCommand { endNaming() }
                    .onChange(of: presetName) { _, _ in showsDuplicateWarning = false }
                    .accessibilityIdentifier("negaflow.develop.presets.name")

                    // Esc 로도 물러날 수 있지만, 눌러서 닫는 자리도 있어야 합니다.
                    Button { endNaming() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(model.text(AppLocalizedPhrase.cancel))
                    .accessibilityLabel(model.text(AppLocalizedPhrase.cancel))
                    .accessibilityIdentifier("negaflow.develop.presets.name-cancel")
                }

                if showsDuplicateWarning {
                    Label(
                        model.text(AppLocalizedPhrase.userPresetNameDuplicate),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 8) {
                TransferButton(
                    title: model.text(AppLocalizedPhrase.save),
                    systemName: "square.and.arrow.down",
                    help: model.text(AppLocalizedPhrase.saveUserPresetHelp)
                ) {
                    // 저장을 누르면 이름부터 묻습니다. 이미 묻고 있으면 그 이름으로 저장합니다.
                    if isNamingPreset {
                        commitPresetName()
                    } else {
                        beginNaming()
                    }
                }
                .accessibilityIdentifier("negaflow.develop.presets.save")

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
        // 저장 대상은 지금 보고 있는 사진입니다. 사진이 바뀌면 적다 만 이름은 닫습니다.
        .onChange(of: frame.id) { _, _ in endNaming() }
    }

    func beginNaming() {
        presetName = ""
        showsDuplicateWarning = false
        isNamingPreset = true
        isNameFieldFocused = true
    }

    func commitPresetName() {
        guard let savedID = model.saveUserDevelopPreset(from: frame, name: presetName) else {
            // 겹치는 이름은 저장하지 않고 입력란을 그대로 둡니다 — 다시 적을 자리가 필요합니다.
            showsDuplicateWarning = true
            isNameFieldFocused = true
            return
        }
        selectedPresetID = savedID
        endNaming()
    }

    func endNaming() {
        presetName = ""
        showsDuplicateWarning = false
        isNamingPreset = false
        isNameFieldFocused = false
    }

    func ensureSelection() {
        if let selectedPresetID,
           model.userDevelopPresets.contains(where: { $0.id == selectedPresetID }) {
            return
        }
        selectedPresetID = model.userDevelopPresets.last?.id
    }
}
