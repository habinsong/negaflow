# 핸드오프 — 2026-08-19 프리뷰 BGRA8 출력 (H.12 ②)

앞 문서: [`handoff-2026-08-19-preview-resident.md`](handoff-2026-08-19-preview-resident.md)
(invert→tone 상주). 이 파일이 그 다음 한 걸음입니다.

## Swift 를 열고 댄 것

`DevelopFrameRenderer+Developed.swift` `renderDisplayCGImage` (158–180행):

1. `DisplayGamutMap.apply` = Metal `gamutSoftClip` = `toneSafeUnitRGB`
   (`ChromabaseMetalKernels.swift` 63–70 · 493–494)
2. `SoftProof.apply` — `paperAndBlackInk` 일 때만 `CIColorMatrix`
   (`in * scale + bias`, 선형)
3. `OutputDither.apply` — sRGB 인코딩 공간에서 ±0.5/255
4. `context.createCGImage(..., format: .RGBA8, colorSpace: sRGB)`

Windows CPU `write_preview` 가 이미 그 순서입니다. GPU 판
`preview_display_encode.hlsl` `PreviewDisplayEncodeMain` 은 그 CPU 1:1
화소 경로입니다. `ToneSafeUnitRGB` 는 Metal 63–70행과 같은 식입니다.

의도된 차이(이미 있던 계약, 이번 창작 아님):

- 디더는 macOS `CIRandomGenerator`(시드 없음) 대신 좌표 해시
  (`display_gamut_map.h` 주석). 분포는 ±0.5/255 로 같음.
- 표시 버퍼는 XAML 이 받는 **BGRA8** (`write_preview` 와 같음).
  8비트 인코드는 RGBA8 과 같고 채널 순서만 다름.

클리핑 오버레이·상자 평균은 macOS 도 `createCGImage` 앞의 별 경로입니다.
그때는 호스트를 내리고 CPU `write_preview` 로 갑니다.

## 한 일

- 셰이더·`GpuPreviewDisplayEncode`·`try_encode_preview_bgra`
- `write_preview` 1:1 이면 GPU, 아니면 `flush` + CPU
- 상주를 publish 까지 유지. 항등 look/grain/finish 는 낡은 float 을 안 훑음
- 톤 상주는 float 을 안 내림

## 측정 (같은 명령·같은 원본)

`NEGA_TIMING=1` Release `negaflow-cli --develop-timing OpticFilm8100_frame_1.tiff x2 nocurve`
5088×3401, 상자 3600, RTX 4060 Ti.

| | ① 닫힌 뒤 두 번째 | **② 지금** |
|---|---:|---:|
| `develop` | 55.0 | **54.5** |
| `tone_adjust` | 19.0 | **0.02** |
| `output` | 78.2 | **7.01** |
| 단계 합 | 167.7 | **65.0** |
| 벽시계 | 196 | **92.8** |
| 작업 집합 봉우리 | 508 MB | **557 MB** |
| 지문 | `f6f4ab3dbcd1f25` | `8e71bb980e3d3e25` (두 번 같음) |

지문이 바뀐 이유: UAV UNORM 반올림 vs CPU `*255+0.5`. 시험 최대 **1 코드**.

## 시험 바닥

| | HEAD 이 세션 시작 | 지금 |
|---|---|---|
| native Debug ctest | 101 중 100 (gpu_working_image 하드웨어) | **101/101** |
| Catalog | 731 assertions, 실패 0 | 관리 코드 안 만짐 — 재실행 안 함 |
| Shell | 1140 assertions, 실패 0 | 재실행 안 함 |

`native.gpu_accelerator` Debug/Release 각 2회.
`invert_then_tone_preview_is_one_bgra_download`: 올리기 1 · 내리기 1 ·
`downloaded_bytes = w*h*4` · 8비트 ≤1 코드.

소스·빌드: `preview_display_encode.hlsl` + `gpu_preview_display_encode.cpp`
가 `CMakeLists.txt` 에 있고, Debug/Release `fxc` 헤더와 `negaflow_gpu.lib` /
`negaflow-cli.exe` 가 다시 만들어졌습니다.

## 확인 못 한 것

- 앱 슬라이더 벽시계
- 앱에서 렌더마다 ~1GB 작업 집합 (CLI 봉우리는 557 MB)
- A4 `run-app` x64 Release abort
- 상자 평균이 남는 경로의 GPU 축소
- 커브 켠 밴드 측정 중간 왕복
- 내장 GPU / WARP 제품 경로

## 다음 한 걸음

`07` H.12 ③ — 파라메트릭 커브 밴드 측정의 중간 float 왕복.
새 커널을 만들기 전에 있는 `GpuAreaAverage` / 유한성 검사로 줄일 수 있는지만 재십시오.
그 다음 현상 메뉴 초기화/이전이후/결함 · D1 · D5.
