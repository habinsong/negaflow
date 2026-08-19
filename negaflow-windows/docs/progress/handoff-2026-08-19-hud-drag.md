# 핸드오프 — 2026-08-19 D3 HUD 끌기

## 왜 이것인가

07 G 8: 줌 단추는 있음. `CanvasView+MovableHUDs` 끌기가 없어
캡슐이 모서리에 고정됨. H.12 ③ 기각, A4는 앞선 크래시.

## Swift

`CanvasHUDInteractionState` · `resolvedCanvasHUDOrigins` ·
`DragGesture(minimumDistance: 4)` · `avoidingOverlap`.

## Windows

`CanvasHudInteractionState` 신쇄. 미리보기 캔버스가 두 HUD를
`Resolve` 좌표로 놓고, 단추/입력칸이 아닌 면을 4px 이상 끌면 옮김.

## 시험

기본 (12,12)/(width-12-136,12), 누적 변위는 시작점 기준,
끝은 start만 지움, 위쪽 clamp 12, 다른 HUD와 겹치면 회피.

## 확인 못 했다

앱에서 실제로 끌어 겹침이 피하는지. 인화 HUD `(width-96, height-28)`.

## 남은 백로그 — goal 닫지 않음

Before 소스 메뉴 · 인화 HUD · H.12 ③ · A4 · D4 IR · D5 슬라이더 undo ·
D6/D7 · F · 08 · 09 · C7–C13 · E1/E2
