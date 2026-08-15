# 네거티브 장면 범위 affine proxy 검증

날짜: 2026-08-10

기준: macOS `2fa1d6297378673b58b8bec72025e968ccc3125c`의
`NegativeInversion.sampleStats`와 `CIImage.transformed(by:)` proxy 좌표 계약

## 수정한 차이

macOS는 `targetW/sourceWidth` 단일 scale을 x/y에 함께 적용한 affine proxy를 output pixel center에서
bilinear로 읽습니다. Windows 장면 범위 측정은 이전에 각 축의 정수 비율로 최근접 pixel을 읽어 다음
두 차이를 만들었습니다.

- 2배 축소 같은 고주파 입력에서 한 위상만 선택
- 짧은 축의 target 크기 반올림이 x/y에 서로 다른 실효 scale을 적용

`bilinear_rgb_sampler.h`에 transparent-black 경계를 포함한 공용 RGB sampler를 두고, scene-range와
muted-scene saturation proxy가 같은 좌표 수학을 사용하게 했습니다. 통계용 153,600표본 상한은 유지하되
상한이 작동해도 가로축에서 다시 구한 단일 scale을 두 축에 적용합니다.

## 회귀 fixture

640×65 linear RGBA32F 입력에서 R은 열마다, G는 행마다 `0.08/0.16`을 교차하고 B는 `0.12`입니다.
가로 scale 0.5의 pixel-center bilinear 표본은 세 채널 모두 0.12이며, Dmin 0.8의 측정 Dmax는 모두
`log10(0.8/0.12)`여야 합니다. 이전 최근접/축별 scale 경로는 R/G에서 0.08 위상을 선택해 이 검사를
통과하지 못합니다.

## 실행

```powershell
cmake --build --preset x64-debug --config Debug --target negaflow_manual_negative_developer_tests --parallel
.\out\build\native\x64-debug\Debug\negaflow_manual_negative_developer_tests.exe

cmake --build --preset x64-debug --config Debug --target `
  negaflow_tone_pipeline_tests negaflow_colorsync_icm_develop_impact_tests `
  negaflow_cli negaflow_develop_export_abi_tests --parallel
ctest --preset x64-debug -C Debug -R `
  "native\.manual_negative_developer|native\.tone_pipeline|native\.colorsync_icm_develop_impact|cli\.negative_invert|native\.develop_export_abi" `
  --output-on-failure

cmake --build --preset x64-release --config Release --target `
  negaflow_manual_negative_developer_tests negaflow_develop_export_abi_tests negaflow_cli --parallel
ctest --preset x64-release -C Release -R `
  "native\.manual_negative_developer|cli\.negative_invert|native\.develop_export_abi" --output-on-failure

cmake --build --preset arm64-release --config Release --target `
  negaflow_manual_negative_developer_tests negaflow_native negaflow_cli --parallel

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-debug
```

## 결과

- 직접 manual-negative Debug test: failure 0
- x64 Debug 인접 native test 5/5와 전체 native CTest 44/44 통과
- x64 Release 인접 native test 3/3 통과
- ARM64 Release manual-negative test, `Negaflow.Native.dll`, CLI 교차 빌드 통과

ARM64 결과는 실제 장치 실행 증거가 아닙니다. 이번 로컬 작업에는 실제 촬영 TIFF 원본이 남아 있지 않아
새 알고리즘으로 실제 TIFF를 다시 게시하지 못했습니다. 기존 5088×3401 TIFF 게시 기록은 역사적 증거로만
유지하며, 같은 입력의 macOS/Windows Dmax와 최종 pixel golden이 확보될 때 동등성을 확정합니다.

## 남은 위험

- Auto FilmBase resolver의 여러 경로는 이후 하나의 affine sampled-grid로 정렬했습니다. Windows 회귀와
  실행 증거는 `2026-08-10-auto-filmbase-affine.md`에 있으며, macOS Core Image float golden은 남았습니다.
- Core Image `CIVibrance`와 Windows 저채도 우선 수학의 최종 pixel 허용오차가 없습니다.
- 극단적인 세로 panorama에서는 Windows 통계 표본 상한이 macOS 전체 proxy보다 적습니다.
- 실제 ARM64 Windows runtime은 미검증입니다.
