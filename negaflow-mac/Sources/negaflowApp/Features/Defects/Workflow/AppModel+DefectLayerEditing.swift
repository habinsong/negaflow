import SwiftUI
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    func beginDefectEditGesture(_ frame: ScanFrame) {
        guard !frame.defectGestureUndoPushed else { return }
        frame.defectEditUndoStack.append(frame.makeDefectEditUndoSnapshot())
        frame.defectGestureUndoPushed = true
    }

    /// 레이어 켜기/끄기(단일 결함 before/after). 끄면 그 레이어만 빠진 cleaned raw 로 재빌드된다.
    func setDefectEditEnabled(_ frame: ScanFrame, id: UUID, enabled: Bool) {
        guard let idx = frame.defectEdits.firstIndex(where: { $0.id == id }),
              frame.defectEdits[idx].enabled != enabled else { return }
        frame.defectEditUndoStack.append(frame.makeDefectEditUndoSnapshot())
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
                frame.defectGestureUndoPushed = false   // 제스처 시작 때 이미 푸시됨
            } else if changed {
                frame.defectEditUndoStack.append(frame.makeDefectEditUndoSnapshot())
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
