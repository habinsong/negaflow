# 2026-08-09 Film preset base v4 verification

## 실행 환경

Windows x64 host, `x64-debug` 및 `x64-release` preset에서 수행했습니다. ARM64는 교차 빌드만 했으며
ARM64 Windows 장치에서 실행하지 않았습니다.

## 결과

| 명령 | 결과 |
| --- | --- |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-debug` | native CTest 30/30 통과 |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-managed.ps1 -Preset x64-debug` | 경고 0, 오류 0, Catalog 317 / Shell 267 assertions 통과 |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-debug` | ABI 0.10, interop 54 assertions 통과 |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-release` | native CTest 30/30 통과 |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-managed.ps1 -Preset x64-release` | 경고 0, 오류 0, Catalog 317 / Shell 267 assertions 통과 |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-release` | ABI 0.10, interop 54 assertions 통과 |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 -Preset arm64-release` | native ARM64 교차 빌드 통과 |
| `dotnet build Negaflow.Windows.slnx -c Release -p:Platform=ARM64 --nologo` | 관리 ARM64 교차 빌드, 경고 0, 오류 0 |
| `py negaflow-mac/scripts/ci/verify-provenance.py` | files=1773, text=1730, binary=43, declared_resources=29, reachable_commits=137 |

실제 사용자 TIFF `OpticFilm8100_frame_1.tiff`(5088×3401, 16-bit RGB)는 수동 Dmin CLI 경로로
PNG16 내보내기에 성공했습니다. 결과 PNG는 100,377,638바이트이며 SHA-256은
`eab2e899b9e9a913be5a141afca9835040f36d3d28dd8e3bb86dcf044b54708b`입니다.

## 2026-08-10 실제 TIFF Film request 추가 검증

x64 Release `Negaflow.Native.dll`의 frozen `nf_develop_export_v4` entry point를 MTA 작업 프로세스에서
직접 호출했습니다. request는 `Film` mode, `kodak-portra-400`, `warm-led`, color negative,
PNG16을 사용했습니다. STA 셸에서의 첫 호출은 decode 전에 `com_apartment_mismatch`로 거부됐고
산출물을 만들지 않았으며, MTA 재실행 결과는 다음과 같습니다.

- ABI status `0`, `succeeded=1`, `failed_stage=0`, `failure_name=ok`
- 5088×3401, source 103,825,968바이트
- base source `7`(`preset_measured`)
- applied Dmin `(0.2446564, 0.1377584, 0.06714519)`
- 검증·게시된 PNG16 101,864,918바이트, SHA-256
  `63555AC04C8782E463C31AA77E5E49206177230EAC504BF0B2849870113D655B`
- native wall time 5,332.02ms
- 원본 길이·UTC 수정시각·파일 속성 전후 동일

출력은 추적하지 않는 `negaflow-windows/out/` 아래에만 있으며 제품·fixture payload가 아닙니다.

## 검증하지 않은 항목

이 기록은 macOS screenshot pixel parity, WinUI rendered/UIA/keyboard/high-contrast/compact runtime,
또는 ARM64 runtime을 증명하지 않습니다. Film preset 실제 TIFF request는 Windows 내부 readback과
원본 관찰 계약까지 통과했지만, 같은 TIFF의 macOS pixel golden 비교는 아닙니다.
