import Foundation

private struct DefectRecipeRelinkPlan {
    let frame: ScanFrame
    let revision: UInt64
    let identity: DefectRecipeIdentity?
}

extension AppModel {
    /// 원본 위치를 바꾸기 전에 기존 source binding을 끊는다. 동일 바이트 재연결도
    /// 새 경로 fixity를 다시 확인하기 전까지 이전 cleaned-raw 증명을 재사용하지 않는다.
    @discardableResult
    func invalidateDefectRecipeSourceBindingForRelink(_ frame: ScanFrame) -> Bool {
        invalidateDefectRecipeSourceBindingsForRelink([frame])
    }

    /// 한 source family의 모든 recipe invalidation을 먼저 계산한 뒤 일괄 반영한다.
    /// 기록은 세션 메모리에만 있으므로(종료 시 이미지에 굽고 폐기) 디스크 반영은 없다.
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
                    identity: nil
                )
            }
            guard frame.defectRecipeRevision < UInt64.max else {
                throw DefectRecipeValidationError.invalidRevision
            }
            return DefectRecipeRelinkPlan(
                frame: frame,
                revision: frame.defectRecipeRevision + 1,
                identity: nil
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
            identity: snapshot.identity
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
            if let identity = plan.identity {
                installDefectRecipeIdentity(identity, on: plan.frame)
            } else {
                plan.frame.defectRecipeIdentity = nil
                updateDefectReviewTracking(plan.frame, identity: nil)
            }
        }
    }
}
