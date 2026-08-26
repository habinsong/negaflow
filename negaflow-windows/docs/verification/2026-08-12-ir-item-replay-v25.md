# GrainMend IR item replay ABI v25 검증

검증일: 2026-08-12  
호스트: Windows 10.0.26200 x64, .NET SDK 10.0.302, CMake 4.3.2, MSVC/MSBuild 18.8.2

## 범위

- flat v24에서 겹치는 cluster attenuation이 반복 적용되던 결함을 item-boundary v25로 교체
- 모든 cluster correction을 같은 item base에서 계산하고 exact correction bbox의 전체 사각 patch를 순서 합성
- item range contiguous·gapless·exact-once, order exact-once, flat cluster 4,096·expanded order 8,192 상한 검증
- macOS canonical fingerprint v2 보존, attenuation 결합 v3와 v2 dual-read 후 v3 재저장 검증
- v25 preview/export 공통 수학, 원본 파일 bytes·SHA-256 불변 검증

## 실행 명령과 결과

`negaflow-windows/`에서 실행했습니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-debug
```

- exit 0
- native CTest 61/61 통과

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci-gate.ps1 -Preset x64-release -IncludeArm64Cross
```

- exit 0
- x64 Release native CTest 61/61 통과
- Catalog 592, Shell 336 assertions 통과
- x64와 ARM64 managed build 경고 0, 오류 0
- ARM64 native·managed Release graph 교차 빌드 통과

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-release
```

- exit 0
- Interop 169 assertions 통과, failures 없음
- ABI 0.32, architecture x64

```powershell
py negaflow-mac/scripts/ci/verify-provenance.py
```

- exit 0
- 2,023 files, 1,896 text, 127 binary, 29 declared resources, 167 reachable commits 검증

## 결과 계약

두 cluster가 겹치는 회귀는 attenuation을 item base에 한 번만 적용합니다. correction bbox 밖 padding은
앞 patch를 덮지 않고, bbox 내부의 unchanged pixel은 macOS와 같은 전체 사각 patch 의미로 item base를
합성합니다. v25 합성 TIFF preview와 export는 PNG16→BGRA8 양자화 최대 1 code 안에서 일치하고 source
bytes와 SHA-256은 변하지 않습니다.

## 검증하지 않은 것

- 실제 ARM64 Windows 장치 실행
- macOS 호스트의 동일 입력 mask·R16 attenuation·최종 pixel golden
- paired visible/IR 자동 검출, scanner companion 수집과 제품 UI lifecycle
- 실제 촬영 paired-plane TIFF
