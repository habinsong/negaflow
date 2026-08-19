# 핸드오프 — 2026-08-19 D5 슬라이더 undo

## 왜 이것인가

07 G 6: 초기화만 CaptureUndo. 슬라이더 `host.Edit` 는 undo 없음.
macOS 는 재현상 길목에서 0.7초로 한 칸.

## Swift

`frameEditCoalesceInterval = 0.7`
`recordFrameEditIfChanged` — 제스처 첫 변경만 undo, 끄는 동안은 기준만 연장.

## Windows

`FrameEditHistory.ConsumeCapture` + `LibraryHostService.Edit`/`EditRoute`.
`EditUndoable`(초기화)는 제스처를 지우고 따로 남김. Undo/Redo 도 제스처 종료.

## 시험

0.2s/0.6s 같은 제스처, 1.4s 새 제스처.
노출 0→1→2 후 Undo 한 번 → 0 (중간 1 아님).

## 확인 못 했다

앱에서 슬라이더를 끈 뒤 Ctrl+Z. 결함 undo.

## 남은 백로그 — goal 닫지 않음

D4 IR · 결함 undo · D6/D7 · 인화 HUD · H.12 ③ · A4 · F · 08 · 09 ·
C7–C13 · E1/E2
