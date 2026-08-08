import SwiftUI
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    func removeDefectEdit(_ frame: ScanFrame, id: UUID) {
        guard let idx = frame.defectEdits.firstIndex(where: { $0.id == id }) else { return }
        frame.defectEditUndoStack.append(frame.makeDefectEditUndoSnapshot())
        let wasLast = idx == frame.defectEdits.count - 1
        frame.defectEdits.remove(at: idx)
        let recipeSnapshot = refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: true
        )
        if frame.defectMaskPreviewID == id { frame.defectMaskPreviewID = nil }
        invalidateCaches(frame, after: idx - 1)
        if frame.defectEdits.isEmpty {
            invalidatePreviousBase(frame)
            rebuildCleanedRaw(frame, recipeSnapshot: nil)
        } else if wasLast, let previous = frame.cleanedRawPreviousImage,
           frame.cleanedRawPreviousEditCount == frame.defectEdits.count {
            // 마지막 레이어 삭제 = 직전 베이스가 곧 결과. 베이스-이전은 모르므로 즉시 경로는 소진된다.
            let base = previous
            let baseIdentity = frame.cleanedRawPreviousIdentity
            invalidatePreviousBase(frame)
            guard let recipeSnapshot else { return }
            runCleanedRawBuild(frame, editsToApply: [], totalEditCount: frame.defectEdits.count,
                               preloadedBase: base, baseDiskURL: nil,
                               baseIdentity: baseIdentity,
                               fromOriginal: false, recipeSnapshot: recipeSnapshot)
        } else {
            invalidatePreviousBase(frame)
            rebuildCleanedRaw(frame, recipeSnapshot: recipeSnapshot)
        }
    }

    /// 적용된 결함 제거를 전부 초기화한다(브러시·가이드 모두). undo 스택에 직전 상태를 남긴다.
    func clearAllDefects(_ frame: ScanFrame) {
        guard !frame.defectEdits.isEmpty else { return }
        frame.defectEditUndoStack.append(frame.makeDefectEditUndoSnapshot())
        frame.defectEdits = []
        _ = refreshDefectRecipeState(frame, advanceRevision: true, persist: true)
        frame.defectMaskPreviewID = nil
        invalidatePreviousBase(frame)
        rebuildCleanedRaw(frame)   // edits가 비면 cleaned raw 폐기 후 원본으로 재현상
        statusMessage = text(AppLocalizedPhrase.defectsClearedStatus)
    }

    /// 브러시 결함 제거 레이어만 제거한다. 가이드/적외선 레이어는 그대로 유지한다.
    func resetBrushDefect(_ frame: ScanFrame) {
        removeDefectEdits(frame, matching: { item in
            if case .brush = item.edit { return true }
            return false
        })
    }

    /// 가이드 영역 결함 제거 레이어와 진행 중인 영역 세션만 초기화한다. 브러시/적외선 레이어는 유지한다.
    func resetRegionDefect(_ frame: ScanFrame) {
        cancelRegionDefect(frame)
        removeDefectEdits(frame, matching: { item in
            if case .region = item.edit { return true }
            return false
        })
    }

    /// 복제 도장 레이어만 제거한다. 브러시/가이드/적외선 레이어는 그대로 유지한다.
    func resetCloneStampDefect(_ frame: ScanFrame) {
        removeDefectEdits(frame, matching: { item in
            if case .clone = item.edit { return true }
            return false
        })
    }

    private func removeDefectEdits(_ frame: ScanFrame, matching shouldRemove: (DefectEditItem) -> Bool) {
        let retained = frame.defectEdits.filter { !shouldRemove($0) }
        guard retained.count != frame.defectEdits.count else { return }
        frame.defectEditUndoStack.append(frame.makeDefectEditUndoSnapshot())
        frame.defectEdits = retained
        let recipeSnapshot = refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: true
        )
        if let id = frame.defectMaskPreviewID,
           !retained.contains(where: { $0.id == id }) {
            frame.defectMaskPreviewID = nil
        }
        invalidatePreviousBase(frame)
        rebuildCleanedRaw(frame, recipeSnapshot: recipeSnapshot)
    }

    /// ⌘Z: 마지막 "결함 제거" 적용을 취소(다단계). 브러시·가이드 어느 것이든 마지막 편집을 되돌린다.
    /// Undo 스냅샷은 무거운 런타임 패치 캐시를 제외하므로 필요할 때 원본+명령에서 재빌드한다.
    func undoDefects(_ frame: ScanFrame) {
        guard let previous = frame.defectEditUndoStack.popLast() else { return }
        frame.defectEdits = previous
        let recipeSnapshot = refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: true
        )
        frame.defectGestureUndoPushed = false
        frame.defectGestureRecipeAdvanced = false
        if let id = frame.defectMaskPreviewID, !previous.contains(where: { $0.id == id }) {
            frame.defectMaskPreviewID = nil   // 사라진 레이어의 마스크 표시 해제
        }
        invalidatePreviousBase(frame)
        rebuildCleanedRaw(frame, recipeSnapshot: recipeSnapshot)
    }

    /// 변경 레이어가 마지막이고 직전 베이스가 살아 있으면 즉시 경로(베이스+캐시 패치), 아니면 전체 재빌드.
    func rebuildAfterEdit(
        _ frame: ScanFrame,
        changedIndex idx: Int,
        live: Bool,
        recipeSnapshot: DefectRecipeSnapshot
    ) {
        if idx == frame.defectEdits.count - 1,
           let previous = frame.cleanedRawPreviousImage,
           frame.cleanedRawPreviousEditCount == idx {
            runCleanedRawBuild(frame, editsToApply: [frame.defectEdits[idx]],
                               totalEditCount: frame.defectEdits.count,
                               preloadedBase: previous, baseDiskURL: nil,
                               baseIdentity: frame.cleanedRawPreviousIdentity,
                               fromOriginal: false,
                               recipeSnapshot: recipeSnapshot,
                               persist: !live, quiet: live)
        } else {
            invalidatePreviousBase(frame)
            rebuildCleanedRaw(
                frame,
                recipeSnapshot: recipeSnapshot,
                persist: !live,
                quiet: live
            )
        }
    }

    /// idx 이후 레이어들의 패치 캐시를 무효화한다 — 캐시는 "앞선 레이어들이 적용된 베이스" 기준이라
    /// 앞이 바뀌면 뒤는 다시 계산해야 한다(idx 자신의 캐시는 강도와 무관하니 유지).
    func invalidateCaches(_ frame: ScanFrame, after idx: Int) {
        guard idx + 1 < frame.defectEdits.count else { return }
        for i in (idx + 1)..<frame.defectEdits.count {
            frame.defectEdits[i].cachedPatches = nil
        }
    }

    func invalidatePreviousBase(_ frame: ScanFrame) {
        frame.cleanedRawPreviousImage = nil
        frame.cleanedRawPreviousEditCount = -1
        frame.cleanedRawPreviousIdentity = nil
    }

    /// defectEdits를 원본 raw에 순차 적용 → cleaned raw(메모리 + 디스크 백킹) 갱신 → 재현상.
    /// edits가 비면 cleaned raw를 버리고 원본 raw로 재현상한다. (undo/clear/레이스 시 안전 경로)

}
