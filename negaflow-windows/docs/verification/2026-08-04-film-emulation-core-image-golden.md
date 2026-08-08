# 2026-08-04 Film Emulation Core Image golden·acutance 검증

기준일: 2026-08-04
대상: `film-emulation-core-image-v1`, `chromabase-film-emulation-acutance-v1`

## canonical macOS 실행

| 항목 | 값 |
|---|---|
| workflow run | [30919921220](https://github.com/habinsong/negaflow/actions/runs/30919921220) |
| runner commit | `6d9994f00f8ce3ad8c05c3ac3ae9ae33e78f0c22` |
| macOS product baseline | `2fa1d6297378673b58b8bec72025e968ccc3125c` |
| OS | macOS 26.5.2, build 25F84 |
| fixture | `film-emulation-core-image-v1`, schema 1 |
| render | extended-linear sRGB, `RGBAf`, opaque, RGB33 |
| profile | Velvia 50, 입력 intensity 0.73, 색상 양자화 intensity 0.75 |
| artifact ID | `8897230219` |
| GitHub artifact digest | `sha256:f0ab00dee3bba2a356d448089750fd18115153df83253b40fac2d913b9b10ee4` |
| 다운로드한 JSON SHA-256 | `dc9259532eef53b7dd9cc6bbf57dc67e47bae1a19ecc355df6fcce0a65d41a80` |

artifact/JSON digest는 공급망과 fixture provenance 확인용입니다. 일반 사용자 이미지 SHA-256 옵션은
계속 기본 `끔`이며 이 검증으로 기본 image hashing을 켜지 않았습니다.

## CI 결과

| job | 결과 |
|---|---|
| Contracts, boundaries, and provenance | 통과 |
| GUI end-to-end test build | 통과 |
| Swift build and strict-concurrency tests | 통과 |
| Film Emulation golden emit/upload | 통과 |
| Unsigned release artifact smoke | 통과 |

run 전체 conclusion은 `success`입니다.

앞선 run `30918150248`도 emitter·GUI·Swift strict test는 통과했지만, Windows 1차 native C++ source를
제3자 payload로 잘못 분류한 기존 provenance gate 때문에 static job이 실패했습니다. gate의 source
분류를 고친 commit `6d9994f`에서 canonical run을 다시 실행했습니다.

## 반복성과 backend 요청 mode

두 run의 runner commit 문자열만 제외하고 metadata가 같았습니다. JSON의 12,912개 numeric value는
bit-level JSON 수치 기준으로 모두 같았고 최대 차이는 0이었습니다.

- `default`와 `software_requested`의 color-only output: 전체 exact 일치
- 두 renderer mode의 full-stage output: 전체 exact 일치
- 두 renderer mode의 impulse/step probe: 전체 exact 일치

`software_requested`는 `CIContext` option 이름이며 실제 CPU backend를 보증하지 않습니다. 결과가 같다는
사실만 기록하고 backend 종류는 추정하지 않습니다.

## 색상 cube 비교

Windows platform-neutral RGB33 reference와 macOS Core Image color-only output의 opaque RGB 36개 값을
비교했습니다.

| 지표 | 결과 |
|---|---:|
| 최대 절대 오차 | `0.0018888685` |
| RMSE | `0.0005653865` |
| `5e-5` 초과 | 28/36 |
| `1e-3` 초과 | 4/36 |
| test 허용오차 | `0.0021` |

차이는 숨기지 않고 platform envelope로 고정했습니다. 현재 증거는 opaque 4×3 fixture에 한정되며
fractional alpha와 더 넓은 cube 경계 입력은 아직 미검증입니다.

## acutance fitting과 검증

intensity 1.0 probe에서 unsharp response의 strength 선형성 최대 편차는 약 `2.4e-8`이었습니다. radius별
separable Gaussian fit은 support 5에서 다음 값을 사용합니다.

| radius | fitted sigma |
|---:|---:|
| 1.0 | 1.042 |
| 1.1 | 1.137 |
| 1.2 | 1.238 |

전체 probe 3,168개 값에 대한 fitted model 최대 절대 오차는 약 `0.001068`, RMSE는 약 `0.0001615`였습니다.
실제 profile intensity를 적용한 Ektar/Provia/Velvia impulse·saturated-step 6개 signature에서 Windows와
Core Image의 최대 절대 오차는 `0.00015372`였습니다.

canonical Velvia impulse를 scalar conformance에 넣은 결과는 다음과 같습니다.

| 항목 | 결과 |
|---|---:|
| 비교 값 | 36 RGBA |
| finite output | 36 |
| failure | 0 |
| amount | 0.22 |
| scratch | 4,356바이트 |
| 최대 절대 오차 | `3.6254525e-05` |
| 최대 상대 오차 | `0.000146816` |

unit test는 12개 profile mapping, 6개 golden signature, alpha 보존, identity, invalid parameter/view/scratch,
부분 alias·scratch overlap 거부, 33×9 exact in-place와 stride 21의 19×23 ring wrap parity를 확인합니다.

## 로컬 검증 상태

- x64 Debug/Release에서 전체 native target을 `/W4 /WX`로 컴파일했습니다.
- `negaflow_film_emulation_acutance_tests`는 failure 0, 최대 Core Image 오차 `0.00015372`로 통과했습니다.
- `negaflow-conformance`는 failure 0으로 통과했습니다.
- x64 Debug/Release CTest는 각각 32/32 통과했습니다.
- ARM64 Debug/Release는 acutance unit test와 conformance를 포함한 전체 target 교차 빌드가 통과했습니다.
  x64 호스트이므로 ARM64 실행은 하지 않았습니다.
- Release CLI/DLL은 x64 `8664`, ARM64 `AA64`이고 ARM64 acutance test executable도 `AA64`입니다. DLL
  export는 기존 `nf_get_abi_version`, `nf_get_build_info_v1` 두 개뿐이며 x64 CLI 직접 dependency는
  Windows 기본 DLL 5개입니다.
- provenance unit test 12개와 현재 1,545개 파일의 tree/implementation/external-data policy, reachable
  history 86개 commit 검사가 통과했습니다.

Windows checkout의 기존 `clear-chrome.json`은 Git blob이 manifest SHA-256과 일치하지만 working file은
Git의 CRLF 변환 때문에 byte hash가 다릅니다. 따라서 로컬 all-in-one provenance entrypoint의 resource
working-copy hash 단계는 통과로 표시하지 않습니다. canonical 원격 run의 같은 static job은 통과했고,
이번 Windows source는 resource hash를 제외한 policy 함수를 직접 실행해 검증했습니다.

## 해석 제한

- Apple의 exact `CIUnsharpMask` kernel을 알아냈거나 복제했다는 주장이 아닙니다.
- macOS 26.5.2와 현재 fixture에 맞춘 versioned compatibility envelope입니다.
- standalone acutance는 아직 색상 cube 뒤 production source route에 연결되지 않았습니다.
- scalar 처리량, SIMD/GPU/WARP와 실제 ARM64 runtime은 검증하지 않았습니다.
- 제한적 특허 검색은 법률 자문이나 freedom-to-operate 보증이 아닙니다.
