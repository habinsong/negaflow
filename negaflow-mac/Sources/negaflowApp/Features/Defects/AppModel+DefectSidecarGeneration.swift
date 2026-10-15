import Foundation

private enum DefectSidecarValidationCode: String {
    case restorePending = "defect_restore_pending"
    case identityMissing = "defect_identity_missing"
    case sidecarMismatch = "defect_sidecar_mismatch"
}

extension AppModel {
    /// 앞서 예약된 원자 쓰기 완료 후 가벼운 파일 관찰값으로 저장 세대를 확인합니다.
    func defectSidecarsMatchCurrentFrames(_ snapshotFrames: [ScanFrame]) -> Bool {
        defectSidecarValidationFailure(snapshotFrames) == nil
    }

    func defectSidecarValidationFailure(_ snapshotFrames: [ScanFrame]) -> String? {
        DefectSidecarFile.flushSync()
        for frame in snapshotFrames where !frame.isPreviewScan {
            guard !frame.defectEditsNeedRestore else { return DefectSidecarValidationCode.restorePending.rawValue }
            guard !frame.defectEdits.isEmpty else { continue }
            guard let identity = frame.defectRecipeIdentity else { return DefectSidecarValidationCode.identityMissing.rawValue }
            let cache = DefectSidecarCommitCache.shared
            guard cache.matches(identity, at:
                DefectSidecarFile.url(for: frame.id, in: libraryDefectDirectoryURL))
                || cache.revalidate(identity, frameID: frame.id, in: libraryDefectDirectoryURL) else {
                return DefectSidecarValidationCode.sidecarMismatch.rawValue
            }
        }
        return nil
    }

    /// 지금 recipe 세대가 디스크 기록으로 이미 확인됐는지 해시 없이 본다. 제스처나 live 갱신이
    /// 걸려 있거나 식별값이 비어 있으면 확정되지 않은 것이다 — 그때만 다시 해시해 저장한다.
    func isDefectRecipeCommitted(_ frame: ScanFrame) -> Bool {
        guard !frame.defectEditsNeedRestore,
              !frame.defectGestureRecipeAdvanced,
              frame.defectRecipeRefreshTask == nil,
              let identity = frame.defectRecipeIdentity,
              identity.revision == frame.defectRecipeRevision else { return false }
        return DefectSidecarCommitCache.shared.matches(
            identity, at: DefectSidecarFile.url(for: frame.id, in: libraryDefectDirectoryURL)
        )
    }
}
