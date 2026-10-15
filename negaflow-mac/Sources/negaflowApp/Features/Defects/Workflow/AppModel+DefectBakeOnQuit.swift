import Foundation

extension AppModel {
    /// 종료 전 recipe의 원자 저장을 확인합니다. 원본 픽셀과 URL은 변경하지 않습니다.
    func bakeDefectEditsForTermination() async -> Bool {
        for frame in frames where !frame.isPreviewScan {
            if frame.defectEditsNeedRestore {
                // 아직 읽지 않은 기록은 디스크 기록이 곧 확정본이다. 읽기에 실패한 기록만 막는다.
                guard frame.defectEditsLoadDeferred else { return false }
                continue
            }
            // 이미 같은 세대로 저장이 확인된 recipe 는 다시 해시·기록하지 않는다 — 종료가 결함
            // 기록 전체를 다시 읽고 SHA-256 을 돌리느라 몇 초씩 멈추던 원인이다.
            if !frame.defectEdits.isEmpty, isDefectRecipeCommitted(frame) { continue }
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
                } catch {
                    AppModel.recordDefectSidecarWriteFailure("\(error)")
                    return false
                }
            }.value
            guard saved, ownsFrame(frame), frame.defectRecipeIdentity == identity else { return false }
        }
        await Task.detached(priority: .utility) { DefectSidecarFile.flushSync() }.value
        return true
    }
}
