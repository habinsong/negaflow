# 영역 Defects ABI v18과 공통 파이프라인 검증

날짜: 2026-08-10

기준: macOS `2fa1d6297378673b58b8bec72025e968ccc3125c`

ABI: `0.24`, request v18

## 실행한 검증

```powershell
cmake --build --preset x64-debug --config Debug
ctest --preset x64-debug -C Debug --output-on-failure
dotnet build .\Negaflow.Windows.slnx --configuration Debug -p:Platform=x64 --no-restore
dotnet run --project .\tests\Interop.ContractTests\Negaflow.Interop.ContractTests.csproj --configuration Debug -p:Platform=x64 --no-build --no-restore -- <absolute-debug-dll>

cmake --build --preset x64-release --config Release
ctest --preset x64-release -C Release --output-on-failure
dotnet build .\Negaflow.Windows.slnx --configuration Release -p:Platform=x64 --no-restore
dotnet run --project .\tests\Interop.ContractTests\Negaflow.Interop.ContractTests.csproj --configuration Release -p:Platform=x64 --no-build --no-restore -- <absolute-release-dll>

cmake --build --preset arm64-release --config Release --target negaflow_defect_component_repair_tests negaflow_develop_export_abi_tests negaflow_native
dotnet build .\Negaflow.Windows.slnx --configuration Release -p:Platform=ARM64 --no-restore
```

## 결과

- x64 Debug 전체 native CTest `44/44` 통과
- x64 Release 전체 native CTest `44/44` 통과
- x64 Debug/Release 관리 build 경고 0·오류 0
- x64 Debug/Release Interop `103 assertions`, ABI `0.24` 통과
- ARM64 Release component repair test, develop-export ABI test, `Negaflow.Native.dll`과 관리 전체 graph 교차
  빌드 통과
- ARM64 세 네이티브 산출물의 PE machine field `0xAA64`; 실제 ARM64 runtime 증거는 아님

첫 전체 Debug CTest는 v18 헤더 변경 뒤 `negaflow_native_tests` 실행 파일을 아직 다시 빌드하지 않아 이전
ABI minor를 들고 `native.build_info` 1개가 실패했습니다. 전체 target을 다시 빌드한 뒤 같은 CTest를 재실행해
`44/44`가 통과했습니다. 소스 결함이나 기대값 수정은 필요하지 않았습니다.

## 고정한 실제 경로

- 저장소 소유 64×64 uncompressed RGB16 TIFF의 아래쪽에 세로 결함을 넣고, bottom-origin 부분 ROI와
  ROI-local top-first mask, 90도 preferred angle을 v18 caller-owned flat payload로 전달
- 같은 request의 identity와 활성 영역 Defects preview가 source-resolution BGRA8에서 다른 픽셀을 생성
- 변한 픽셀은 y-up에서 top-down으로 변환된 부분 ROI 안에만 있고 ROI 밖은 identity와 byte-exact
- identity와 활성 영역 Defects PNG16 export가 모두 게시되고 출력 byte가 다름
- preview와 export 뒤 합성 원본 TIFF가 byte-exact
- frame 밖 ROI가 `NF_DEVELOP_STAGE_DEFECT_COMPONENT_REPAIR` / `invalid_argument`로 실패하고 게시하지 않음
- 0 strength bit-exact, 0.5 strength가 같은 full repair의 linear midpoint
- 관리 구조체 크기와 pointer/strength/angle offset, 유효 payload의 native 도달, 짧은 mask의 호출 전 거부

## 검증하지 않은 범위

- macOS와 Windows의 동일 RGBAf/실제 촬영 TIFF pixel golden
- revision-aware defect sidecar, catalog 재시작 재적용, WinUI 영역 선택·brush·undo 흐름
- 대형 ROI와 수백 장 batch의 peak memory·처리량
- 실제 ARM64 Windows 장치 실행

## 후속 검증: Clone Stamp ABI v20

실행 명령:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-interop.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-managed.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ci-gate.ps1 -Preset x64-release -IncludeArm64Cross
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-interop.ps1 -Preset x64-release
```

결과:

- x64 Debug/Release native CTest `45/45`, Interop ABI `0.26`의 `118 assertions`, Catalog `583`,
  Shell `315 assertions`가 실패 없이 통과했습니다.
- hard stamp, item strength, 뒤 stroke의 full-strength source 참조, zero-offset no-op과 invalid geometry
  fail-closed를 단위 커널에서 고정했습니다.
- 64×64 합성 RGB16 TIFF의 ABI v20 preview와 PNG16 export가 identity와 다른 결과를 냈고 source TIFF는
  두 경로 뒤에도 byte-exact였습니다.
- Shell projector가 region → clone → region 순서를 보존하며 Brush는 계속 명시적으로 거부합니다.
- ARM64 Release native와 managed 전체 graph는 경고 0·오류 0으로 교차 빌드했습니다. 실행 결과가 아닙니다.

남은 검증은 macOS hosted Clone Stamp pixel golden, 실제 촬영 TIFF, 실제 ARM64 장치와 수만 개 겹침
stroke의 시간·메모리입니다.

## 후속 검증: Brush ABI v21

실행 명령:

```powershell
cmake --build --preset x64-debug --target negaflow_develop_export_abi_tests negaflow_defect_heal_brush_tests --parallel
ctest --preset x64-debug -R '^native\.(defect_heal_brush|develop_export_abi)$' --output-on-failure
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-managed.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-interop.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ci-gate.ps1 -Preset x64-release -IncludeArm64Cross
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-interop.ps1 -Preset x64-release
py ..\negaflow-mac\scripts\ci\verify-provenance.py
```

결과:

- x64 Debug/Release native CTest `46/46`, ABI `0.27` Interop `127 assertions`, Catalog `583`,
  Shell `316 assertions`가 실패 없이 통과했습니다.
- 단위 커널은 center stroke의 displaced heal, alpha 보존, item strength midpoint, empty identity와
  비정상·0~1 밖 geometry의 실패 폐쇄형 처리를 고정합니다.
- 64×64 합성 RGB16 TIFF의 ABI v21 Brush preview와 PNG16 export가 identity와 다른 결과를 냈고,
  region/Clone Stamp/Brush preview·export 뒤에도 source TIFF는 byte-exact였습니다.
- Shell projector와 managed Interop이 brush point/stroke/edit를 운반하고 기존 order 배열에서
  region → brush 순서를 보존합니다. v21 struct 크기 `4832`와 세 pointer offset `4784/4800/4816`을
  native static assertion과 managed assertion으로 함께 고정했습니다.
- ARM64 Release native와 managed 전체 graph는 경고 0·오류 0으로 교차 빌드했습니다. 실행 결과가 아닙니다.
- provenance 검증은 `files=1983`, `text=1856`, `binary=127`, `declared_resources=29`,
  `reachable_commits=148`로 통과했습니다.

첫 x64 Release 게이트 시도는 짧은 도구 제한시간으로 시작된 이전 게이트가 남아 같은 build root를
동시에 사용해 MSBuild tlog 파일 잠금으로 실패했습니다. 프로세스 종료를 확인한 뒤 단일 게이트로
재실행했으며, 별도 Release ABI 회귀에서 Brush 범위 검사가 잘못된 유사 코드 블록에 들어간 누락을
찾아 수정한 후 최종 전체 게이트가 통과했습니다.

남은 검증은 macOS hosted CoreGraphics/Core Image Brush pixel golden, macOS fallback 및 네 chunk 단위
RGBA16 flatten 누적 양자화, 실제 촬영 TIFF, 대형 ROI·대량 stroke 성능과 실제 ARM64 장치 실행입니다.
