import Chromabase
import Combine
import Foundation

// MARK: - 인화 작업공간 되돌리기 / 다시 실행
//
// 인화 설정은 컨트롤마다 저장소 프로퍼티가 따로다. 되돌리기를 컨트롤마다 달면 새 컨트롤이
// 생길 때마다 빠지므로, 값이 바뀌기 직전 상태를 저장소 변경 신호에서 통째로 잡아 한 칸으로 남긴다.
extension AppModel {
    /// 인화 화면에 있는 동안의 설정 변경만 히스토리에 남긴다. 앱 시작 시의 기본값 정규화나
    /// 다른 화면에서 일어나는 파생 갱신은 사용자가 한 조작이 아니다.
    func observePrintWorkspaceSettingsHistory() {
        printWorkspaceSettingsStore.objectWillChange
            .sink { [weak self] _ in
                guard let self, self.activeWorkspaceModule == .print else { return }
                // objectWillChange 는 대입 **직전**에 온다 — 지금 값이 곧 되돌릴 상태다.
                let before = self.printWorkspaceSettingsStore.snapshot
                Task { @MainActor [weak self] in
                    self?.recordPrintWorkspaceSettingsEdit(before)
                }
            }
            .store(in: &printSettingsHistoryCancellables)
    }

    private func recordPrintWorkspaceSettingsEdit(_ before: PrintWorkspaceSettingsSnapshot) {
        guard !isApplyingPrintSettingsHistory else { return }
        guard printWorkspaceSettingsStore.snapshot != before else { return }
        // 여백·크기 슬라이더를 끄는 동안은 한 칸으로 묶는다.
        guard printSettingsCoalesceTask == nil else {
            schedulePrintSettingsCoalesceEnd()
            return
        }
        registerPrintWorkspaceSettingsUndo(before)
        schedulePrintSettingsCoalesceEnd()
    }

    private func schedulePrintSettingsCoalesceEnd() {
        printSettingsCoalesceTask?.cancel()
        printSettingsCoalesceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(AppModel.frameEditCoalesceInterval))
            guard !Task.isCancelled else { return }
            self?.printSettingsCoalesceTask = nil
        }
    }

    private func registerPrintWorkspaceSettingsUndo(_ snapshot: PrintWorkspaceSettingsSnapshot) {
        guard let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.applyPrintWorkspaceSettingsSnapshot(snapshot)
        }
    }

    func applyPrintWorkspaceSettingsSnapshot(_ snapshot: PrintWorkspaceSettingsSnapshot) {
        let current = printWorkspaceSettingsStore.snapshot
        guard current != snapshot else { return }
        registerPrintWorkspaceSettingsUndo(current)
        isApplyingPrintSettingsHistory = true
        printSettingsCoalesceTask?.cancel()
        printSettingsCoalesceTask = nil
        printWorkspaceSettingsStore.restore(snapshot)
        isApplyingPrintSettingsHistory = false
    }
}
