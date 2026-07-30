import Foundation
import Chromabase

private enum UserDevelopPresetStore {
    static let key = "negaflow.userDevelopPresets.v1"

    static func load() -> [DevelopUserPreset] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([DevelopUserPreset].self, from: data)) ?? []
    }

    static func save(_ presets: [DevelopUserPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

extension AppModel {
    func loadUserDevelopPresets() -> [DevelopUserPreset] {
        UserDevelopPresetStore.load()
    }

    func saveUserDevelopPresets() {
        UserDevelopPresetStore.save(userDevelopPresets)
    }

    @discardableResult
    func saveUserDevelopPreset(from frame: ScanFrame) -> UUID {
        let nextNumber = userDevelopPresets.count + 1
        let preset = frame.makeUserDevelopPreset(name: text(AppLocalizedPhrase.userPresetNameFormat, nextNumber))
        userDevelopPresets.append(preset)
        statusMessage = text(AppLocalizedPhrase.userPresetSavedFormat, preset.name)
        return preset.id
    }

    func applyUserDevelopPreset(_ preset: DevelopUserPreset, to frame: ScanFrame) {
        let restoredFrame = restoreSnapshotCompareState()
        let targetFrames = framesForContextAction(frame)
        guard !targetFrames.isEmpty else { return }
        for targetFrame in targetFrames {
            targetFrame.applyUserDevelopPreset(preset, presets: presets)
        }
        let appliedName = targetFrames.count == 1
            ? preset.name
            : "\(preset.name) · \(text(AppLocalizedPhrase.framesFormat, targetFrames.count))"
        statusMessage = text(AppLocalizedPhrase.userPresetAppliedFormat, appliedName)
        let targetIDs = Set(targetFrames.map(\.id))
        let framesToDevelop = restoredFrame.map { restored in
            targetIDs.contains(restored.id) ? targetFrames : [restored] + targetFrames
        } ?? targetFrames
        developFramesAfterSettingsTransfer(framesToDevelop)
    }

    func deleteUserDevelopPreset(_ preset: DevelopUserPreset) {
        userDevelopPresets.removeAll { $0.id == preset.id }
        statusMessage = text(AppLocalizedPhrase.userPresetDeletedFormat, preset.name)
    }
}
