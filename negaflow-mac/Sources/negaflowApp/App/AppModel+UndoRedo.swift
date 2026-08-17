import AppKit

// MARK: - 앱 전체 되돌리기 / 다시 실행
//
// negaflow 의 모든 되돌릴 수 있는 조작 — 라이브러리에서 제거, 컬렉션 편집, 현상 초기화, 로컬
// 조정, GrainMend 레이어 — 은 창의 UndoManager 한 곳에 등록된다. 그래서 ⌘Z 는 도구나 화면과
// 무관하게 "마지막에 한 일"을 되돌리고, ⇧⌘Z 는 그것을 다시 실행한다.
//
// 예전에는 캔버스가 ⌘Z 를 가로채 무조건 현재 사진의 GrainMend 를 되돌렸다. 사진을 지운 직후
// ⌘Z 를 누르면 지운 사진이 아니라 **다음 사진의 GrainMend 기록**이 사라진 것이 그 때문이다.
extension AppModel {
    var canUndo: Bool { catalogUndoManager?.canUndo == true }
    var canRedo: Bool { catalogUndoManager?.canRedo == true }

    func performUndo() {
        // 텍스트 입력 중에는 그 필드의 편집 기록이 먼저다(이름 바꾸기 도중의 ⌘Z).
        if let fieldEditor = focusedTextUndoManager(), fieldEditor.canUndo {
            fieldEditor.undo()
            return
        }
        // canUndo 로 먼저 거르지 않는다 — 방금 등록한 조작은 아직 이번 이벤트의 묶음이 열려 있어
        // canUndo 가 false 다. undo() 가 그 묶음을 닫고 되돌린다. 되돌릴 것이 없으면 아무 일도 없다.
        catalogUndoManager?.undo()
    }

    func performRedo() {
        if let fieldEditor = focusedTextUndoManager(), fieldEditor.canRedo {
            fieldEditor.redo()
            return
        }
        guard let undoManager = catalogUndoManager, undoManager.canRedo else { return }
        undoManager.redo()
    }

    /// 지금 키 입력을 받는 텍스트 편집기의 UndoManager. 텍스트 필드가 아니면 nil.
    /// (NSApp 은 앱 밖에서 실행될 때 없을 수 있어 먼저 확인한다.)
    private func focusedTextUndoManager() -> UndoManager? {
        guard let application: NSApplication = NSApp,
              let responder = application.keyWindow?.firstResponder as? NSText else { return nil }
        let manager = responder.undoManager
        // 창 자체의 UndoManager 를 돌려주는 응답자도 있다 — 그건 앱 히스토리와 같은 스택이라
        // 여기서 가로채면 두 번 처리된다.
        return manager === catalogUndoManager ? nil : manager
    }
}
