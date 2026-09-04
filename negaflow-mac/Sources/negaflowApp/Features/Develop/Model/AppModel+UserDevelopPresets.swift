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

    /// 이름을 비워 두면 겹치지 않는 번호 이름이 붙고, 적어 준 이름이 이미 있으면 저장하지
    /// 않습니다(`nil`). 목록에 같은 이름이 둘이면 어느 것을 고르는지 알 수 없습니다.
    @discardableResult
    func saveUserDevelopPreset(from frame: ScanFrame, name: String) -> UUID? {
        guard let resolvedName = DevelopUserPresetNaming.resolve(
            requested: name,
            existing: userDevelopPresets.map(\.name),
            autoName: { text(AppLocalizedPhrase.userPresetNameFormat, $0) }
        ) else {
            statusMessage = text(AppLocalizedPhrase.userPresetNameDuplicate)
            return nil
        }
        let preset = frame.makeUserDevelopPreset(name: resolvedName)
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
