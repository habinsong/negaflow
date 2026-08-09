# Point Curve recipe v5 vertical slice

2026-08-09에 macOS Point Curve recipe의 RGB/Red/Green/Blue channel을 Windows Catalog, Shell,
versioned C ABI, native CPU pipeline, WinUI editor까지 하나의 request로 연결했습니다.

- `params.pointCurves`는 네 배열을 저장합니다. 빈 배열은 identity이며 unknown parameter field는 유지됩니다.
- ABI 0.11 `nf_develop_export_request_v5`/`nf_develop_preview_v5`는 v4 prefix 뒤에 channel당 최대 64개의
  `(x, y)` double 좌표를 append합니다. v1~v4의 entry point와 layout은 변경하지 않습니다.
- Catalog·Interop·native는 finite `0...1`, 64개 상한, x 정렬 뒤 `1e-9` 최소 간격을 fail-closed로 확인합니다.
- `ToneCurveEditor`는 RGB/Red/Green/Blue selector, 188 DIP canvas, click/drag, non-endpoint double-click delete,
  1%/Shift 5% keyboard nudge, input/output percentage field, add/delete/reset channel을 제공합니다.
- preview와 export는 `DevelopRequestFactory`가 만든 동일 `DevelopPointCurves` request를 사용합니다.

## 검증

- x64 Debug native CTest: 30/30 통과.
- x64 Debug Catalog: 331 assertions 통과.
- x64 Debug Shell: 271 assertions 통과.
- x64 Debug interop ABI 0.11: 58 assertions 통과.

native ABI test는 malformed channel이 request validation에서 거절되고 활성 Point Curve가 preview pixel을
바꾸는 것을 확인합니다.

## 남은 증거

Sky UI automation 세션이 `node_repl exec context not found`로 시작하지 않아 현재 환경에서는 rendered
WinUI screenshot/UIA, compact/high contrast, 실제 ARM64 runtime을 수집하지 못했습니다. macOS Core Image
golden과 Windows pixel diff도 아직 없습니다.
