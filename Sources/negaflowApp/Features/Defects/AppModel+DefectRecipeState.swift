import CryptoKit
import Foundation
import ScannerKit

extension AppModel {
    /// 예약된 live fingerprint가 취소 후 늦게 완료되어도 frame에 적용되지
    /// 않게 generation을 먼저 올린다. 제스처 종료·undo·종료 저장의 동기 확정
    /// 경로가 모두 이 함수를 통해 pending 계산을 무효화한다.
    func cancelPendingDefectRecipeRefresh(_ frame: ScanFrame) {
        frame.defectRecipeRefreshGeneration &+= 1
        frame.defectRecipeRefreshTask?.cancel()
        frame.defectRecipeRefreshTask = nil
        frame.defectRecipeRefreshWorkerID = nil
        frame.defectRecipeRefreshChangedEditID = nil
    }

    /// 렌더에 영향을 주는 defect state가 바뀐 직후 호출한다. 기록은 세션 메모리에만 있고
    /// 디스크에 저장하지 않는다 — 종료 시 cleaned raw가 이미지로 구워지고 기록은 사라진다.
    /// persist 파라미터는 호출부 호환용이며 더 이상 디스크 IO를 일으키지 않는다.
    @discardableResult
    func refreshDefectRecipeState(
        _ frame: ScanFrame,
        advanceRevision: Bool,
        persist: Bool
    ) -> DefectRecipeSnapshot? {
        // live worker가 identity를 fail-closed하기 위해 비운 상태에서도 source binding은
        // 승계해야 한다. 먼저 캡은 뒤 worker를 취소하고 제스처를 종료해,
        // enabled/remove/clear/undo 같은 다른 semantic mutation이 와도 저장 guard가
        // 영구적으로 닫히지 않게 한다.
        let sourceIdentity = frame.defectGestureRecipeAdvanced
            ? frame.defectGestureSourceIdentity
            : frame.defectRecipeIdentity?.sourceIdentity
        cancelPendingDefectRecipeRefresh(frame)
        if frame.defectGestureRecipeAdvanced {
            frame.defectGestureRecipeAdvanced = false
            frame.defectGestureUndoPushed = false
            frame.defectGestureSourceIdentity = nil
        }
        if advanceRevision || frame.defectRecipeRevision == 0 {
            guard frame.defectRecipeRevision < UInt64.max else {
                statusMessage = text(AppLocalizedPhrase.removingDefectsFailedStatus)
                return nil
            }
            frame.defectRecipeRevision += 1
        }

        guard !frame.defectEdits.isEmpty else {
            frame.defectRecipeIdentity = nil
            updateDefectReviewTracking(frame, identity: nil)
            invalidateLibraryQueryContext()
            scheduleLibrarySave()
            return nil
        }

        let records = frame.defectEdits.map { DefectEditItemRecord(item: $0) }
        let snapshot: DefectRecipeSnapshot
        do {
            snapshot = try DefectRecipeSnapshot(
                frameID: frame.id,
                revision: frame.defectRecipeRevision,
                sourceIdentity: sourceIdentity,
                items: records
            )
        } catch {
            frame.defectRecipeIdentity = nil
            updateDefectReviewTracking(frame, identity: nil)
            statusMessage = text(AppLocalizedPhrase.removingDefectsFailedStatus)
            return nil
        }
        installDefectRecipeIdentity(snapshot.identity, on: frame)
        invalidateLibraryQueryContext()
        scheduleLibrarySave()
        return snapshot
    }

    nonisolated func bindDefectRecipeSnapshot(
        _ snapshot: DefectRecipeSnapshot,
        to sourceIdentity: DefectSourceIdentity
    ) throws -> DefectRecipeSnapshot {
        try DefectRecipeSnapshot(
            frameID: snapshot.frameID,
            revision: snapshot.identity.revision,
            sourceIdentity: sourceIdentity,
            items: snapshot.items
        )
    }

