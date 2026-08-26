# 2026-08-11 IR attenuation replay ABI v24 검증

## 범위

macOS post-baseline IR layer의 저장된 R16 attenuation을 Windows Defects sidecar에서 복원해
Shell→Interop→native 공통 preview/export에 순서대로 재생하는 경계를 검증했습니다. 자동 IR 검출,
scanner companion plane, WinUI 수명주기와 macOS-hosted 동일 입력 golden은 이 기록의 범위가 아닙니다.

## 실행 명령

`negaflow-windows/`에서:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-debug
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-managed.ps1 -Preset x64-debug
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-debug
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci-gate.ps1 -Preset x64-release -IncludeArm64Cross
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-release
```

저장소 루트에서:

```powershell
py negaflow-mac/scripts/ci/verify-provenance.py
```

현재 호스트의 기본 PowerShell 실행 정책은 script 실행을 거부했으므로, 저장소가 안내하는 일회성
`ExecutionPolicy Bypass`로 다시 실행했습니다.

## 결과

- x64 Debug native CTest: 61/61 통과.
- x64 Debug Interop: 163 assertions, ABI 0.31, 실패 0.
- x64 Debug Catalog: 587 assertions, 실패 0.
- x64 Debug Shell: 336 assertions, 실패 0.
- x64 Release 전체 gate: native 61/61, Catalog 587, Shell 336, 관리 build 경고 0·오류 0.
- x64 Release Interop: 163 assertions, ABI 0.31, 실패 0.
- ARM64 Release native와 managed 전체 교차 빌드 통과. `Negaflow.Native.dll`,
  `negaflow_develop_export_abi_tests.exe`, `negaflow_defect_infrared_stage_tests.exe`의 PE Machine은 모두
  `0xAA64`였습니다. ARM64에서 실행한 결과는 아닙니다.
- provenance gate: `files=2014`, `text=1887`, `binary=127`, `declared_resources=29`,
  `reachable_commits=161`.

## 고정한 동작

- sidecar v2의 optional compressed R16을 정확한 `width × height × 2` 크기로 decode하며 필드가 없는
  legacy cluster를 계속 읽습니다. 손상 zlib와 크기 불일치는 실패 폐쇄형입니다.
- Region/IR/Clone/Brush 교차 순서를 유지하고 IR을 Region으로 접지 않습니다.
- IR stage는 attenuation division 뒤 optional core component repair를 실행합니다. core가 0이면
  attenuation만 적용하고 inpaint하지 않습니다.
- ABI v24 synthetic TIFF의 preview와 export는 같은 native 수학 경로를 사용했습니다. PNG16 결과를
  BGRA8로 다시 내린 비교의 최대 차이는 양자화 경계인 1 code였고, 입력 TIFF bytes와 SHA-256은
  전후 동일했습니다.

## 남은 증거

- 최신 macOS와 같은 paired-plane 후보 검출, local alignment·visible confirmation, null/MAD,
  significance-dependent inverse-Mills bias, attenuation/core 분리를 Windows에 아직 연결하지 않았습니다.
- 같은 visible/IR 입력의 macOS-hosted mask·R16 attenuation·최종 pixel golden이 없습니다.
- 실제 scanner companion 입력, 실제 촬영 IR TIFF pair, 대형 batch와 실제 ARM64 Windows runtime은
  검증하지 않았습니다.
