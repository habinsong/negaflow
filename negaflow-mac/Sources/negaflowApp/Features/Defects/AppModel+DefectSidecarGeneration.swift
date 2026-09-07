import Foundation

extension AppModel {
    /// 앞서 예약된 원자 쓰기 완료 후 가벼운 파일 관찰값으로 저장 세대를 확인합니다.
    func defectSidecarsMatchCurrentFrames(_ snapshotFrames: [ScanFrame]) -> Bool {
        defectSidecarValidationFailure(snapshotFrames) == nil
    }

    func defectSidecarValidationFailure(_ snapshotFrames: [ScanFrame]) -> String? {
        DefectSidecarFile.flushSync()
        for frame in snapshotFrames where !frame.isPreviewScan {
            guard !frame.defectEditsNeedRestore else { return "defect_restore_pending" }
            guard !frame.defectEdits.isEmpty else { continue }
            guard let identity = frame.defectRecipeIdentity else { return "defect_identity_missing" }
            guard DefectSidecarCommitCache.shared.matches(identity, at:
                DefectSidecarFile.url(for: frame.id, in: libraryDefectDirectoryURL)) else {
                return "defect_sidecar_mismatch"
            }
        }
        return nil
    }
}
