# 핸드오프 — 2026-08-19 D2 비교 캡슐 + 분할 클립

## 왜 이것인가

07 G 8: 비교 *상태*는 있음. 캡슐·분할 그림이 없어 Select(Split) 이 화면에
안 보였음. HUD 끌기보다 사용자에게 먼저 보이는 D2 표면.

## Swift

`CanvasCompareToggle` 순서 원본·현상본·좌우·상하.
`CanvasCompareDivider` fraction 0.02…0.98, grab 18, handle 4×34.
`splitVerticalImage`: after 전체, before 왼쪽/위 fraction clip.
무보정 Before = `neutralPreviewImage` (`ExportFlatMaster.Neutralize`).

## Windows

`CanvasCompareHud` + `CanvasCompareDividerState` + Before `Image` clip.
분할 진입 시 Neutralize 1회. 슬라이더 중 after 만 갱신.

## 시험

`CanvasCompareHudTests` — 수치, clamp, drag grab, BeforeClip, Neutralize.

## 확인 못 했다

앱에서 캡슐을 눌러 분할이 그려지는지, 일곱 축, Before 소스 메뉴.

## 남은 백로그 — goal 닫지 않음

HUD 끌기 · Before 소스 메뉴 · H.12 ③ · A4 · D4 IR · D5 슬라이더 undo ·
D6/D7 · F · 08 · 09 · C7–C13 · E1/E2
