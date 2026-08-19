# 핸드오프 — 2026-08-19 D3 줌 뷰포트 수식

## 왜 이것인가

07 G D2 토글 다음: 분할 캡슐은 픽셀 UI. D3 `CanvasViewportState` 가 다음
구현 가능 항목(Windows ZoomIn/Fit 히트 0).

## Swift

`CanvasViewportState.swift` · `CanvasGeometry.swift` ·
`CanvasViewportStateTests` · HUD `×1.25` / fit `reset` / actualSizeScale.

## Windows

`CanvasViewportState` · `CanvasViewportGeometry` 1:1.
HUD XAML 은 창작하지 않음.

## 시험

macOS 와 같은 입력: 1000×800 / 캔버스 500×400.
scale 40 → 12, 팬 (10000,−10000) → (266, −232), magnify 2×1.5 → 3.
Shell.UnitTests Debug x64 **2회** 1199 assertions, 실패 0.

## 남은 백로그 — goal 닫지 않음

분할 캡슐 렌더 · 줌 HUD 단추 · H.12 ③ · A4 · D4 IR · D5 슬라이더 undo ·
D6/D7 · F · 08 · 09 · C7–C13 · E1/E2
