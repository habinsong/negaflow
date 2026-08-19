# 핸드오프 — 2026-08-19 D3 CanvasToolHUD

## 왜 이것인가

07 G 8: 뷰포트 수식은 이미 있음. HUD 단추가 없어 스케일을 바꿀 입력이 없었다.
H.12 ③은 실측 기각. A4는 앱 미확인. 분할 캡슐은 픽셀 UI.

## Swift

`CanvasToolHUD.swift` · `CanvasView+MovableHUDs` · `CanvasHUDPlacement`
· `CanvasBackground.hudContentColor` / `hudSurfaceColor`.
`−` / `+` ×1.25, 퍼센트 5…1600 후 `setScale(percent/100)`(다시 0.2…12),
맞춤 `reset`, 원본 크기 `actualSizeScale`.

## Windows

`CanvasToolHudPolicy` · `CanvasHudPlacement` · `CanvasHudChrome`
· `CanvasToolHud` XAML. `DevelopPanelState.Viewport` 를 미리보기 사각형
(`PreviewFrame.TryFromViewport` = `FittedImageFrame`)에 붙임.
메뉴 없이 HUD 단추가 `ZoomBy` / `Reset` / `SetScale` 을 부름.

## 시험

`CanvasToolHudTests` — 수치, 퍼센트 파싱, 신쇄 `TryApplyZoomPercentText`,
크롬 흰 값, 기본 위치 (12,12) / (width-12-136, 12).

## 확인 못 했다

앱에서 HUD를 눌러 사진이 커지는지, 일곱 축 화면 대조, HUD 끌기,
인화 캔버스 HUD 위치 `(width-96, height-28)`.

## 남은 백로그 — goal 닫지 않음

분할 캡슐 렌더 · HUD 끌기 · H.12 ③ · A4 · D4 IR · D5 슬라이더 undo ·
D6/D7 · F · 08 · 09 · C7–C13 · E1/E2