    func installDefectRecipeIdentity(
        _ identity: DefectRecipeIdentity,
        on frame: ScanFrame
    ) {
        frame.defectRecipeRevision = max(frame.defectRecipeRevision, identity.revision)
        if frame.defectRecipeIdentity != identity {
            frame.defectRecipeIdentity = identity
        }
        updateDefectReviewTracking(frame, identity: identity)
    }

    func markDefectRecipeReviewed(_ frame: ScanFrame) {
        guard ownsFrame(frame),
              !frame.isPreviewScan,
              let identity = frame.defectRecipeIdentity,
              let sourceIdentity = identity.sourceIdentity,
              var state = frame.libraryWorkflowTrackingState else { return }
        var tracking = state.defectReviewTracking
        tracking.coverage = .tracked
        tracking.currentRecipeRevision = identity.revision
        tracking.currentRecipeSHA256 = identity.recipeSHA256
        tracking.currentSourceIdentitySHA256 = sourceIdentity.sha256
        tracking.reviewedRecipeRevision = identity.revision
        tracking.reviewedRecipeSHA256 = identity.recipeSHA256
        tracking.reviewedSourceIdentitySHA256 = sourceIdentity.sha256
        state.defectReviewTracking = tracking
        frame.libraryWorkflowTrackingState = state
        invalidateLibraryQueryContext()
        scheduleLibrarySave()
    }

    /// 기록이 세션을 넘어 보존되지 않으므로(종료 시 이미지에 굽기) 콘텐츠 SHA-256 대신
    /// 파일시스템 관찰값(device/inode/size/mtime/ctime) 다이제스트를 쓴다 — 대형 TIFF를
    /// 읽거나 해시하지 않고도 같은 세션 안의 원본 교체를 감지한다.
    nonisolated static func defectSourceIdentity(for url: URL) throws -> DefectSourceIdentity {
        let observation = try CaptureFileObservation.capture(for: url)
        let canonical = [
            "\(observation.device)", "\(observation.inode)", "\(observation.byteCount)",
            "\(observation.modifiedSeconds).\(observation.modifiedNanoseconds)",
            "\(observation.changedSeconds).\(observation.changedNanoseconds)",
        ].joined(separator: "/")
        let digest = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return try DefectSourceIdentity(
            byteCount: observation.byteCount,
            sha256: digest
        )
    }

    func updateDefectReviewTracking(
        _ frame: ScanFrame,
        identity: DefectRecipeIdentity?
    ) {
        frame.establishLibraryWorkflowBaselineIfNeeded()
        guard var state = frame.libraryWorkflowTrackingState else { return }
        var tracking = state.defectReviewTracking
        tracking.coverage = .tracked
        if let identity, let sourceIdentity = identity.sourceIdentity {
            tracking.currentRecipeRevision = identity.revision
            tracking.currentRecipeSHA256 = identity.recipeSHA256
            tracking.currentSourceIdentitySHA256 = sourceIdentity.sha256
            if let reviewedRevision = tracking.reviewedRecipeRevision,
               reviewedRevision > identity.revision {
                tracking.reviewedRecipeRevision = nil
                tracking.reviewedRecipeSHA256 = nil
                tracking.reviewedSourceIdentitySHA256 = nil
            }
        } else {
            tracking.currentRecipeRevision = nil
            tracking.currentRecipeSHA256 = nil
            tracking.currentSourceIdentitySHA256 = nil
            // source가 없는 recipe는 아직 새 원본으로 재검증되지 않았다. 같은 recipe hash가
            // 남아 있어도 이전 원본에서의 검토 완료를 승계하지 않는다.
            tracking.reviewedRecipeRevision = nil
            tracking.reviewedRecipeSHA256 = nil
            tracking.reviewedSourceIdentitySHA256 = nil
        }
        state.defectReviewTracking = tracking
        if frame.libraryWorkflowTrackingState != state {
            frame.libraryWorkflowTrackingState = state
        }
    }
}
