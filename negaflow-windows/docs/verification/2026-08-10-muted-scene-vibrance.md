# Muted-scene vibrance 검증

날짜: 2026-08-10

기준: `negaflow-windows-2026-08-04-m0`, macOS commit
`2fa1d6297378673b58b8bec72025e968ccc3125c`

대상: Windows x64 Debug/Release CPU 경로, ARM64 Debug/Release 교차 빌드

## 변경 범위

- scene-ranged 비프리셋 컬러 네거티브 반전 직후에 muted-scene vibrance를 연결했습니다.
- 최대 160px 폭 linear proxy에서 HSV 평균 채도를 측정하고 macOS의 `0.24`, `×3`, 최대 `0.5`,
  활성 임계 `0.01`을 그대로 사용합니다.
- 기존 ColorModel과 같은 독립 Windows 저채도 우선 pixel 수학을 공유합니다.
- preset, B&W, 이미 채도 높은 장면과 4px 이하 입력은 exact identity입니다.
- preview와 export는 같은 `develop_manual_negative` 호출을 사용하며 추가 전체 프레임 버퍼가 없습니다.

## 실행 명령

```powershell
cmake --build --preset x64-debug --target negaflow_manual_negative_developer_tests negaflow_color_model_tests negaflow_develop_export_abi_tests
ctest --preset x64-debug -R "native\.(manual_negative_developer|color_model|develop_export_abi)$" --output-on-failure
ctest --preset x64-debug --output-on-failure

cmake --build --preset x64-release --target negaflow_manual_negative_developer_tests negaflow_color_model_tests negaflow_develop_export_abi_tests
ctest --preset x64-release -R "native\.(manual_negative_developer|color_model|develop_export_abi)$" --output-on-failure

cmake --build --preset arm64-debug --target negaflow_manual_negative_developer_tests negaflow_color_model_tests negaflow_develop_export_abi_tests
cmake --build --preset arm64-release --target negaflow_manual_negative_developer_tests negaflow_color_model_tests negaflow_develop_export_abi_tests
```

## 결과

- x64 Debug: 표적 3/3 통과(총 0.64초), 전체 native CTest 42/42 통과(총 3.89초).
- x64 Release: 3/3 통과, 총 0.27초.
- ARM64 Debug/Release: 세 target 교차 빌드 통과. ARM64 장치 실행 증거는 아닙니다.
- 저채도 컬러의 측정 amount와 chroma 증가, 고채도 exact identity, B&W·preset 제외, tiny fallback,
  기존 ColorModel 공유 수학 및 전체 C ABI 현상 경로를 확인했습니다.

## 검증하지 않은 범위

- Windows에서는 macOS Swift/Core Image 테스트를 실행하지 않았습니다.
- Core Image affine proxy sampling의 edge/phase와 `CIVibrance` pixel 출력을 동일 입력의 macOS
  관측 fixture로 아직 비교하지 않았습니다. 따라서 macOS 수치 동등성을 주장하지 않습니다.
- 실제 촬영 TIFF, ARM64 runtime, 전체 CI, WARP/GPU와 대량 batch 처리량은 실행하지 않았습니다.
