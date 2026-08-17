import SwiftUI
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    /// 강도 드래그 시작. 히스토리는 드래그가 끝나 값이 확정될 때 한 칸만 남기므로, 여기서는
    /// 시작 시점 상태만 들고 있는다.
    func beginDefectEditGesture(_ frame: ScanFrame) {
        guard !frame.defectGestureUndoPushed else { return }
        frame.pendingDefectHistorySnapshot = frame.makeDefectEditUndoSnapshot()
        frame.defectGestureUndoPushed = true
    }

    /// 레이어 켜기/끄기(단일 결함 before/after). 끄면 그 레이어만 빠진 cleaned raw 로 재빌드된다.
    func setDefectEditEnabled(_ frame: ScanFrame, id: UUID, enabled: Bool) {
        guard let idx = frame.defectEdits.firstIndex(where: { $0.id == id }),
              frame.defectEdits[idx].enabled != enabled else { return }
        recordDefectHistory(frame, before: frame.makeDefectEditUndoSnapshot())
        frame.defectEdits[idx].enabled = enabled
        guard let recipeSnapshot = refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: true
        ) else { return }
        invalidateCaches(frame, after: idx)
        rebuildAfterEdit(
            frame,
            changedIndex: idx,
            live: false,
            recipeSnapshot: recipeSnapshot
        )
    }

    /// 레이어 복원 강도(0~1). live=드래그 중(undo 푸시·디스크 저장·스피너 없이 즉시 반영),
    /// live=false=드래그 종료/단발 호출(최종 반영 + 디스크 저장).
    func setDefectEditStrength(_ frame: ScanFrame, id: UUID, strength: Double, live: Bool = false) {
        guard let idx = frame.defectEdits.firstIndex(where: { $0.id == id }) else { return }
        let clamped = max(0, min(1, strength))
        let changed = abs(frame.defectEdits[idx].strength - clamped) > 1e-3
        if live {
            guard changed else { return }
            beginDefectEditGesture(frame)   // 제스처 밖 live 호출도 안전하게 1회 푸시
            if !frame.defectGestureRecipeAdvanced {
                guard frame.defectRecipeRevision < UInt64.max else {
                    statusMessage = text(AppLocalizedPhrase.removingDefectsFailedStatus)
                    return
                }
                frame.defectGestureSourceIdentity = frame.defectRecipeIdentity?.sourceIdentity
                frame.defectRecipeRevision += 1
                frame.defectGestureRecipeAdvanced = true
            }
            frame.defectEdits[idx].strength = clamped
            invalidateCaches(frame, after: idx)
            scheduleLiveDefectRecipeRefresh(frame, changedIndex: idx)
            return
        } else {
            if frame.defectGestureUndoPushed {
                // 드래그 시작 시점 상태를 이제서야 히스토리 한 칸으로 굳힌다.
                if let pending = frame.pendingDefectHistorySnapshot {
                    recordDefectHistory(frame, before: pending)
                }
                frame.pendingDefectHistorySnapshot = nil
                frame.defectGestureUndoPushed = false
            } else if changed {
                recordDefectHistory(frame, before: frame.makeDefectEditUndoSnapshot())
            }
            // 최종 커밋은 값이 같아도 수행한다 — live 빌드가 저장을 건너뛰었으므로 디스크 백킹을 맞춘다.
        }
        let advanceRevision = changed && !frame.defectGestureRecipeAdvanced
        frame.defectEdits[idx].strength = clamped
        guard let recipeSnapshot = refreshDefectRecipeState(
            frame,
            advanceRevision: advanceRevision,
            persist: true
        ) else { return }
        frame.defectGestureRecipeAdvanced = false
        frame.defectGestureSourceIdentity = nil
        invalidateCaches(frame, after: idx)
        rebuildAfterEdit(
            frame,
            changedIndex: idx,
            live: false,
            recipeSnapshot: recipeSnapshot
        )
    }


}
