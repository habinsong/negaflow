# 핸드오프 — 2026-08-19 D1 모든 보정 초기화 · D5 그 undo

## Swift

`DevelopInspectorResetter.resetAllAdjustments` · `AppModel.resetAllDevelopAdjustments` ·
`registerDevelopAdjustmentUndo`. 베이스·기하는 유지. 메뉴
`AppWorkflowMenuCommands` `commandResetAdjustments`.

## Windows

- `DevelopInspectorResetter.ResetAllAdjustments` → `LibraryFrameEdit`
- `DevelopPanelState.ResetAllAdjustments` + `LibraryHostService.EditUndoable`
- 현상 메뉴 항목 + `WorkflowShortcutAction.ResetAdjustments` (Ctrl+Shift+R)
- 이전/이후·결함 메뉴는 핸들러가 없어 **넣지 않음**(가짜 UI 금지)

## 시험

`DevelopInspectorResetterTests` 신쇄 `ResetAllAdjustments`.
Shell.UnitTests Debug x64 **두 번** 1165 assertions, 실패 0, 경고 0.
(HEAD 바닥 1140). Catalog 731/0.

## 확인 못 한 것

- A4 `run-app` 현상 전환 abort
- 앱에서 메뉴를 눌러 초기화·Ctrl+Z 를 눈으로 봄
- D2 비교 캡슐 · D3 줌 · D4 IR 메뉴 · D5 슬라이더 단위 undo(카탈로그 스택만)

## 남은 audit 백로그 — 이 goal 은 닫히지 않음

H.12 ③(있는 커널 기각) · A4 · 현상 이전/이후·결함 메뉴 · D2/D3/D4 ·
D5 슬라이더 undo · D6 내보내기 35 · D7 인화 8 · F · 08 아이콘 · 09 단축키/설정
· C7–C13 · E1/E2 앱 슬라이더 벽시계 · 16 앱 1GB
