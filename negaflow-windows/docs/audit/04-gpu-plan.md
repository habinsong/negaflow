> # ☠️ 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음 ☠️
>
> **🔬 추측·가설 금지.** "냄새난다" 고 덮지 말고 **냄새의 원인을 찾아 없애십시오.**
> 재현하고, 스택을 잡고, 계측해서 원인을 **확정**한 뒤에 고칩니다.
> 원인을 못 잡았으면 **"못 잡았다" 고 적으십시오** — 추측으로 고친 것은 다음 사람의 함정입니다.
>
> **🌐 모르면 웹 검색을 적극적으로** 하십시오 — 특히 GPU·최적화·UI/UX 구현. 찾은 것은 출처를 남기십시오.
>
> **백엔드**: macOS Swift 파일을 **먼저 열고** 코드를 1:1 로 그대로 옮깁니다.
> 상수 하나, 임계 하나, 게이트 순서 하나도 지어내지 마십시오.
> 이름이 같다고 "있음" 으로 적지 마십시오 — **함수 안을 읽고** 판정하십시오.
>
> **프론트엔드**: ① computer-use 로 Windows 앱을 **구역별 크롭**해서 보고
> ② **Parsec 으로 macOS negaflow** 를 같은 구역으로 보고
> ③ **스크린샷 84장**(`negaflow_mac_screenshot/`)을 확인한 **뒤에만** 판정합니다.
> **모양·크기·위치·정렬·색상·내용·텍스트 안 잘림** 일곱 가지를 전부 맞춥니다.
> XAML 에 있다고 "있음" 이 아닙니다 — **화면에 보여야** 있는 것이고,
> **눌러서 값이 안 바뀌면 가짜**입니다.
>
> **저장소**: 본체 `C:\Users\habin\negaflow\`(Apache 2.0) · 스캐너 `C:\Users\habin\negaflow-scanner-sane\`(GPL).
> **두 저장소의 `negaflow-mac\` 은 절대 고치지 마십시오.** 코드 파쿠리·라이선스·특허·저작권 위반 금지.
>
> 규칙 [`00-index.md`](00-index.md) · UI 검증 [`11`](11-ui-verification-protocol.md) · 라이선스 [`12`](12-repos-and-licence.md)

---

---

# 04 — GPU 이식 계획 (이미지 관련 전부)

> **사용자 요구:** GPU 를 쓸 것. Intel 내장·AMD 내장·외장(Intel/NVIDIA/AMD) **공통으로 되는 것.**
> 검출뿐 아니라 **현상·프리뷰·보정·우측 슬라이더·인화 등 이미지 관련 전부.**

**최종 갱신 2026-08-18.** 이 판은 앞 판과 다릅니다.
앞 판은 "무엇을 GPU 로 옮길까" 를 **Windows CPU 파일 목록에서 역으로 추측**했습니다 — 창작에 가깝습니다.
이번에는 **macOS 가 GPU 에서 실제로 돌리는 커널 파일을 열어서** 세었고, **그 목록이 이식 대상**입니다.

> **이 문서는 *무엇을* 옮길지입니다. *어떻게* 빠르게 만들지는 [`13-performance-playbook.md`](13-performance-playbook.md).**
> 스레드 그룹 크기·`groupshared` 상한·분리형 컨볼루션·vHGW 형태학·가이드 필터 O(1)·
> **더블 버퍼 다운로드**(D3D11 의 `Map` 은 동기화합니다)·품질 지키는 절차가 거기 있습니다.
> **GPU 밖의 것**(스레드 풀·컴파일러 스위치·SIMD·표시 경로 복사)도 거기 있습니다.

---

## 0. 근거 — 이 문서가 딛고 있는 실측

> ### ✅ 2026-08-18 착수함 (`aa0d59f`)
>
> 아래 표의 "히트 0" 은 **착수 전 상태**입니다. 지금은 `src/Native/gpu/` 가 있습니다.
>
> | 만든 것 | 무엇 |
> |---|---|
> | `gpu/gpu_device.*` | D3D11 장치·컨텍스트 하나. FL 11_0 하한, WARP 폴백, **벤더 ID 로 거르지 않음** |
> | `gpu/gpu_working_image.*` | `R32G32B32A32_FLOAT` 텍스처 + SRV/UAV, 업로드·다운로드, `GpuStagingRing`(더블 버퍼) |
> | `gpu/shaders/*.hlsl` | `basic_tone` · `parametric_tone_curve` · `color_grade` + 공용 `tone_shared.hlsli` |
> | `gpu/gpu_pointwise.*` | 화소별 커널 32개가 공유하는 골격 — 바인딩·디스패치·상수 |
> | `gpu/gpu_tone_kernels.*` · `gpu_color_kernels.*` | `basicTone` · `parametricToneCurve` · `colorGrade` |
> | `cmake/CompileShaders.cmake` | `fxc` 로 빌드 시 컴파일해 헤더 임베드 |
>
> **실측** — 이 기계 RTX 4060 Ti, **FL 11_1**, VRAM 7949MB. Parsec 가상 어댑터는 규칙대로 걸러짐.
>
> | 시험 | 결과 |
> |---|---|
> | 텍스처 왕복 | WARP·NVIDIA 양쪽 **비트 단위 일치**. 행 여백 미오염 |
> | `basicTone` CPU/GPU 최대 오차 | WARP **1.8e-07~6.0e-07** · NVIDIA **3.6e-07~7.7e-07** (허용 1e-5) |
> | `parametricToneCurve` | WARP **6.0e-08~1.2e-07** · NVIDIA **2.4e-07** |
> | `colorGrade` | WARP **0~1.8e-07** · NVIDIA **6.0e-08~2.4e-07** |
> | `colorMixerHSL` | WARP **0~6.0e-08** · NVIDIA **0~1.3e-06** |
> | `negativeInvert` (현상 최대 비용 단계) | WARP **7.5e-08~1.5e-07** · NVIDIA **8.9e-08~1.8e-07** |
> | `bwToning` | WARP **0~1.2e-07** · NVIDIA **1.2e-07~1.8e-07** |
> | `digitalBWFilm` (CPU 는 `double`) | WARP **3.0e-07~4.2e-07** · NVIDIA **4.2e-07~4.8e-07** |
> | 노출 (macOS 전용 커널 없음) | **양쪽 전부 0 — 비트 단위 일치** |
> | 포인트 커브 (LUT 적용) | WARP **1.8e-07~3.6e-07** · NVIDIA **3.0e-07~3.6e-07** |
>
> ### ✅ 톤 단계가 전부 GPU 커널을 갖췄습니다
>
> `apply_working_tone_adjustments` 의 하위 7단계 — **노출 · 기본 톤 · 파라메트릭 커브 ·
> 포인트 커브 · 컬러 믹서 · 컬러 그레이딩 · 원색 보정** — 이 전부 이식됐습니다.
> 사용자가 "우측탭 뭘 써도 수 초" 라고 한 그 경로입니다.
> **이제 파이프라인 연결이 의미를 갖습니다** — 업로드 1회 → 7단계 GPU 상주 → 다운로드 1회.
> | `calibrationPrimaries` | WARP **전부 0** · NVIDIA **0~1.4e-06** |
> | 매개변수 조합 | 11개 — 양수/음수 대비, 임계 미만, clamp, 각 마스크 |
> | 새 시험 | `native.gpu_device` · `native.gpu_working_image` · `native.gpu_basic_tone` 전부 통과 |
>
> ⚠️ **이 기계에는 Intel/AMD 내장이 없습니다.** 범용성은 **코드 구조로만** 보장돼 있고
> 내장 GPU 실기 확인은 **못 했습니다.** 됐다고 적지 마십시오.
>
> ⚠️ **아직 파이프라인에 연결되지 않았습니다.** 커널은 시험에서만 돕니다.
> `stages/look.cpp` 가 아직 CPU `apply_working_tone_adjustments` 만 부릅니다.

### 착수 전 상태 (2026-08-18 이전)

| 사실 | 어떻게 쟀나 | 값 |
|---|---|---|
| Windows GPU 코드 | `d3d11`·`d3d12`·`directml`·`dxgi`·`hlsl`·`Win2D`·`CanvasDevice`·`vulkan`·`opencl`·`cuda` 로 `src/` 전수 | **히트 0** |
| `.hlsl` / `.cso` / `.fx` / `.comp` 파일 | `find` | **0개** |
| 히트처럼 보인 2건 | `mipmap_downsampler.h:19` · `tone_mapping.h:47` | **둘 다 주석**. 코드 아님 |
| macOS GPU 커널 | `Chromabase/Engine/ChromabaseMetalKernels.swift` (859줄) | `[[stitchable]]` **32개** |
| macOS 커널의 이웃 접근 | 같은 파일에서 `destCoord`·`samplerCoord`·`.sample(` | **0회** — 32개 **전부 화소별** |
| macOS 이웃 연산 | `CIGaussianBlur`·`CIBoxBlur`·`CIMedianFilter`·`CIAreaAverage` | Apple **내장 필터**가 처리 |
| 파이프라인 이음매 | `src/Native/pipeline/export/stages/` 10파일 | 전 단계가 `WorkingImage&`(호스트 float32 RGBA) |
| **단계별 ms 계측기** | `src/Native/pipeline/` 에서 `elapsed`·`duration_ms`·`stage_ms` | **없음 — 기준선이 없습니다** |

**마지막 줄이 이 계획의 0단계입니다.** 재지 않고 시작하는 최적화도 추측입니다.

---

## 1. macOS 가 실제로 GPU 에서 돌리는 것

### 1.1 컨텍스트 — 큐 하나

`Features/Develop/Pipeline/Renderer/DevelopFrameRenderer.swift:33-51`

```swift
static let metalDevice = MTLCreateSystemDefaultDevice()
static let metalQueue  = metalDevice?.makeCommandQueue()
static let sharedRenderContext: CIContext = {
    let options: [CIContextOption: Any] = [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        .outputColorSpace:  CGColorSpace(name: CGColorSpace.sRGB) as Any,
    ]
    if let queue = metalQueue { return CIContext(mtlCommandQueue: queue, options: options) }
    …
}()
```

주석 원문:

> 공유 렌더 컨텍스트는 Metal command queue 로 만든다. 단일 큐로 GPU 작업이 정렬돼, 빠른 반복
> 렌더에서 "GPU 쓰기 완료 전에 결과를 읽어 빈/검은 프레임이 나오는" 동기화 버블을 없앤다.

컨텍스트는 셋입니다 — 본 렌더(`linear→sRGB`) · `linearRawProxyContext`(`linear→linear`) ·
`srgbRawProxyContext`(`sRGB→sRGB`). **Windows 도 장치·컨텍스트를 하나로 둡니다. 같은 이유입니다.**

### 1.2 정밀도 — 시작 전에 정하고 가야 하는 것

macOS 는 `.workingFormat` 을 **설정하지 않습니다.** 전 트리에서 주는 곳은 IT8 평가기 2곳
(`IT8PatchEvaluator.swift:129`, `ScannerRelativeIT8Benchmark.swift:76`, 둘 다 `RGBAf`)뿐입니다.
Core Image 의 기본 작업 형식은 **half float** 입니다. Windows 는 `Rgba32F` — **float32**.

**즉 Windows CPU 파이프라인은 이미 macOS 보다 정밀합니다. 이 차이는 지금도 있는 것이고, 이번 작업이 만드는 것이 아닙니다.**

**결정: GPU 텍스처 포맷은 `R32G32B32A32_FLOAT`.**

| 왜 | |
|---|---|
| 시험 가능성 | 지금 CPU 결과와 GPU 결과를 **`1e-5` 로 고정**해야 "정확히 옮겼다" 를 증명할 수 있습니다. half 로 가면 무엇이 이식 실수이고 무엇이 반올림인지 못 가립니다 |
| 골든값 | 기존 골든 해시·dmin 이 전부 float32 기준입니다. 포맷을 낮추면 전부 흔들립니다 |
| macOS 와 다르지 않나 | 다릅니다. **그러나 CPU 에서 이미 다릅니다.** 맞추려면 CPU·GPU 를 같이 내려야 하고 그것은 별건입니다. **이 문서는 그 결정을 하지 않습니다** |

### 1.3 이식 대상 — `[[stitchable]]` 커널 32개

`ChromabaseMetalKernels.swift`. **전부 화소별**이라 HLSL 로 **옮겨쓰는 작업**입니다.
알고리즘을 새로 설계할 것이 없습니다.

| # | macOS 커널 | 줄 | Windows CPU 대응 (파일명 추정 — 열어서 대조할 것) |
|---:|---|---:|---|
| 1 | `colorMixerHSL` | 74 | `color_mixer.cpp` |
| 2 | `colorGrade` | 101 | `color_grading.cpp` |
| 3 | `bwToning` | 123 | `bw_toning.cpp` |
| 4 | `calibrationPrimaries` | 151 | `primary_calibration.cpp` |
| 5 | `basicTone` | 185 | `working_tone_adjuster.cpp` |
| 6 | `parametricToneCurve` | 242 | `point_curve.cpp` |
| 7 | `filmGrain` | 281 | `digital_film_grain.cpp` |
| 8 | `scannerLowSatChroma` | 289 | `scanner_target_grade.cpp` |
| 9 | `scannerMidtoneChroma` | 306 | `scanner_target_grade.cpp` |
| 10 | `filmScanShrink` | 362 | `film_scan_denoise.cpp` |
| 11 | `gfProduct` | 466 | `film_scan_denoise.cpp` (가이드 필터 4단) |
| 12 | `gfCoeffA` | 470 | 〃 |
| 13 | `gfCoeffB` | 482 | 〃 |
| 14 | `gfApply` | 486 | 〃 |
| 15 | `gamutSoftClip` | 493 | `tone_mapping.cpp` |
| 16 | `noritsuTexture` | 505 | `texture_stage.cpp` |
| 17 | `boundedRelativeGrade` | 531 | `rescue_grade.cpp` |
| 18 | `negativeInvert` | 557 | `manual_negative_developer.cpp` |
| 19 | `highlightDesaturate` | 580 | `tone_mapping.cpp` |
| 20 | `ditherAdd` | 596 | **Windows 없음** — `OutputDither.swift` 미이식 |
| 21 | `channelClippingOverlay` | 604 | **Windows 없음** — `ChannelClippingOverlay.swift` 미이식 |
| 22 | `digitalSceneReconstruct` | 640 | `digital_film_physics.cpp` |
| 23 | `digitalFilmDensity` | 653 | 〃 |
| 24 | `digitalInterImage` | 681 | 〃 |
| 25 | `digitalPrintPaper` | 692 | 〃 |
| 26 | `digitalReversalTransmit` | 702 | 〃 |
| 27 | `digitalHalation` | 712 | `digital_halation.cpp` |
| 28 | `digitalToDisplayGamma` | 738 | 〃 |
| 29 | `digitalToLinearLight` | 742 | 〃 |
| 30 | `digitalFilmColor` | 774 | `digital_film_color_preset.cpp` |
| 31 | `digitalFilmGrainDensity` | 800 | `digital_film_grain.cpp` |
| 32 | `digitalBWFilm` | 826 | `digital_bw_film_look.cpp` |

> ### 2026-08-18 실제 대조 결과 — 위 표의 오른쪽 열은 **추정이었고 일부 틀렸습니다**
>
> 이식하면서 하나씩 열어 확인했습니다. **확정된 것만** 적습니다.
>
> | # | 커널 | 실제 Windows 대응 | 상태 |
> |---:|---|---|---|
> | 1 | `colorMixerHSL` | `color_mixer.cpp` `apply_color_mixer` | **이식함** |
> | 2 | `colorGrade` | `color_grading.cpp` `apply_color_grading` | **이식함** |
> | 3 | `bwToning` | `bw_toning.cpp` `apply_bw_toning` | **이식함** |
> | 32 | `digitalBWFilm` | `digital_bw_emulsion_response.cpp` (CPU 는 `double`) | **이식함** |
> | 4 | `calibrationPrimaries` | `primary_calibration.cpp` | **이식함** |
> | 5 | `basicTone` | `tone_mapping.cpp` `apply_basic_tone` | **이식함** |
> | 6 | `parametricToneCurve` | `tone_mapping.cpp` `apply_parametric_tone_curve` | **이식함** |
> | 18 | `negativeInvert` | **`core/negative_inversion.cpp`** (imaging 아님) | **이식함** |
> | 17 | `boundedRelativeGrade` | `rescue_grade.cpp` 아님 — **`scanner_target_grade.cpp:62-64`** 안에 박혀 있음 | ☠️ **단순 이식 불가** (아래) |
> | 22 | `digitalSceneReconstruct` | **없음** | CPU 부터 없음 |
> | 23 | `digitalFilmDensity` | **없음** | 〃 |
> | 24 | `digitalInterImage` | **없음** | 〃 |
> | 25 | `digitalPrintPaper` | **없음** | 〃 |
> | 26 | `digitalReversalTransmit` | **없음** | 〃 |
> | 28 | `digitalToDisplayGamma` | **없음** | 〃 |
> | 29 | `digitalToLinearLight` | **없음** | 〃 |
>
> **22~26·28·29 는 `digital_film_physics.cpp` 가 아닙니다.** 그 파일은 필름별 산란·할레이션·
> 그레인 **프로파일 표**일 뿐이고 커널이 아닙니다. 개념어(`scene_reconstruct`·`inter_image`·
> `print_paper`·`reversal_transmit`·`film_density`)로 `src/Native/` 를 훑어도 **히트 0** 입니다.
> [`01-backend-gaps.md`](01-backend-gaps.md) 가 적은 `DigitalFilmDevelop`·`SceneReconstruct` 결손과
> 같은 것입니다. **GPU 이전에 CPU 이식이 먼저입니다.**
>
> ☠️ **17 `boundedRelativeGrade` 는 화소별 옮겨쓰기가 아닙니다.** Windows 는 그 혼합을
> `scanner_target_grade.cpp` 의 화소 루프 안에서 하고, 그 안의 `transformed_srgb`·`gamut_scale`
> 이 **전부 `double`** 입니다. float32 GPU 로 옮기면 `1e-5` 를 못 지킬 수 있습니다.
> 옮기려면 먼저 **CPU 를 float 로 내려도 골든이 안 바뀌는지** 재야 합니다. 재기 전에는 손대지 마십시오.
>
> ⚠️ **먼저 [`../verification/2026-08-10-macos-kernel-audit.md`](../verification/2026-08-10-macos-kernel-audit.md) 를 읽으십시오.**
> 그 문서가 **이미 수식 1:1 대조를 했습니다**(2026-08-10 기준):
> `basicTone`·`parametricToneCurve`·`negativeInvert`·`colorMixerHSL`·`colorGrade`·
> `calibrationPrimaries`·`bwToning`·텍스처 = **일치**, `filmGrain` = 수식 일치·잡음원만 다름.
> **이 9개는 GPU 이식 시 CPU 코드를 그대로 HLSL 로 옮기면 됩니다.**
>
> ☠️ **그리고 아래 세 커널은 macOS 활성 파이프라인이 부르지 않습니다** (같은 문서 "없어서 맞는 것들"):
> **8·9 `scannerLowSatChroma`/`scannerMidtoneChroma`, 15 `gamutSoftClip`, 19 `highlightDesaturate`.**
> 정의만 남아 있고 호출부가 **없습니다.** PostPipeline 주석의 *"타겟 프로파일 밖의 고정 NR·명부
> 탈채도·추가 gamut 압축은 적용하지 않는다"* 와 일치합니다.
> **소스에 있다는 이유로 GPU 로 옮기면 macOS 에 없는 효과를 만들어 냅니다. 옮기지 마십시오.**
> 나머지 커널도 **옮기기 전에 호출부가 살아 있는지부터** 확인하십시오.
>
> ⚠️ 위 대조는 **2026-08-10 기준**입니다. 그 뒤 바뀐 곳은 다시 봐야 합니다.
> 나머지 열은 파일명으로 짐작한 것입니다. **그 파일을 열어 수식이 같은지 확인**하십시오.
> 다르면 **CPU 쪽이 이미 틀린 것**이고, GPU 이식보다 그것을 먼저 고쳐야 합니다.
> 20·21 은 macOS 에 있고 Windows 에 **없는 기능**입니다 — GPU 이전에 **CPU 이식이 먼저**입니다.

### 1.4 Apple 이 공짜로 준 것 — 우리가 직접 써야 하는 것

macOS 커널이 전부 화소별인 이유는 **이웃 연산을 Apple 내장 필터가 대신하기 때문**입니다.
Windows 에는 그 내장 필터가 없습니다. **여기가 실제 작업량입니다.**

| macOS 내장 필터 | 쓰이는 곳 | Windows 에서 만들 것 |
|---|---|---|
| `CIGaussianBlur` | `ColorModel.swift:128,166` · `FilmScanDenoise.swift:96` · `LocalDodgeBurnStage.swift:169` · `ScannerNoiseReduction+Color.swift:19` | **분리형 가우시안** — 수평 1D + 수직 1D, `groupshared` 타일 캐시 |
| `CIBoxBlur` | `FilmScanDenoise.swift:154` | **분리형 박스** — 슬라이딩 윈도우로 화소당 O(1) |
| `CIMedianFilter` (3×3) | `FilmScanDenoise.swift:171` | **3×3 중앙값** — 9원소 정렬 네트워크 |
| `CIAreaAverage` | 히스토그램·자동 보정 | **병렬 리덕션** |
| `CIRandomGenerator` | 그레인·디더 노이즈 | **결정적 해시 노이즈.** macOS 와 화소값까지 맞춰야 하면 **씨앗 규칙부터 대조** |
| `CIVibrance` | `ColorModel` | **이미 CPU 로 이식돼 있음** — Apple 비공개 커널이라 33³ LUT 로 측정 이식(`muted_scene_vibrance_table.cpp` 9,003줄). GPU 에서는 `Texture3D` + `SampleLevel` **한 번**. **GPU 이득이 가장 큰 곳 중 하나** |

---

## 2. Windows 가 지금 하는 것 — 이음매는 어디인가

`src/Native/pipeline/develop_export.cpp:101` `run_develop` 의 단계 순서:

```
validate → observe → decode → invert → defect → grain → grade → look → grain → finish → publish
```

| 단계 파일 | 안에서 부르는 화소 커널 |
|---|---|
| `stages/invert.cpp` | `resolve_auto_negative_base` · `develop_manual_negative` |
| `stages/grade.cpp` | `apply_scene_correction` · `apply_scanner_target_grade` · `apply_rescue_grade` · `apply_scanner_profile_grade` · `apply_color_model` |
| `stages/look.cpp` | `apply_working_tone_adjustments` · `apply_working_film_look` |
| `stages/finish.cpp` | `apply_film_scan_denoise` · `apply_local_dodge_burn` · `apply_texture_stage` · `apply_bw_toning` · `apply_image_transform` · `working_image_resample` · `apply_output_sharpening` |

**전 단계가 `negaflow::imaging::WorkingImage&` 를 받습니다:**

```cpp
struct WorkingImage final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint32_t stride_pixels{0};
    std::vector<negaflow::core::Rgba32F> pixels{};   // 호스트 메모리
};
```

즉 **단계마다 호스트 메모리를 통째로 훑습니다.** 이것이 다음 절을 결정합니다.

---

## 3. 설계 결정 — 단계마다 올렸다 내리면 집니다

Core Image 는 `CIImage` 체인을 **지연 합성**하고 `CIContext` 가 **마지막에 한 번** 평가합니다.
중간 결과가 호스트로 내려오지 않습니다.

**따라서 Windows 도 `GpuWorkingImage` 를 만들어 단계 사이에 GPU 에 머무르게 합니다.
업로드 1회(디코드 뒤), 다운로드 1회(발행 앞).**

왜 협상 불가인지 — 24MP float32 RGBA 산술:

```
24,000,000 화소 × 16 바이트 = 384 MB
단계는 위에서 11개 → 단계마다 왕복하면 왕복 10회 이상
```

커널이 아무리 빨라도 **전송이 지배**합니다. 한 번 올리고 한 번 내리면 **왕복 1회**입니다.

> ⚠️ **위는 바이트 산술이고, 실제 전송 ms 는 아직 재지 않았습니다.**
> 내장 GPU 는 시스템 메모리를 공유해 왕복이 훨씬 쌉니다(그래도 복사입니다).
> **0단계에서 이 기계의 실제 업로드/다운로드 대역폭을 재서 이 자리를 채우십시오.**

설계 결과:

- `WorkingImage` ↔ `GpuWorkingImage` 변환은 **파이프라인 양 끝에만** 둡니다.
- 각 `apply_*` 는 `WorkingImage&` 판(CPU)과 `GpuWorkingImage&` 판(GPU)을 **나란히** 갖습니다.
- 어느 단계가 아직 GPU 판이 없으면 **그 단계 앞뒤로만** 내렸다 올립니다 —
  이식이 진행될수록 왕복이 저절로 사라집니다.
- 다운로드는 **스테이징 텍스처 + `D3D11_MAP_READ`**. 기본(`DEFAULT`) 텍스처는 직접 매핑할 수 없습니다.
- 핑퐁 텍스처 **2장**을 두고 단계마다 교대합니다(in-place 쓰기는 UAV 경합).

---

## 4. API 선택 — Direct3D 11 컴퓨트 셰이더

| 후보 | 판정 |
|---|---|
| **D3D11 Compute** | **채택.** Microsoft 제작, 모든 벤더 구현, Windows 기본 포함, 내장·외장 무관. WARP 소프트웨어 폴백을 CI 정합성 시험에 쓸 수 있음 |
| D3D12 | 커버리지는 같지만 기술 부담이 큼. 필요한 것은 컴퓨트뿐 |
| DirectML | 추론용. 일반 이미지 커널에 과함 |
| Direct2D / Win2D | 편하지만 **커널을 우리가 못 씀**(고정 효과 집합) — macOS 커널 32개를 그대로 옮길 수 없음 |
| CUDA | NVIDIA 전용 — **요구 위반** |
| OpenCL | 벤더 드라이버 의존, Intel 내장에서 불안정 |
| Vulkan compute | 되지만 Windows 기본 미포함 |

### 4.1 하드웨어 하한 — **기능 수준 11_0**

Direct3D **10.0/10.1 기기도 컴퓨트 셰이더 4.x 를 선택적으로** 지원합니다.
`CheckFeatureSupport(D3D11_FEATURE_D3D10_X_HARDWARE_OPTIONS, …)` 의
`ComputeShaders_Plus_RawAndStructuredBuffers_Via_Shader_4_x` 로 판정합니다.
**그러나 10.x 경로의 제약이 우리 설계와 맞지 않습니다:**

| 10.x 컴퓨트 제약 | 우리 설계와 충돌 |
|---|---|
| **UAV 를 1개만** 바인딩 가능 | 핑퐁 출력 + 보조 출력이 안 됨 |
| UAV 는 `RWStructuredBuffer` / `RWByteAddressBuffer` **만** | `RWTexture2D<float4>` 못 씀 |
| 스레드 그룹 **768개**까지, X·Y 각각 768 제한 | — |
| `numthreads` 의 **Z 는 1** 고정 | — |

**결정: `D3D_FEATURE_LEVEL_11_0` 을 하한으로 둡니다.**
Intel 내장은 **HD 4000(Ivy Bridge, 2012)** 부터, AMD 내장·외장은 그보다 앞서 11_0 입니다 —
요구된 **Intel 내장·AMD 내장·외장 전부** 이 하한을 넘습니다.
11_0 미만이면 **CPU 폴백**으로 갑니다(기능 축소가 아니라 지금 그대로).

출처: [D3D11_FEATURE_DATA_D3D10_X_HARDWARE_OPTIONS](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/ns-d3d11-d3d11_feature_data_d3d10_x_hardware_options) ·
[Compute Shaders on Downlevel Hardware](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-devices-downlevel-compute-shaders)

### 4.2 셰이더 컴파일

- D3D11 = **셰이더 모델 5.0** = `fxc`. (SM 6.0/`dxc` 는 D3D12 경로입니다 — 섞지 마십시오.)
- **빌드 시 컴파일해 헤더로 임베드**합니다. 런타임 `d3dcompiler` 의존을 없앱니다.
- `/Gis`(부동소수 엄격) 를 켜고, 필요한 곳에 `precise` 를 답니다 —
  **드라이버가 임의로 재배열하면 CPU 와 값이 갈립니다.** 동치 시험이 벤더마다 다르게 깨지는 원인이 여기입니다.

---

## 5. 뼈대 — 어디에 넣나

```
src/Native/gpu/
  gpu_device.h/.cpp        D3D11 장치·컨텍스트 1개 (macOS sharedRenderContext 대응)
  gpu_capability.h/.cpp    CheckFeatureSupport → 11_0 인지 / WARP 인지 / CPU 폴백인지
  gpu_working_image.h/.cpp WorkingImage ↔ GPU 텍스처, 핑퐁 2장, 스테이징 다운로드
  gpu_dispatch.h/.cpp      디스패치 + 상수 버퍼 바인딩
  gpu_neighborhood.h/.cpp  가우시안·박스·중앙값·리덕션 (1.4절)
  shaders/*.hlsl           커널
  shaders/compiled/*.h     빌드 시 fxc 로 컴파일해 임베드
```

- **God object 금지 규칙(500줄)은 여기에도 적용됩니다.** 커널 32개를 한 파일에 넣지 마십시오
  (macOS 가 859줄 한 파일인 것은 Core Image 가 **하나의 Metal 소스 문자열**을 요구하기 때문이고,
  그 파일에 `// allow: SIZE_OK` 예외 주석이 달려 있습니다 — 우리에겐 그 제약이 없습니다).
- 각 커널은 `xxx_gpu()` 와 기존 `xxx()`(CPU) 를 나란히 두고, 상위에서 가용성으로 고릅니다.

---

## 6. 순서 — 이 차례로 합니다

| 단계 | 내용 | 왜 이 자리인가 | 기대 |
|---|---|---|---|
| **0** | **단계별 ms 계측** — `RunTracker` 에 stage 별 소요 기록 + CLI 로 덤프. 업로드/다운로드 대역폭 측정 | **기준선이 없습니다.** 재지 않으면 이후 전부 추측 | 기준선 확보 |
| **1** | **프리뷰 프록시 캐시** (GPU 아님) | 매번 디코드하면 GPU 를 붙여도 소용없음 | 아래 6.1 |
| **2** | `gpu/` 뼈대 + 가용성 판정 + WARP 시험 | 커널 없이 골격만 | — |
| **3** | **화소별 커널** — 1.3절 32개 중 현상·보정 경로(1~6, 15·17~19, 22~32) | 우측 슬라이더 체감의 전부 | 슬라이더 즉시 |
| **4** | **이웃 원시연산** — 1.4절 가우시안·박스·중앙값·리덕션 | 3단계가 끝나야 이것이 병목으로 드러남 | 디노이즈·닷지번·할레이션 |
| **5** | **형태학** (GrainMend 검출) | 검출 CPU 의 **82%** | 아래 6.2 |
| **6** | 리샘플 · sRGB 변환 | 프리뷰 경로 | — |
| **7** | 인화 합성 | 인화 프리뷰가 썸네일 확대를 쓰는 문제를 먼저 고친 뒤 | — |
| **8** | 결함 수리 · IR | 사용 빈도 낮음 | — |

### 6.1 1단계 상세 — 프리뷰 프록시 (다른 에이전트 진행 중)

**GPU 를 붙여도 매번 원본을 디코드하면 소용없습니다.**

2026-08-18 현재: `decode_source` 가 같은 파일·같은 관측이면 디스크 디코드를 건너뜁니다.
첫 호출의 **2,695 ms** 는 그대로이고, 같은 프레임의 다음 호출은 그 TIFF 디코드를 다시 하지 않습니다.
`Shell.Core/Develop/DevelopPreviewProxy.cs` 가 macOS 상수(1024…3600, step 256, settle 0.14s)를 갖고,
`PreviewCoordinator` 가 표시 크기 적응 패스 뒤 무편집 0.14초면 3600 정착을 돌립니다.
고정 1600×1200 은 제거됐습니다.

**아직 안 된 것: 앱에서 정착 패스 ms 를 재지 않았습니다.** 0단계 계측기가 나오면 그것으로 잽니다.

macOS 대응 상수:

| macOS | 값·위치 |
|---|---|
| `interactiveProxyDimension()` | 표시 픽셀 → 256 양자화, `1024…3600` |
| `fullMaxDimension` | **3600** (정착 패스) |
| `fastPreviewMaxDimension` | **720** (최초 빠른 프리뷰) |
| `thumbnailMaxDimension` | **360** |
| `waitForDevelopSettle` | **0.14초** 무편집 대기 후 정착 |
| `cachedInteractivePreviewRaw` / `cachedSettledPreviewRaw` | `AppModel+DevelopRendering.swift:355-390` **두 슬롯**, `cleanRawRevision` 으로 무효화 |

### 6.2 5단계 상세 — GrainMend 검출

검출 8,932 ms 의 CPU 작업 내역(12타일 합계, 워커 4):

| 단계 | CPU 합계 | 비중 | GPU 커널 |
|---|---:|---:|---|
| 먼지 형태학(`opening`/`closing`) | 14,990 ms | **47%** | 분리형 1D 최소/최대 — van Herk/Gil-Werman |
| 미세 입자 | 11,135 ms | **35%** | 같은 형태학 원시연산 재사용 |
| 스크래치 각도 | 2,058 ms | 6% | 각도별 응답을 한 디스패치로 |
| 검출 이미지 생성 | 840 ms | 3% | 다운스케일 + 채널 결합 |
| 증거 조립 | 602 ms | 2% | **CPU 유지**(분기가 많음) |
| 봉합 + 성분 | 115 ms | <1% | **CPU 유지**(연결 성분) |

**형태학 하나가 82%.** 대상 파일: `grain_mend_morphology.cpp` · `grain_mend_detector.cpp` ·
`grain_mend_speck_detector.cpp` · `grain_mend_scratch_angles.cpp` · `grain_mend_detection_image.cpp`

---

## 7. 검증 — "된다" 고 말하기 전에

1. **동치 시험**: 커널마다 CPU 결과와 GPU 결과를 같은 입력으로 비교. 허용 오차 **`1e-5`**.
   시험 이름에 커널 이름을 넣습니다.
2. **WARP 시험**: 하드웨어 없이도 CI 에서 돌도록 `D3D_DRIVER_TYPE_WARP` 로 한 번 더.
3. **골든 유지**: 실측 코퍼스 17장의 dmin·해시가 **바이트까지 그대로**인지.
4. **측정**: 커널마다 이전/이후 ms 를 **커밋 메시지에** 적습니다.
5. **실기 확인**: Intel 내장 · AMD 내장 · 외장에서 각각 한 번씩.
   **이 기계에 없는 벤더는 "확인 못 함" 으로 적습니다.** 됐다고 적지 마십시오.

---

## 8. 위험 — 미리 적어 둡니다

| 위험 | 내용 | 대응 |
|---|---|---|
| **큰 스캔** | D3D11 FL 11_0 의 `Texture2D` 한 변 상한은 **16384**. 평판 고해상 스캔은 이것을 넘을 수 있습니다 | **타일 분할 필수.** 사용자 실제 최대 스캔 크기를 **재서** 이 칸을 채울 것 |
| **내장 GPU 메모리** | 내장은 시스템 메모리를 나눠 씁니다. float32 RGBA 는 화소당 16바이트 | 타일 + 핑퐁 2장까지만. 상한 초과 시 CPU 폴백 |
| **드라이버별 부동소수** | 최적화 재배열로 벤더마다 값이 갈릴 수 있음 | `/Gis` + `precise`. 동치 시험이 벤더별로 다르게 깨지면 **여기부터** 봅니다 |
| **노이즈 재현성** | `CIRandomGenerator` 를 대체하면 그레인 무늬가 macOS 와 달라짐 | 씨앗 규칙을 먼저 대조. 못 맞추면 **"다르다" 고 적을 것** |
| **half vs float** | 1.2절 — macOS 는 half, 우리는 float32 | 이번 작업에서 건드리지 않음. **별건으로 남김** |

---

## 9. 아직 모르는 것 (정직하게)

1. **단계별 실제 ms** — 계측기가 없어 `decode 2,695 ms` 와 검출 내역 말고는 기준선이 없습니다.
2. **업로드/다운로드 실제 대역폭** — 3절의 384 MB 는 산술이고 ms 가 아닙니다.
3. **이 기계의 GPU** — 어떤 장치이고 FL 이 얼마인지 아직 안 찍었습니다. 2단계에서 찍습니다.
4. **사용자 최대 스캔 크기** — 16384 한계에 걸리는지 미확인.
5. **1.3절 오른쪽 열** — 파일명 추정이고 수식 대조를 안 했습니다.
