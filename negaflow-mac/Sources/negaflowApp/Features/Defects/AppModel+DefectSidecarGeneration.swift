import Foundation

extension AppModel {
    /// 앞서 예약된 원자 쓰기 완료 후 가벼운 파일 관찰값으로 저장 세대를 확인합니다.
    func defectSidecarsMatchCurrentFrames(_ snapshotFrames: [ScanFrame]) -> Bool {
        DefectSidecarFile.flushSync()
        return snapshotFrames.filter { !$0.isPreviewScan }.allSatisfy { frame in
            guard !frame.defectEditsNeedRestore else { return false }
            guard !frame.defectEdits.isEmpty else { return true }
            guard let identity = frame.defectRecipeIdentity else { return false }
            return DefectSidecarCommitCache.shared.matches(identity, at:
                DefectSidecarFile.url(for: frame.id, in: libraryDefectDirectoryURL))
        }
    }
}
