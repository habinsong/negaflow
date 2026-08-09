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

## 검증하지 않은 항목

이 기록은 macOS screenshot pixel parity, WinUI rendered/UIA/keyboard/high-contrast/compact runtime,
또는 ARM64 runtime을 증명하지 않습니다. 실제 TIFF 내보내기도 Film preset request가 아니라
수동 Dmin CLI request입니다.
