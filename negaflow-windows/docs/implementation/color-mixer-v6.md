# Color Mixer recipe v6 vertical slice

2026-08-09 기준 macOS `ColorMixerSection`의 HSL 8밴드 recipe를 Windows Catalog, Shell,
versioned C ABI, native CPU pipeline, WinUI Inspector 하나의 request로 연결합니다.

- `params.colorMixer.{hue,saturation,luminance}`를 macOS처럼 최대 8개 배열로 읽고, 부족한 값은
  0으로 채웁니다. write는 항상 각 8개를 canonical하게 기록하며, 범위 밖·non-finite 값은
  fail-closed입니다.
- ABI 0.12 `nf_develop_export_request_v6`/`nf_develop_preview_v6`는 v5 prefix 뒤에 3×8 float
  배열을 append합니다. v1~v5 entry point와 layout은 변경하지 않았습니다.
- Shell request factory는 Catalog recipe를 `DevelopColorMixer`로 정확히 복사합니다. 따라서
  preview와 export는 같은 HSL 값을 native `working_tone_adjuster`의 Point Curve 다음 단계에
  전달합니다.
- `ColorMixerEditor`는 Hue/Saturation/Luminance/All 선택과 Red, Orange, Yellow, Green, Aqua,
  Blue, Purple, Magenta 밴드를 제공합니다. 각 slider는 -1…1, 0 reset, 0.01/Shift 0.10 keyboard
  nudge와 안정된 `negaflow.develop.color-mixer.*` AutomationId를 사용합니다.

## 검증

- x64 Debug native CTest: 30/30 통과.
- x64 Debug Catalog: 336 assertions 통과.
- x64 Debug Shell: 275 assertions 통과.
- x64 Debug interop ABI 0.12: 61 assertions 통과.
- x64 Release CI gate: native CTest 30/30, Catalog 336 assertions, Shell 275 assertions,
  managed build 경고·오류 0.
- ARM64 교차 빌드: native와 managed 전체 target 빌드 경고·오류 0. 실제 ARM64 실행은 아닙니다.
- provenance: `verify-provenance.py` files=1783, text=1740, binary=43,
  declared_resources=29, reachable_commits=139 통과.

Native ABI test는 v6 request 크기와 null/undersized request를 확인하고, 범위 밖 mixer를
`invalid_color_mixer`로 거부하며, 실제 fixture에서 조정 HSL 값이 preview 픽셀을 바꾸는지
확인합니다.

## 남은 증거

현재 환경에서는 Sky UI automation이 `node_repl exec context not found`로 시작하지 않아 rendered
WinUI screenshot/UIA, compact/high-contrast, 실제 ARM64 runtime 증거는 수집하지 못했습니다.
macOS screenshot/golden과 Windows pixel diff도 아직 없습니다.
