# 2026-08-04 8대역 Color Mixer scalar 검증

기준일: 2026-08-04
대상: `chromabase-color-mixer-v1`과 point curve 뒤 working orchestration

## 검증 범위

- red/orange/yellow/green/aqua/blue/purple/magenta 고정 순서
- hue/saturation/luminance 24개 control의 `[-1, 1]` 경계와 identity 임계값
- 원형 hue 거리, 0/1 wrap과 폭 0.14의 겹침 가중 평균
- Float32 RGB↔HSL, saturation 회색 gate와 최종 `[0, 1]` 경계
- extended RGB identity bit-exact 보존과 active clamp
- alpha, stride padding과 in-place/separate output 일치
- 빨강 saturation +1이 red patch chroma를 증가시키는 기능 anchor
- point curve 뒤 Color Mixer 처리 순서와 실패 시 output pixel 폐기
- 저장소 소유 4×3 fixture의 48개 RGBA 값
- CLI JSON의 알고리즘 버전·적용 여부와 SHA 기본-off
- x64 Debug/Release 실행과 ARM64 Debug/Release 교차 빌드

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

Visual Studio 2026의 `dumpbin /headers`, `/exports`로 Release CLI/DLL architecture와 공개 C symbol을
확인했습니다. conformance와 CLI 출력은 PowerShell `ConvertFrom-Json`으로 구문 분석했습니다.

## 자동 검증 결과

| 검사 | 결과 |
|---|---|
| x64 native Debug | CTest 28/28 통과 |
| x64 native Release | CTest 28/28 통과 |
| `native.color_mixer` | Debug/Release 통과 |
| Color Mixer conformance | 48/48 유한 값, failure 0, 최대 절대·상대 오차 0 |
| default CLI JSON | version `chromabase-color-mixer-v1`, applied `false`, SHA `off`, 통계 scan 2 |
| x64 CLI/DLL PE | `8664` |
| ARM64 CLI/DLL PE | `AA64` |
| ARM64 Debug/Release | 전체 target 교차 빌드 통과, 실행 미검증 |
| DLL exports | 두 architecture 모두 `nf_get_abi_version`, `nf_get_build_info_v1`만 존재 |
| 새 runtime dependency | 없음 |

fixture 기대값은 macOS Metal source의 Float32 연산 순서를 별도 JavaScript `Math.fround` 계산으로 만든 뒤
C++ output과 비교했습니다. 12 pixel × RGBA 4개가 허용오차 안에 들어왔고 현재 compiler에서는 고정
Float32 값과 정확히 일치했습니다. 사용자 TIFF, 경로, 이름과 image hash는 fixture나 문서에 넣지 않았습니다.

기존 point curve, tone, scanner, TIFF와 출력 테스트를 포함한 전체 suite도 함께 통과했습니다. 일반 이미지
SHA-256 기본 `끔`과 명시적 opt-in 경로는 변경하지 않았습니다.

## 해석 제한

- 합성 fixture는 실제 macOS Core Image/Metal render golden이 아닙니다.
- macOS GPU compiler의 연산 결합과 Windows precise scalar가 bit-exact하다고 주장하지 않습니다.
- ARM64는 이 x64 PC에서 실행하지 않았으므로 runtime 통과가 아닙니다.
- active 24개 control은 아직 CLI/WinUI에서 입력·저장할 수 없습니다.
- scalar correctness 검증이며 SIMD, Direct2D, WARP 성능 결과가 아닙니다.
