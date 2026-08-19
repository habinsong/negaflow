# 핸드오프 — 2026-08-19 D4 IR 프론트

## 왜 이것인가

07 G 9: GrainMend 카드에 IR 단추가 없다고 적혀 있음. Swift 를 열면
IR 은 5번째 알약이 아니라 `InfraredImportPairing` + 선택 시
`runInfraredCleanIfNeeded`. 엔진 `RunFiles` 와 스캔 publish 는 이미 있음.

## Swift

`InfraredFilmCompatibility` 색소/은.
`InfraredImportPairing` (`foo.tiff.ir.tiff` / `_ir` / `-infrared`).
`ShouldRun`: IR 경로, 미시도, IR 레이어 없음, 컬러만.

## Windows

같은 정책 + `FrameImport.Plan` 이 짝 IR 을 두 번째 장으로 넣지 않고
`infraredScanPath` 를 씀. `SetSelection` / `DevelopPanelState.Select` 가
`TryInfraredCleanIfNeeded` → `RunFiles`.

## 시험

색소/은, 게이트, core name, `a.tif`+`a_ir.tif` → row 1 + IR 경로.

## 확인 못 했다

앱에서 IR 쌍을 가져와 선택하면 레이어가 생기는지. 기존 장에 IR 만 붙이기.

## 남은 백로그 — goal 닫지 않음

기존 장 attach · stray IR 접기 · D6/D7 · 결함 undo · 인화 HUD ·
H.12 ③ · A4 · F · 08 · 09 · C7–C13 · E1/E2
