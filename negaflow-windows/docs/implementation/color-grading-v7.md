# Color Grading recipe v7 vertical slice

2026-08-09에 macOS `ColorGradingSection`의 세 tonal range recipe를 Windows의 Catalog, Shell,
versioned C ABI, native CPU pipeline, WinUI Inspector까지 하나의 요청으로 연결했습니다.

- `params.colorGrading`은 `shadows`·`midtones`·`highlights` 각각의
  `hue`(0…360), `saturation`(0…1), `luminance`(-1…1)와 `blending`(0…1),
  `balance`(-1…1)를 저장합니다. 누락된 recipe는 macOS 기본값과 같이 identity
  (`blending=0.5`)로 읽으며, 비유한값과 범위 밖 값은 fail-closed입니다.
- ABI 0.13 `nf_develop_export_request_v7`/`nf_develop_preview_v7`는 고정된 v6
  prefix 뒤에 11개 float를 append합니다. v1~v6 구조체와 entry point는 변경하지
  않았습니다. native request validation은 잘못된 값에 `invalid_color_grading`을
  반환합니다.
- `ColorGradingEditor`는 Shadows/Midtones/Highlights selector, 150 DIP hue/saturation
  wheel, luminance/blending/balance slider를 제공합니다. 포인터 캡처와 화살표의
  0.01 saturation·1° hue nudge, Shift의 10배 nudge를 지원하고, 변경은 Catalog를
  거쳐 같은 preview/export recipe에 반영합니다.

## 검증

- x64 Debug native CTest: 30/30 통과.
- x64 Debug Catalog: 338 assertions 통과.
- x64 Debug Shell: 276 assertions 통과.
- x64 Debug interop ABI 0.13: 64 assertions 통과.
- x64 Release CI gate: native CTest 30/30, Catalog 338 assertions, Shell 276 assertions,
  managed build 경고·오류 0.
- ARM64 교차 빌드: native와 managed 전체 target이 경고·오류 없이 완료했습니다. 실제 ARM64
  실행은 하지 않았습니다.
- provenance: `verify-provenance.py` files=1787, text=1744, binary=43,
  declared_resources=29, reachable_commits=140 통과.

Native ABI test는 v7 구조체의 크기·null request와 잘못된 Color Grading 값을 검증하며,
Catalog test는 identity 기본값과 JSON write/read round-trip을 확인합니다.

## 남은 증거

이 환경에서 WinUI 자동화 세션을 시작할 수 없어 rendered screenshot/UIA, compact/high
contrast, 실제 ARM64 runtime은 아직 검증하지 못했습니다. macOS screenshot/golden과 Windows
pixel 비교 역시 없습니다.
