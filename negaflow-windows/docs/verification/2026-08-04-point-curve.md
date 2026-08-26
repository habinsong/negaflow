# 2026-08-04 DR/R/G/B 포인트 커브 scalar 검증

기준일: 2026-08-04
대상: `chromabase-point-curve-v1` native reference와 tone orchestration 통합

## 검증 범위

- DR/R/G/B 제어점 정렬, 끝점 연장과 64표본 LUT 생성
- 전체 RGB LUT 뒤 채널 LUT를 적용하는 64표본 합성
- extended-linear↔sRGB 변환, active cube clamp와 alpha 보존
- 빈·근사 identity의 bit-exact 무연산과 stride padding 미기록
- 64개 제어점 허용, 65개·중복 x·범위 밖·NaN/Inf 거부
- 분리 output과 in-place output 일치
- 기본 톤 뒤 포인트 커브 순서와 실패 시 output pixel 폐기
- versioned 3×2 fixture의 LUT 표본과 24개 RGBA 값
- CLI JSON의 알고리즘 버전·적용 여부 형식
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
확인했습니다. conformance와 CLI JSON은 PowerShell `ConvertFrom-Json`으로 구문 분석했습니다.

## 자동 검증 결과

| 검사 | 결과 |
|---|---|
| x64 native Debug | CTest 27/27 통과 |
| x64 native Release | CTest 27/27 통과 |
| `native.point_curve` | Debug/Release 통과 |
| point curve conformance | 24/24 유한 값, failure 0, 최대 절대·상대 오차 0 |
| x64 CLI/DLL PE | `8664` |
| ARM64 CLI/DLL PE | `AA64` |
| ARM64 Debug/Release | 전체 target 교차 빌드 통과, 실행 미검증 |
| DLL exports | 두 architecture 모두 `nf_get_abi_version`, `nf_get_build_info_v1`만 존재 |
| 새 runtime dependency | 없음 |

합성 fixture 기대값은 macOS `CurveLUT`와 `PointCurveStage` 수식을 별도 JavaScript 계산으로 만든 뒤
C++ 출력과 비교했습니다. 처음 독립 계산에서 sRGB encode/decode 방향을 반대로 쓴 오류가 테스트에서
드러났고, 변환 방향을 바로잡은 뒤 C++과 24개 값이 일치했습니다. 잘못된 기대값에 구현을 맞추지
않았습니다.

CLI 기본 recipe에는 포인트가 없으므로 `point_curve_applied`는 `false`였고
`point_curve_algorithm_version`은 `chromabase-point-curve-v1`로 파싱됐습니다. 일반 이미지 SHA-256
설정과 경로는 변경하지 않았습니다.

## 해석 제한

- fixture는 저장소 소유 수식을 독립 계산한 합성 golden이며 실제 macOS Core Image render가 아닙니다.
- 실제 Core Image의 endpoint·lookup·Float32 반올림과 bit-exact하다고 주장하지 않습니다.
- ARM64는 이 x64 PC에서 실행하지 않았으므로 runtime 통과가 아닙니다.
- 현재 CLI/WinUI는 활성 제어점 목록을 입력·저장하지 않습니다.
- scalar reference만 검증했으며 SIMD/GPU 성능 결과가 아닙니다.
