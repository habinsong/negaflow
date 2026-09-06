import Foundation

extension AppModel {
    /// 종료 전 recipe의 원자 저장을 확인합니다. 원본 픽셀과 URL은 변경하지 않습니다.
    func bakeDefectEditsForTermination() async -> Bool {
        for frame in frames where !frame.isPreviewScan {
            guard !frame.defectEditsNeedRestore else { return false }
            cancelPendingDefectRecipeRefresh(frame)
            guard !frame.defectEdits.isEmpty else { continue }
            guard let snapshot = refreshDefectRecipeState(
                frame, advanceRevision: frame.defectGestureRecipeAdvanced, persist: false
            ) else { return false }
            let identity = snapshot.identity
            let directory = libraryDefectDirectoryURL
            let saved = await Task.detached(priority: .utility) {
                do {
                    switch try DefectSidecarFile.write(snapshot, in: directory) {
                    case .written, .alreadyCurrent: return true
                    case .skippedNewer: return false
                    }
                } catch { return false }
            }.value
            guard saved, ownsFrame(frame), frame.defectRecipeIdentity == identity else { return false }
        }
        await Task.detached(priority: .utility) { DefectSidecarFile.flushSync() }.value
        return true
    }
}
