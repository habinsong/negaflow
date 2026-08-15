# Auto FilmBase 선택·fallback 수학 검증

날짜: 2026-08-10

기준: macOS `2fa1d6297378673b58b8bec72025e968ccc3125c`의
`FilmBaseEstimator.swift`, `FilmBaseStatistics.swift`와
`ChromabaseEngine+NegativePipeline.swift`

## 수정한 차이

Auto FilmBase sampled-grid의 좌표 정렬 뒤, 격자에서 실제 Dmin을 선택하는 분기와 마지막 scene-edge
fallback을 함수별로 대조해 다음 차이를 수정했습니다.

- 연결 성분의 warm-backlight 강등은 macOS처럼 최상위 성분 아래에서 처음 발견한 성분 하나만 검사합니다.
  Windows가 그 성분의 R−B 조건이 맞지 않을 때 더 어두운 제3 성분까지 탐색하던 동작을 제거했습니다.
- 연결 성분과 non-film mode 강등의 R−B 대표값은 짝수 표본에서 macOS가 쓰는 위쪽 중앙값을 사용합니다.
- non-film coherent mode에 들어가는 후보도 macOS처럼 전체 후보 p99의 `0.10` 미만을 먼저 제외합니다.
- `edgeFraction=0.06`과 연속 경계 coverage `0.65`는 `double`로 계산합니다. 기존 `float` 계산은 폭
  `50/100/150/200/250`에서 경계를 한 픽셀 작게 만들 수 있었습니다.
- strip 평균은 macOS와 같이 double 누적 뒤 float Dmin으로 내립니다.
- 모든 sampled-grid 경로가 실패한 scene-edge fallback도 가로축 단일 scale, output pixel-center
  bilinear와 transparent-black 경계를 사용합니다. 이전에는 이 마지막 경로만 최근접·축별 표본이었습니다.

새 의존성이나 외부 코드는 추가하지 않았고, 기존 공용 affine RGB sampler를 사용했습니다. scene-edge는
필요한 가장자리 pixel만 직접 표본화하므로 전체 두 번째 격자를 할당하지 않습니다.

## 결과를 고정한 회귀

1. 세 개의 24-cell 연결 성분을 배치했습니다. 최상위 성분의 R−B는 짝수 표본의 아래/위 중앙값이
   `0.08/0.14`, 첫 하위 성분은 `0.12`, 제3 성분은 `0.22`입니다. macOS 계약은 첫 하위 성분 하나만
   검사하고 위쪽 중앙값을 사용하므로 최상위 성분을 유지하며 Dmin은 `(0.755, 0.70, 0.645)`입니다.
2. `100×50` 격자의 세 번째 행에 13-cell 조각 다섯 개를 놓았습니다. `Int(50×0.06)=3`과
   `Int(100×0.65)=65`를 사용해야 continuous-border가 성립합니다. 과거 float 경계는 세 번째 행을
   border로 보지 못했습니다.
3. `640×64 → 320×32` scene-edge 입력에서 최근접 위상은 어두운 pixel만 보지만 bilinear 표본은
   40개의 `(0.48, 0.32, 0.16)` 후보를 복원합니다. 최종 provenance가 `scene_edge`이고 채널 p90 Dmin이
   해당 값인지 확인했습니다.

## 실행과 결과

```powershell
cmake --build out/build/native/x64-debug --config Debug --target negaflow_manual_negative_developer_tests --parallel
.\out\build\native\x64-debug\Debug\negaflow_manual_negative_developer_tests.exe

cmake --build out/build/native/x64-debug --config Debug --target negaflow_develop_export_abi_tests --parallel
ctest --test-dir out/build/native/x64-debug -C Debug -R "native\.(manual_negative_developer|develop_export_abi)$" --output-on-failure

cmake --build out/build/native/x64-debug --config Debug --parallel
ctest --test-dir out/build/native/x64-debug -C Debug --output-on-failure

cmake --build out/build/native/x64-release --config Release --target negaflow_manual_negative_developer_tests negaflow_develop_export_abi_tests --parallel
ctest --test-dir out/build/native/x64-release -C Release -R "native\.(manual_negative_developer|develop_export_abi)$" --output-on-failure

cmake --build out/build/native/arm64-release --config Release --target negaflow_manual_negative_developer_tests negaflow_develop_export_abi_tests negaflow_native --parallel
```

- x64 Debug manual-negative 직접 실행: `failures=0`
- x64 Debug 인접 CTest: `2/2`
- x64 Debug 전체 native CTest: `44/44`
- x64 Release 인접 CTest: `2/2`
- ARM64 Release manual-negative test, develop-export ABI test와 DLL 교차 빌드 통과
- 세 ARM64 산출물의 PE machine field: `0xAA64`

## 검증하지 않은 범위

- Windows에서는 macOS Swift/Core Image를 실행하지 않았습니다. 실제 Core Image RGBAf 표본과 최종 Dmin
  golden은 없습니다.
- macOS는 렌더된 Float RGB를 Double luma·통계로 승격합니다. Windows의 sampled RGB는 같게 float이지만
  일부 luma·threshold 통계는 아직 float이므로 임계값 바로 주변의 분기 동등성은 다음 수치 작업입니다.
- 실제 촬영 TIFF, 실제 ARM64 Windows runtime, GPU/WARP와 대형 batch 처리량은 이번에 실행하지 않았습니다.
