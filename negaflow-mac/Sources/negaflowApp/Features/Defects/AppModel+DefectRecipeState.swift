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

    /// 편집 recipe는 앱 소유 sidecar에 직렬·원자 저장합니다. 원본 픽셀은 보존합니다.
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
        guard !frame.defectEditsNeedRestore else { return nil }
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
            if persist {
                DefectSidecarFile.removeAsync(for: frame.id, atRevision: frame.defectRecipeRevision,
                                             in: libraryDefectDirectoryURL)
            }
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
        if persist { persistDefectRecipe(snapshot, for: frame) }
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

    /// 파일시스템 관찰값으로 캐시의 원본 세대를 확인합니다. 복구·재연결로 inode 등이
    /// 바뀌면 recipe를 보존하고 캐시만 새 원본에서 재생성합니다.
    ///
    /// ctime 은 넣지 않는다. 기본 저장소인 iCloud 의 업로드·태그·백업이 확장 속성만 바꿔도
    /// ctime 이 바뀌어, 내용이 같은 원본을 바뀐 것으로 보고 결함 제거를 처음부터 다시 만들고
    /// 검토 표시까지 지웠다. `bound` 는 recipe 에 이미 묶인 값이다 — 예전(ctime 포함) 형식으로
    /// 묶였어도 그때와 같은 상태면 그 값을 돌려줘, 형식이 바뀌었다는 이유만으로 다시 만들지 않는다.
    nonisolated static func defectSourceIdentity(
        for url: URL,
        bound: DefectSourceIdentity? = nil
    ) throws -> DefectSourceIdentity {
        let observation = try CaptureFileObservation.capture(for: url)
        var components = [
            "\(observation.device)", "\(observation.inode)", "\(observation.byteCount)",
            "\(observation.modifiedSeconds).\(observation.modifiedNanoseconds)",
        ]
        let current = try sourceIdentity(components, byteCount: observation.byteCount)
        guard let bound, bound != current else { return current }
        components.append("\(observation.changedSeconds).\(observation.changedNanoseconds)")
        let legacy = try sourceIdentity(components, byteCount: observation.byteCount)
        return bound == legacy ? bound : current
    }

    private nonisolated static func sourceIdentity(
        _ components: [String],
        byteCount: UInt64
    ) throws -> DefectSourceIdentity {
        let digest = SHA256.hash(data: Data(components.joined(separator: "/").utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return try DefectSourceIdentity(byteCount: byteCount, sha256: digest)
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
