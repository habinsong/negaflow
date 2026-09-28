import Foundation

private struct DefectRecipeRelinkPlan {
    let frame: ScanFrame
    let revision: UInt64
    let snapshot: DefectRecipeSnapshot?
}

extension AppModel {
    /// 원본 위치를 바꾸기 전에 기존 source binding을 끊는다. 동일 바이트 재연결도
    /// 새 경로 fixity를 다시 확인하기 전까지 이전 cleaned-raw 증명을 재사용하지 않는다.
    @discardableResult
    func invalidateDefectRecipeSourceBindingForRelink(_ frame: ScanFrame) -> Bool {
        invalidateDefectRecipeSourceBindingsForRelink([frame])
    }

    /// 한 source family의 모든 recipe invalidation을 먼저 계산한 뒤 일괄 반영한다.
    /// 새 세대는 디스크 기록에도 남긴다. 카탈로그 저장은 메모리 recipe 와 디스크 기록이 같은
    /// 세대인지 확인하므로, 재빌드 없이 끝나는 재연결(원본 이동·폴더 감시)도 여기서 저장해야 한다.
    @discardableResult
    func invalidateDefectRecipeSourceBindingsForRelink(_ family: [ScanFrame]) -> Bool {
        do {
            let plans = try family.map(makeDefectRecipeRelinkPlan)
            applyDefectRecipeRelinkPlans(plans)
            invalidateLibraryQueryContext()
            scheduleLibrarySave()
            return true
        } catch {
            statusMessage = text(AppLocalizedPhrase.removingDefectsFailedStatus)
            return false
        }
    }

    private func makeDefectRecipeRelinkPlan(
        _ frame: ScanFrame
    ) throws -> DefectRecipeRelinkPlan {
        if frame.defectEdits.isEmpty {
            guard frame.defectRecipeIdentity != nil || frame.defectRecipeRevision > 0 else {
                return DefectRecipeRelinkPlan(
                    frame: frame,
                    revision: frame.defectRecipeRevision,
                    snapshot: nil
                )
            }
            guard frame.defectRecipeRevision < UInt64.max else {
                throw DefectRecipeValidationError.invalidRevision
            }
            return DefectRecipeRelinkPlan(
                frame: frame,
                revision: frame.defectRecipeRevision + 1,
                snapshot: nil
            )
        }

        guard frame.defectRecipeRevision < UInt64.max else {
            throw DefectRecipeValidationError.invalidRevision
        }
        let snapshot = try DefectRecipeSnapshot(
            frameID: frame.id,
            revision: frame.defectRecipeRevision + 1,
            sourceIdentity: nil,
            items: frame.defectEdits.map { DefectEditItemRecord(item: $0) }
        )
        return DefectRecipeRelinkPlan(
            frame: frame,
            revision: snapshot.identity.revision,
            snapshot: snapshot
        )
    }

    private func applyDefectRecipeRelinkPlans(_ plans: [DefectRecipeRelinkPlan]) {
        for plan in plans {
            cancelPendingDefectRecipeRefresh(plan.frame)
            plan.frame.defectGestureRecipeAdvanced = false
            plan.frame.defectGestureUndoPushed = false
            plan.frame.defectGestureSourceIdentity = nil
        }
        for plan in plans {
            plan.frame.defectRecipeRevision = plan.revision
            if let snapshot = plan.snapshot {
                installDefectRecipeIdentity(snapshot.identity, on: plan.frame)
                persistDefectRecipe(snapshot, for: plan.frame)
            } else {
                plan.frame.defectRecipeIdentity = nil
                updateDefectReviewTracking(plan.frame, identity: nil)
            }
        }
    }
}
