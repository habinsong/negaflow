import SwiftUI
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    /// 레이어 휴지통. 사용자가 명시적으로 지우는 유일한 경로이므로 IR 도 지울 수 있고,
    /// 되돌리면 그 IR 이 정확히 돌아온다(`.exact`).
    func removeDefectEdit(_ frame: ScanFrame, id: UUID) {
        guard let idx = frame.defectEdits.firstIndex(where: { $0.id == id }) else { return }
        recordDefectHistory(frame, before: frame.makeDefectEditUndoSnapshot(), mode: .exact)
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

    /// 사용자가 적용한 결함 제거를 전부 초기화한다(브러시·가이드·복제). undo 스택에 직전 상태를 남긴다.
    ///
    /// **적외선 레이어는 남긴다.** IR 은 사람이 그린 기록이 아니라 스캔과 함께 측정된 결과이고,
    /// 초기화 버튼은 "내가 한 보정을 되돌린다"는 뜻이다. 여기서 같이 지우면 세션 안에서는
    /// 다시 만들 방법이 없어(한 세션 한 번 계약) IR 먼지 제거가 통째로 불능이 된다.
    func clearAllDefects(_ frame: ScanFrame) {
        let removedAny = removeDefectEdits(frame, matching: { !$0.isInfrared })
        guard removedAny else { return }
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

    @discardableResult
    private func removeDefectEdits(
        _ frame: ScanFrame,
        matching shouldRemove: (DefectEditItem) -> Bool
    ) -> Bool {
        let retained = frame.defectEdits.filter { !shouldRemove($0) }
        guard retained.count != frame.defectEdits.count else { return false }
        recordDefectHistory(frame, before: frame.makeDefectEditUndoSnapshot())
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
        return true
    }

    /// 결함 편집 하나를 앱 공용 히스토리에 남긴다. 반드시 **바꾸기 직전** 스냅샷을 넘긴다.
    ///
    /// 카탈로그 편집과 같은 UndoManager 를 쓰므로 ⌘Z 는 언제나 "마지막에 한 일"을 되돌린다 —
    /// 사진을 지운 뒤 ⌘Z 가 엉뚱하게 다음 사진의 GrainMend 기록을 지우던 원인이 이 분리였다.
    func recordDefectHistory(
        _ frame: ScanFrame,
        before snapshot: [DefectEditItem],
        mode: DefectHistorySnapshot.Mode = .preservingInfrared
    ) {
        frame.defectHistoryDepth += 1
        registerDefectHistoryUndo(frame, snapshot: snapshot, mode: mode)
    }

    private func registerDefectHistoryUndo(
        _ frame: ScanFrame,
        snapshot: [DefectEditItem],
        mode: DefectHistorySnapshot.Mode
    ) {
        guard let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.applyDefectHistorySnapshot(snapshot, to: frame, mode: mode)
        }
    }

    /// 히스토리 한 칸을 적용한다. 되돌리기 중 등록한 것은 UndoManager 가 다시 실행으로 잡아 주므로
    /// ⌘Z 와 ⇧⌘Z 가 같은 코드로 왕복한다.
    func applyDefectHistorySnapshot(
        _ snapshot: [DefectEditItem],
        to frame: ScanFrame,
        mode: DefectHistorySnapshot.Mode
    ) {
        guard frames.contains(where: { $0 === frame }) else { return }
        let current = frame.makeDefectEditUndoSnapshot()
        let restored = DefectHistorySnapshot.resolve(
            snapshot,
            current: frame.defectEdits,
            mode: mode
        )
        frame.defectHistoryDepth = catalogUndoManager?.isRedoing == true
            ? frame.defectHistoryDepth + 1
            : max(0, frame.defectHistoryDepth - 1)
        registerDefectHistoryUndo(frame, snapshot: current, mode: mode)

        frame.defectEdits = restored
        let recipeSnapshot = refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: true
        )
        frame.pendingDefectHistorySnapshot = nil
        frame.defectGestureUndoPushed = false
        frame.defectGestureRecipeAdvanced = false
        if let id = frame.defectMaskPreviewID, !restored.contains(where: { $0.id == id }) {
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
