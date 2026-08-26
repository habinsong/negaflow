# Auto FilmBase affine sampled-grid 검증

날짜: 2026-08-10

기준: macOS `2fa1d6297378673b58b8bec72025e968ccc3125c`의
`FilmBaseSampleGrid.swift`와 `FilmBaseEstimator.swift`

## 수정한 차이

macOS Auto FilmBase는 폭을 `32...256`으로 제한하고 `width/sourceWidth`에서 구한 단일 scale을
x/y에 함께 적용합니다. 그 결과를 하나의 `FilmBaseSampleGrid`로 렌더한 뒤 연결 성분, 비필름 제외,
continuous border, distributed mask와 strip fallback이 모두 재사용합니다.

Windows는 같은 크기의 격자를 연결 성분과 후속 fallback에서 각각 최근접으로 만들었습니다. 이를 다음
계약으로 정렬했습니다.

- 가로축에서 정한 단일 scale로 출력 높이를 버림 계산
- output pixel center를 역변환해 두 축 모두 bilinear 표본
- 입력 extent 밖은 transparent black
- 하나의 RGB/luma 격자를 모든 Auto 측정 경로가 공유

공용 `bilinear_rgb_sampler.h`를 재사용하며 새 의존성이나 외부 코드는 추가하지 않았습니다. 연결 성분이
실패해도 같은 원본을 다시 축소하지 않으므로 fallback 경로의 중복 표본화도 제거했습니다. 다만 bilinear
연산 자체의 실제 대형 TIFF 처리량은 이번 검증에서 측정하지 않았습니다.

## 회귀 fixture

`512×129` linear RGBA32F 입력에서 R은 열마다 `0.56/0.72`, G는 행마다 `0.40/0.56`을 교차하고 B는
`0.32`로 고정했습니다. macOS 계약의 `256×64`, scale `0.5` pixel-center 표본은 모든 위치에서
`(0.64, 0.48, 0.32)`가 됩니다. 이전 최근접 경로는 짝수 행·열 위상만 읽어
`(0.56, 0.40, 0.32)`가 되므로 이 검사를 통과하지 못합니다.

동일한 공유 격자에서 연결 성분이 선택되고 최종 Auto Dmin이 `(0.64, 0.48, 0.32)`인지 확인합니다.
기존 hard-bright 제외, chromogenic demotion, luma MAD 이상치 제거, continuous/distributed/strip 및
scene-edge fallback 회귀도 x64 Debug 전체에서 함께 통과했습니다.

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

- 직접 실행한 x64 Debug manual-negative suite: `failures=0`
- x64 Debug 인접 CTest: `2/2`
- x64 Debug 전체 native CTest: `44/44`
- x64 Release 인접 CTest: `2/2`
- ARM64 Release manual-negative test, develop-export ABI test와 DLL 교차 빌드 통과
- 세 ARM64 산출물의 PE machine field: `0xAA64`

## 검증하지 않은 범위

- Windows에서는 macOS Swift/Core Image를 실행하지 않았습니다. 같은 입력의 실제 Core Image RGBAf
  sampled-grid와 Windows float 값을 비교한 golden이 없으므로 phase와 edge의 수치 동등성을 확정하지
  않습니다.
- 실제 촬영 TIFF 원본이 현재 작업공간에 없어 새 Auto Dmin과 최종 preview/export pixel을 다시 비교하지
  못했습니다.
- 실제 ARM64 Windows runtime, GPU/WARP, 대형 TIFF와 수백 장 batch 처리량은 실행하지 않았습니다.

