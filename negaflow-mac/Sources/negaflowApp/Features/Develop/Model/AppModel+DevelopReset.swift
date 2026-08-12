import Chromabase
import Foundation

/// "모든 보정 초기화" 직전의 현상 설정. 되돌리기용 최소 스냅샷(값 타입 params + 룩 프리셋)이며,
/// 기하(imageTransform)·베이스 설정은 초기화 대상이 아니라 담지 않는다.
struct DevelopAdjustmentSnapshot {
    let params: DevelopParameters
    let preset: LookPreset?

    @MainActor
    init(frame: ScanFrame) {
        params = frame.params
        preset = frame.preset
    }

    @MainActor
    func apply(to frame: ScanFrame) {
        frame.preset = preset
        frame.params = params
    }
}

extension AppModel {
    /// 슬라이더 수십 개를 한 번에 되돌리는 파괴적 동작이므로 ⌘Z 로 취소할 수 있어야 한다.
    /// 취소가 없으면 사용자는 초기화 전 값을 하나씩 기억해 복구해야 한다.
    func resetAllDevelopAdjustments(_ frame: ScanFrame, neutralPreset: LookPreset?) {
        guard ownsFrame(frame) else { return }
        let previous = DevelopAdjustmentSnapshot(frame: frame)
        DevelopInspectorResetter.resetAllAdjustments(frame: frame, neutralPreset: neutralPreset)
        requestDevelop(frame)
        registerDevelopAdjustmentUndo(previous, on: frame)
    }

    /// 되돌리기/다시 실행 공통 경로 — 되돌리기 직전 상태를 다시 등록해 ⌘⇧Z 도 성립한다.
    func restoreDevelopAdjustments(_ snapshot: DevelopAdjustmentSnapshot, on frame: ScanFrame) {
        guard ownsFrame(frame) else { return }
        let previous = DevelopAdjustmentSnapshot(frame: frame)
        snapshot.apply(to: frame)
        requestDevelop(frame)
        registerDevelopAdjustmentUndo(previous, on: frame)
    }

    private func registerDevelopAdjustmentUndo(
        _ snapshot: DevelopAdjustmentSnapshot,
        on frame: ScanFrame
    ) {
        guard let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.restoreDevelopAdjustments(snapshot, on: frame)
        }
        undoManager.setActionName(text(.commandResetAdjustments))
    }
}
