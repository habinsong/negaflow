# 핸드오프 — 2026-08-19 D2 비교 모드(상태 + 이전/이후 토글)

## 왜 이것인가

07 G: D1/D5 닫힌 뒤 H.12 ③은 실측 기각(값 2.55e-04). A4는 앱 미확인.
다음 구현 가능: D2 `selectCompareMode` / `toggleDevelopedShortcut`.

## Swift

`CanvasCompareMode` raw/developed/splitVertical/splitHorizontal.
`selectCompareMode` 가 `showDeveloped`·`previousCompareMode`·게이트를 바꿈.
`toggleDevelopedShortcut` 은 developed ↔ previous(기본 raw).
`canCompare` 가 거짓이면 Active 는 developed/raw 만.

## Windows

`CanvasCompareState` (신쇄). `DevelopPanelState.ToggleBeforeAfter`.
메뉴·`\` 단축키. Raw 이면 기존 `UninvertedSource`(스포이드와 같은 경로).
분할 캡슐 UI·줌 HUD 는 이번 턴에 창작하지 않음.

## 시험

`CanvasCompareStateTests` → `Select`/`ToggleDeveloped`/`ActiveMode`.
Shell.UnitTests Debug x64 **2회** 1185 assertions, 실패 0, 경고 0.

## 남은 백로그 — goal 닫지 않음

H.12 ③ · A4 · 분할 캡슐 렌더 · D3 줌 HUD · D4 IR · D5 슬라이더 undo ·
D6/D7 · F · 08 · 09 · C7–C13 · E1/E2 앱 슬라이더
