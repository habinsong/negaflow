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
        let nextTransform = scope.geometry ? snapshot.imageTransform : currentTransform
        var nextParams = scopedParams
        nextParams.imageTransform = nextTransform
        imageTransform = nextTransform
        params = nextParams
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
        presetParams.imageTransform = imageTransform
        return DevelopUserPreset(name: name, params: presetParams, presetID: preset?.id)
    }

    func applyUserDevelopPreset(_ preset: DevelopUserPreset, presets: [LookPreset]) {
        let presetParams = preset.params
        filmType = presetParams.filmType
        self.preset = preset.presetID.flatMap { id in presets.first(where: { $0.id == id }) }
        params = presetParams
        imageTransform = presetParams.imageTransform
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

        let targetFrames = framesForContextAction(frame)
        guard !targetFrames.isEmpty else { return }
        for targetFrame in targetFrames {
            targetFrame.applyDevelopSettingsSnapshot(copiedDevelopSettings, scope: scope)
        }
        let action = scope.isFullDevelopScope
            ? text(AppLocalizedPhrase.developSettingsPasted)
            : text(AppLocalizedPhrase.developSettingsPartiallyPastedFormat, scope.displayName(language: appLanguage))
        let destination = targetFrames.count == 1
            ? targetFrames[0].displayName
            : text(AppLocalizedPhrase.framesFormat, targetFrames.count)
        statusMessage = text(
            AppLocalizedPhrase.developSettingsPasteStatusFormat,
            action,
            copiedDevelopSettings.sourceFrameName,
            destination
        )
        developFramesAfterSettingsTransfer(targetFrames)
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

    @discardableResult
    func developFramesAfterSettingsTransfer(
        _ requestedFrames: [ScanFrame]
    ) -> Task<Void, Never> {
        let frames = requestedFrames.filter { ownsFrame($0) && !$0.isPreviewScan }
        let previousTask = sequentialLibraryDevelopmentTask
        let task = Task { [weak self] in
            await previousTask?.value
            guard let self, !Task.isCancelled else { return }

            // 대량 선택 붙여넣기에서 프레임 수만큼 비구조적 Task를 한꺼번에 만들면 수천 개의
            // continuation과 인터랙티브 현상 결과가 동시에 대기한다. 실제 렌더 슬롯 수만큼만
            // 고정 worker를 유지해 메모리를 제한하면서 기존 2-way 처리량은 보존한다.
            var nextIndex = 0
            await withTaskGroup(of: Void.self) { group in
                func enqueueNext() {
                    guard nextIndex < frames.count else { return }
                    let frame = frames[nextIndex]
                    nextIndex += 1
                    group.addTask { [weak self, weak frame] in
                        guard let self, let frame, !Task.isCancelled else { return }
                        await self.developFrameAfterSettingsTransfer(frame)
                    }
                }

                for _ in 0..<min(self.developController.maxConcurrentDevelopments, frames.count) {
                    enqueueNext()
                }
                while await group.next() != nil {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    enqueueNext()
                }
            }
        }
        sequentialLibraryDevelopmentTask = task
        return task
    }

    private func developFrameAfterSettingsTransfer(_ frame: ScanFrame) async {
        if let seed = frame.initialThumbnailSeedTask {
            await seed.value
        }
        guard !Task.isCancelled, ownsFrame(frame) else { return }
        await developFrame(frame, skipInteractivePreview: true)
    }
}
