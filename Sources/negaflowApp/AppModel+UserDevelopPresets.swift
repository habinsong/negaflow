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
        let preset = frame.makeUserDevelopPreset(name: "Preset \(nextNumber)")
        userDevelopPresets.append(preset)
        statusMessage = "사용자 프리셋 저장됨: \(preset.name)"
        return preset.id
    }

    func applyUserDevelopPreset(_ preset: DevelopUserPreset, to frame: ScanFrame) {
        let restoredFrame = restoreSnapshotCompareState()
        frame.applyUserDevelopPreset(preset, presets: presets)
        statusMessage = "사용자 프리셋 적용됨: \(preset.name)"
        Task {
            if let restoredFrame, restoredFrame.id != frame.id {
                await developFrame(restoredFrame)
            }
            await developFrame(frame)
        }
    }

    func deleteUserDevelopPreset(_ preset: DevelopUserPreset) {
        userDevelopPresets.removeAll { $0.id == preset.id }
        statusMessage = "사용자 프리셋 삭제됨: \(preset.name)"
    }
}
