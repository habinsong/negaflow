import Foundation
import Chromabase

struct DevelopSettingsSnapshot {
    let sourceFrameName: String
    let params: DevelopParameters
    let preset: LookPreset?
    let imageTransform: ImageTransform
}

struct DevelopSnapshot: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
    let params: DevelopParameters
    let presetID: String?
}

struct SnapshotCompareState {
    let frameID: UUID
    let snapshotID: UUID
    let base: DevelopSettingsSnapshot
}

extension ScanFrame {
    var developSettingsSnapshot: DevelopSettingsSnapshot {
        var copiedParams = params
        copiedParams.filmType = filmType
        copiedParams.imageTransform = imageTransform
        return DevelopSettingsSnapshot(
            sourceFrameName: displayName,
            params: copiedParams,
            preset: preset,
            imageTransform: imageTransform
        )
    }

    func applyDevelopSettingsSnapshot(_ snapshot: DevelopSettingsSnapshot) {
        var pastedParams = snapshot.params
        pastedParams.imageTransform = snapshot.imageTransform
        filmType = pastedParams.filmType
        preset = snapshot.preset
        imageTransform = snapshot.imageTransform
        params = pastedParams
    }

    func applyDevelopSettingsSnapshot(
        _ snapshot: DevelopSettingsSnapshot,
        scope: DevelopSettingsPasteScope
    ) {
        guard !scope.isEmpty else { return }
        guard !scope.isFullDevelopScope else {
            applyDevelopSettingsSnapshot(snapshot)
            return
        }

        let currentTransform = imageTransform
        let scopedParams = scope.applying(source: snapshot.params, to: params)
        if scope.base {
            filmType = scopedParams.filmType
        }
        if scope.tone {
            preset = snapshot.preset
        }
        imageTransform = currentTransform
        params = scopedParams
    }

    func makeDevelopSnapshot(name: String) -> DevelopSnapshot {
        var snapshotParams = params
        snapshotParams.filmType = filmType
        snapshotParams.imageTransform = imageTransform
        return DevelopSnapshot(
            id: UUID(),
            name: name,
            createdAt: Date(),
            params: snapshotParams,
            presetID: preset?.id
        )
    }

    func applyDevelopSnapshot(_ snapshot: DevelopSnapshot, presets: [LookPreset]) {
        let snapshotParams = snapshot.params
        filmType = snapshotParams.filmType
        preset = snapshot.presetID.flatMap { id in presets.first(where: { $0.id == id }) }
        imageTransform = snapshotParams.imageTransform
        params = snapshotParams
    }

    func makeUserDevelopPreset(name: String) -> DevelopUserPreset {
        var presetParams = params
        presetParams.filmType = filmType
        presetParams.imageTransform = .identity
        return DevelopUserPreset(name: name, params: presetParams, presetID: preset?.id)
    }

    func applyUserDevelopPreset(_ preset: DevelopUserPreset, presets: [LookPreset]) {
        let currentTransform = imageTransform
        var presetParams = preset.params
        presetParams.imageTransform = currentTransform
        filmType = presetParams.filmType
        self.preset = preset.presetID.flatMap { id in presets.first(where: { $0.id == id }) }
        params = presetParams
        imageTransform = currentTransform
    }
}

extension AppModel {
    func copyDevelopSettings(from frame: ScanFrame) {
        copiedDevelopSettings = frame.developSettingsSnapshot
        statusMessage = text(AppLocalizedPhrase.developSettingsCopiedFormat, frame.displayName)
    }

    func pasteDevelopSettings(to frame: ScanFrame, scope: DevelopSettingsPasteScope = .all) {
        guard let copiedDevelopSettings else {
            statusMessage = text(AppLocalizedPhrase.noDevelopSettingsToPaste)
            return
        }
        guard !scope.isEmpty else {
            statusMessage = text(AppLocalizedPhrase.chooseDevelopPasteScope)
            return
        }

        frame.applyDevelopSettingsSnapshot(copiedDevelopSettings, scope: scope)
        let action = scope.isFullDevelopScope
            ? text(AppLocalizedPhrase.developSettingsPasted)
            : text(AppLocalizedPhrase.developSettingsPartiallyPastedFormat, scope.displayName(language: appLanguage))
        statusMessage = text(
            AppLocalizedPhrase.developSettingsPasteStatusFormat,
            action,
            copiedDevelopSettings.sourceFrameName,
            frame.displayName
        )
        Task { await developFrame(frame) }
    }

    @discardableResult
    func saveSnapshot(for frame: ScanFrame) -> UUID {
        let nextNumber = frame.developSnapshots.count + 1
        let snapshot = frame.makeDevelopSnapshot(name: text(AppLocalizedPhrase.snapshotNameFormat, nextNumber))
        frame.developSnapshots.append(snapshot)
        statusMessage = text(AppLocalizedPhrase.snapshotSavedFormat, snapshot.name)
        return snapshot.id
    }

    func applySnapshot(_ snapshot: DevelopSnapshot, to frame: ScanFrame) {
        let restoredFrame = restoreSnapshotCompareState()
        frame.applyDevelopSnapshot(snapshot, presets: presets)
        statusMessage = text(AppLocalizedPhrase.snapshotAppliedFormat, snapshot.name)
        Task {
            if let restoredFrame, restoredFrame.id != frame.id {
                await developFrame(restoredFrame)
            }
            await developFrame(frame)
        }
    }

    func toggleSnapshotCompare(_ snapshot: DevelopSnapshot, for frame: ScanFrame) {
        if let state = snapshotCompareState,
           state.frameID == frame.id,
           state.snapshotID == snapshot.id {
            snapshotCompareState = nil
            frame.applyDevelopSettingsSnapshot(state.base)
            statusMessage = text(AppLocalizedPhrase.snapshotCompareEnded)
            Task { await developFrame(frame) }
            return
        }

        let restoredFrame = restoreSnapshotCompareState()
        let base = frame.developSettingsSnapshot
        frame.applyDevelopSnapshot(snapshot, presets: presets)
        snapshotCompareState = SnapshotCompareState(frameID: frame.id, snapshotID: snapshot.id, base: base)
        statusMessage = text(AppLocalizedPhrase.snapshotComparingFormat, snapshot.name)
        Task {
            if let restoredFrame, restoredFrame.id != frame.id {
                await developFrame(restoredFrame)
            }
            await developFrame(frame)
        }
    }

    func restoreSnapshotCompareState() -> ScanFrame? {
        guard let state = snapshotCompareState else { return nil }
        snapshotCompareState = nil
        guard let frame = frames.first(where: { $0.id == state.frameID }) else { return nil }
        frame.applyDevelopSettingsSnapshot(state.base)
        return frame
    }
}
