# 핸드오프 — 2026-08-19 D2 Before 소스 메뉴

## 왜 이것인가

07 G 8: 분할은 무보정만 그렸다. macOS `CanvasCompareLabels` 의
MAIN / 무보정 / 원본 / 다른 사진이 없었다.

## Swift

`selectedBeforeID` · `primaryBeforeOptions` · `frame:` prefix.
라벨 중심 `(minX+60, minY+48)`, after 세로 `(maxX-38, minY+48)`.
`beforeImage` 스위치.

## Windows

`CanvasCompareBeforePolicy` + `SelectBefore` + `CanvasCompareLabels`.
요청: unedited=`Neutralize`, raw=uninverted, main=타깃 MAIN(이미 MAIN 이면
after 화소 복사), `frame:`=그 프레임 현상.

## 시험

CanonicalId, 위치, BeforeSnapshot(톤/타깃/다른 장), SelectBefore.

## 확인 못 했다

앱에서 메뉴를 눌러 Before 그림이 바뀌는지.

## 남은 백로그 — goal 닫지 않음

인화 HUD · H.12 ③ · A4 · D4 IR · D5 슬라이더 undo · D6/D7 · F · 08 · 09 ·
C7–C13 · E1/E2
