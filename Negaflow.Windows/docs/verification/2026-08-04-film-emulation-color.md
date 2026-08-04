# 2026-08-04 Film Emulation RGB33 색상 cube 검증

기준일: 2026-08-04
대상: `chromabase-film-emulation-color-v1` standalone native component

## 검증 범위

- macOS와 같은 11종 profile enum과 각 profile의 고정 RGB33 node signature
- cube dimension 33, RGB Float32 payload 431,244바이트와 blue/green/red index 순서
- finite intensity, `[0, 1]` clamp, 5% 양자화와 정확한 half-step 반올림
- 채널 tone curve→matrix→shadow/highlight tint→hue-dependent saturation→intensity blend 순서
- extended-linear sRGB→encoded cube domain→삼선형 보간→linear sRGB 왕복
- identity의 extended RGB·alpha bit-exact 보존과 stride padding 불변
- 활성 변환의 fractional alpha 보존과 in-place/separate output 일치
- unknown enum, NaN intensity, stale cube, 잘못된 stride, 손상 cube와 비유한 pixel 거부
- 저장소 소유 4×3 Velvia 50 fixture의 48개 RGBA 값
- x64 Debug/Release 실행과 ARM64 Debug/Release 교차 빌드
- 기존 SHA-256 기본 `끔`, C ABI export와 native runtime dependency 불변

## 실행한 주요 명령

```powershell
cmake --preset x64-debug
cmake --build --preset x64-debug
ctest --preset x64-debug --output-on-failure

cmake --preset x64-release
cmake --build --preset x64-release
ctest --preset x64-release --output-on-failure

cmake --preset arm64-debug
cmake --build --preset arm64-debug
cmake --preset arm64-release
cmake --build --preset arm64-release
```

적합성 실행 파일의 JSON은 PowerShell `ConvertFrom-Json`으로 구문 분석했습니다. Visual Studio 2026의
`dumpbin /headers`와 `/exports`로 Release CLI/DLL architecture와 공개 C symbol을 확인했습니다.

## 자동 검증 결과

| 검사 | 결과 |
|---|---|
| x64 native Debug | CTest 31/31 통과 |
| x64 native Release | CTest 31/31 통과 |
| `native.film_emulation_color` | Debug/Release 통과 |
| 11종 profile signature | 11/11 허용오차 통과 |
| Film Emulation conformance | 48/48 유한 값, failure 0 |
| cube dimension | 33 |
| cube RGB payload | 431,244바이트 |
| fixture intensity | 입력 0.73, step 15, 실제 색상 강도 0.75 |
| 최대 절대 오차 | `2.384185791015625e-7` |
| 최대 상대 오차 | `5.6279360238744549e-7` |
| x64 CLI/DLL PE | `8664` |
| ARM64 CLI/DLL PE | `AA64` |
| ARM64 Debug/Release | 전체 target 교차 빌드 통과, 실행 미검증 |
| DLL exports | 두 architecture 모두 `nf_get_abi_version`, `nf_get_build_info_v1`만 존재 |
| 새 runtime dependency | 없음 |

fixture 기대값은 macOS profile 수식과 Float32 table 저장을 별도 JavaScript 계산으로 만들고, Windows와
같은 고정 index의 삼선형 보간을 독립 수행해 산출했습니다. 12 pixel × RGBA 4개와 각 profile의 한 node
signature가 허용오차 안에 들어왔습니다. 사용자 TIFF, 경로, 이름과 image hash는 fixture나 문서에 넣지
않았습니다.

cube는 caller-owned 고정 431,244바이트 외에 build/apply 내부 heap이나 full-frame allocation이 없습니다.
apply 전 안전 검사는 cube payload 전체를 한 번 읽습니다. 이 검증은 correctness와 bounded memory를
확인한 것이며 megapixel 처리량 보증은 아닙니다.

기존 Primary Calibration, Color Grading, Color Mixer, point curve, tone, scanner, TIFF와 출력 test를
포함한 전체 suite도 함께 통과했습니다. 일반 이미지 SHA-256 기본 `끔`과 명시적 opt-in 경로는 변경하지
않았습니다.

## 해석 제한

- 합성 fixture는 실제 macOS `CIColorCubeWithColorSpace` render golden이 아닙니다.
- Core Image의 실제 보간, cube 경계와 fractional-alpha 동작이 현재 삼선형 reference와 같은지
  macOS에서 확인해야 합니다.
- acutance는 포함하지 않았고 production working pipeline·CLI·WinUI에도 연결하지 않았습니다.
- ARM64는 이 x64 PC에서 실행하지 않았으므로 runtime 통과가 아닙니다.
- scalar correctness 검증이며 cube build/apply의 SIMD, DirectCompute, WARP 성능 결과가 아닙니다.
