# Defect component repair v2 검증

날짜: 2026-08-10

기준: macOS `2fa1d6297378673b58b8bec72025e968ccc3125c`

알고리즘: `chromabase-defect-component-repair-v2`

## 실행한 검증

```powershell
cmake --build --preset x64-debug --target negaflow_defect_component_repair_tests
ctest --preset x64-debug -R "^native\.defect_component_repair$" --output-on-failure
cmake --build --preset x64-debug
ctest --preset x64-debug --output-on-failure
cmake --build --preset x64-release
ctest --preset x64-release --output-on-failure
cmake --build --preset arm64-release --target negaflow_defect_component_repair_tests negaflow_native
```

- x64 Debug targeted `1/1` 통과
- x64 Debug 전체 native CTest `44/44` 통과
- x64 Release 전체 native CTest `44/44` 통과
- ARM64 Release component repair test와 `Negaflow.Native.dll` 교차 빌드 통과
- 두 ARM64 산출물의 PE machine field는 모두 `0xAA64`였습니다. x64 host에서 실행한 증거는 아닙니다.

처음 PE 확인에 이어 붙인 `dumpbin`은 현재 shell PATH에 없어 그 확인 단계만 실패했습니다. 빌드 출력은
그 전에 정상 생성됐고, 이후 같은 COFF machine field를 직접 읽어 `0xAA64`를 확인했습니다.

## 고정한 동작

- 빈 mask의 bit-exact identity
- preferred angle이 있는 가로 scratch와 세로 구조 교차 보존
- 2:1 방향의 26.6도 얇은 구조 연결
- 11×11 두꺼운 component의 중앙까지 onion-peel 복원
- chromatic grain field의 deterministic texture transfer와 smooth-patch 방지
- 2,304픽셀 넓은 brush mask를 실제 32픽셀 damage로 축소하고 정상 영역 bit-exact 보존
- 잘못된 angle·mask layout·비유한 pixel의 fail-closed

## 검증하지 않은 범위

- macOS와 Windows를 같은 RGBAf fixture로 실행한 절대 pixel golden
- 실제 촬영 TIFF의 영역 Defects mask·복원 비교
- C ABI, catalog recipe, WinUI Defects 작업 흐름
- 수백 component·대형 ROI의 peak memory와 batch 처리량
- 실제 ARM64 Windows 장치 실행
