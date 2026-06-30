import Foundation
import Chromabase

extension ScanFrame {
    func makeDevelopHistoryEntry(label: String) -> DevelopHistoryEntry {
        var historyParams = params
        historyParams.filmType = filmType
        historyParams.imageTransform = imageTransform
        return DevelopHistoryEntry(label: label, params: historyParams, presetID: preset?.id)
    }

    func applyDevelopHistoryEntry(_ entry: DevelopHistoryEntry, presets: [LookPreset]) {
        let historyParams = entry.params
        filmType = historyParams.filmType
        preset = entry.presetID.flatMap { id in presets.first(where: { $0.id == id }) }
        imageTransform = historyParams.imageTransform
        params = historyParams
    }
}

extension AppModel {
    @discardableResult
    func recordDevelopHistory(for frame: ScanFrame) -> UUID {
        let nextNumber = frame.developHistory.count + 1
        let entry = frame.makeDevelopHistoryEntry(label: "History \(nextNumber)")
        frame.developHistory.append(entry)
        statusMessage = "History 기록됨: \(entry.label)"
        return entry.id
    }

    func applyDevelopHistory(_ entry: DevelopHistoryEntry, to frame: ScanFrame) {
        let restoredFrame = restoreSnapshotCompareState()
        frame.applyDevelopHistoryEntry(entry, presets: presets)
        statusMessage = "History 적용됨: \(entry.label)"
        Task {
            if let restoredFrame, restoredFrame.id != frame.id {
                await developFrame(restoredFrame)
            }
            await developFrame(frame)
        }
    }
}
