# 핸드오프 — 2026-08-19 H.12 ③ 측정 (값 변경 기각)

## 규칙

추측·가설 없이 재서 판단했습니다. Goal `plan.md` Deviations 에 같은 지시를 적었습니다.

## 한 일

커브가 켜진 프리뷰에서 `measure_parametric_tone_curve_bands` 가 풀해상도 float 을
내리는지 확인했습니다. 있는 `GpuMipHalve`( `downsample_for_statistics` 와 같은
`wanted_level_count` )로 측정 입력만 줄여 봤습니다.

## 실측

| | 값 |
|---|---|
| 시험 | `tone_path_runs_on_gpu` Debug 두 번 동일 |
| GPU/CPU 최대 오차 | **2.55e-04** (허용 **1e-5**) |
| 밴드 오차 | 2.48e-04 (밴드 허용 1e-3 안) |
| 판정 | **값을 바꾸므로 쓰지 않음. 되돌림.** |

되돌린 뒤 `native.gpu_accelerator` Debug 두 번 통과. 톤 오차 다시 2.09e-06.

CLI 커브 켬(고치기 전 Release, BGRA8 바이너리) `x2`:
두 번째 벽시계 129 ms, `tone_adjust` **25.59 ms**, `output` 7.56 ms,
지문 `be75746522bcf702` 두 번 같음.

`GpuAreaAverage` 는 영역 평균 하나라 백분위 격자를 대체하지 못합니다
(헤더·호출부가 그렇게 생김).

## 확인 못 한 것

- 새 커널(float 격자)이 1e-5 를 지키는지 — 만들지 않음
- 앱 슬라이더 체감
- A4 `run-app` abort

## 남은 audit 백로그 (이 goal 은 닫히지 않음)

- H.12 ③ 커브 중간 왕복 (있는 커널로는 값 불변 불가)
- A4 abort 미재현 확인
- 현상 메뉴 나머지(초기화·이전/이후·결함)
- D1 모든 보정 초기화 · D5 현상/결함 undo
- D2 비교 캡슐 · D3 줌 HUD
- D4 IR 프론트 · D6 내보내기 35 · D7 인화 8
- F 문자열 · 08 아이콘 · 09 단축키 24 · 설정 11절
- C7–C13 · E1/E2 앱 슬라이더 벽시계 · 16 앱 1GB

다음 구현 항목: 현상 메뉴 초기화(D1) — 핸들러가 생길 때까지 메뉴에 넣지 말라는
주석이 Windows XAML 에 있음. macOS `DevelopResetUndoTests` 가 정답 시험.
