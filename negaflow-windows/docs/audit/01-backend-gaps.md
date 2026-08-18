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


# 01 — 백엔드 감사 (엔진)

macOS `Sources/Chromabase/` **159파일**을 개념 키워드로 Windows 전 트리에 대조했습니다.
히트 0 = 한 글자도 없음. 히트가 있으면 파일을 열어 함수·상수 단위로 확인했습니다.

---

## 1. 완전히 없음 — 히트 0 (28개 개념)

### 1.1 GPU · 실행 장치 (가장 큼)

| macOS | 줄 | Windows |
|---|---:|---|
| `Engine/ChromabaseMetalKernels.swift` | — | **없음** |
| `Engine/SamplingContextPool.swift` | — | **없음** |
| CoreImage 전반 (`CIImage` 83파일) | — | **없음** |

`d3d11` · `D3D11` · `Direct3D` · `ID3D11Device` · `ComputeShader` · `.hlsl` · `DirectML` ·
`DirectCompute` · `CUDA` · `OpenCL` · `Vulkan` · `ID2D1` · `Direct2D` · `DXGI` · `Win2D`
**전부 히트 0.** 셰이더 파일(`.hlsl`/`.cso`/`.fx`)도 0개.

**Windows 이미지 파이프라인은 전부 스칼라 CPU C++ 입니다.** → [`04-gpu-plan.md`](04-gpu-plan.md)

### 1.2 현상 경로

| macOS | Windows | 영향 |
|---|---|---|
| `Engine/ChromabaseEngine+PositivePipeline.swift` | **없음** | 슬라이드(포지티브) 현상 경로 전체 |
| `Film/PositiveDevelop.swift` | **없음** | 〃 |
| `Adjustments/FilmEmulationProfile+Slide.swift` | **없음** | 슬라이드 필름 에뮬레이션 |
| `Digital/DigitalFilmDevelop.swift` | **없음** | 디지털 소스 현상 |
| `Digital/DigitalSceneReconstruct.swift` | **없음** | 디지털 장면 재구성 |

### 1.3 편집 상태 · 이력

| macOS | 줄 | Windows | 영향 |
|---|---:|---|---|
| `Develop/DevelopHistory.swift` | 23 | **없음** | **현상 undo/redo 스택 자체가 없음** |
| `Features/Defects/Workflow/AppModel+DefectHistory.swift` | 205 | **없음** | 결함 도구 undo — 복제/브러시 캡슐의 되돌리기 단추가 걸 곳이 없음 |
| `Develop/DevelopKeyboardNudge.swift` | — | **없음** | 키보드 미세 조정 |
| `Develop/DevelopToneRange.swift` | — | **없음** | 톤 범위 모델 |
| `Develop/DevelopDebugFrame.swift` | — | **없음** | 디버그 오버레이 |

`CanUndo` 히트 6건은 전부 `Library*` (라이브러리 편집 undo)이고 **현상·결함과 무관**합니다.

### 1.4 스캐너 프로파일링

| macOS | 파일 | 줄 | Windows |
|---|---:|---:|---|
| `Profiles/Noise/*` | 4 | 364 | **없음** (`ScannerNoiseReduction` 도 3파일 전부 없음) |
| `Adjustments/ScannerNoiseReduction*.swift` | 3 | — | **없음** |
| `Profiles/ColorTarget/*` (IT8) | 6 | **3,255** | **없음** |
| `Profiles/ScannerProfile/ScannerProfileRegistry.swift` | 1 | — | **없음** |

**IT8 프로파일링 3,255줄이 통째로 없습니다.**

### 1.5 내보내기 · 기록

| macOS | 파일 | Windows |
|---|---:|---|
| `Export/RenderManifest*.swift` | 5 | **없음** — 무엇을 어떤 설정으로 냈는지 기록·해시·검증 |
| `Export/DestinationGamutWarning.swift` | 1 | **없음** |
| `Export/ICCOutputProfileSnapshot.swift` | 1 | **없음** |
| `Export/ExportEngine.swift` | 1 | **없음** |
| `Export/ExportRenderedImage.swift` | 1 | **없음** |
| `Export/PrintPackageRenderer.swift` | 1 | **없음** |
| `Imaging/ChannelClippingOverlay.swift` | 1 | **없음** — 채널 클리핑 표시 |
| `Adjustments/OutputDither.swift` | 1 | **없음** — 8bit 출력 디더 |

### 1.6 필름 베이스 측정

| macOS | Windows |
|---|---|
| `Film/FilmBaseMeasurementDiagnostics.swift` (186) | **없음 확정**(2026-08-18 재확인). `Method` 4종 + `Anomaly` **8종** + `EvidenceComponents` + `FilmBaseMeasurementBuilder`. 이름이 아니라 개념(`evidence`/`anomal`/`confidence`)으로 훑어도 히트 **0** |
| `Film/FilmBasePicker.swift` (149) | **2026-08-18 이식함** → `imaging/film_base_picker.cpp`(268) + `abi/pick/film_base_pick_abi.cpp` + `Interop/FilmBasePick.cs`. 시험 `native.film_base_picker` 7개 |
| `Film/FilmBaseSampleGrid.swift` (64) | **이름만 없고 이식돼 있음** — `film_base_sampling.cpp` 의 `SampleGrid`·`make_sample_grid`·`make_sample_grid_geometry` |
| `Film/FilmBaseStatistics.swift` (44) | **이름만 없고 이식돼 있음** — `coherentCluster`/`median`/`percentile` 셋 전부 `film_base_sampling.cpp` 의 `coherent_measurement`/`median`/`percentile`. **앞 판정이 틀렸습니다** — 파일명으로 찾아 "없음" 으로 적었던 것 |
| `Film/PrintPaperGrade.swift` | **없음**(엔진 쪽) |

### 1.7 GrainMend 내부

| macOS | Windows |
|---|---|
| `DefectRemoval/DefectContext.swift` | **없음** |
| `DefectRemoval/DefectLabeledMask.swift` | **없음** |
| `DefectRemoval/DefectParallelAccumulators.swift` | **없음** |
| `DefectRemoval/ConcurrentResultStore.swift` | **없음** |
| `DefectRemoval/DefectBench*.swift` (4) | **없음** (벤치 도구) |

---

## 2. 있으나 macOS 의 절반 이하 — "얇은 구현"

줄 수는 규모의 지표일 뿐이지만, **절반 이하는 기능이 빠졌다는 뜻**입니다.

| 서브시스템 | macOS | Windows | 비 | 무엇이 빠졌나 |
|---|---:|---:|---:|---|
| `Profiles/ScannerTargetGrade` (8파일) | 1,697 | 749 | **44%** | `+Signature`·`+PositiveSignature`·`+Texture`·`+DocumentedCharacter` 히트 **0** |
| `Profiles/ScannerProfile` (5파일) | 681 | 297 | **44%** | `ScannerProfileRegistry` 없음, `Matcher` 히트 1 |
| `Engine` (6파일) | 1,718 | 256 | **15%** | 포지티브 파이프라인·Metal 커널·샘플링 풀 없음 |
| `Film` (11파일) | 1,993 | 1,379 | **69%** | **`FilmBaseMeasurementDiagnostics`(186)만 없음.** 피커는 2026-08-18 이식(+268), 통계·샘플그리드는 이름만 없고 이식돼 있었음 |
| `Digital` (13파일) | 2,435 | 1,618 | **66%** | `DigitalFilmDevelop`·`SceneReconstruct` 없음 |
| `Export` (23파일) | 3,985 | 2,703 | **68%** | `RenderManifest` 5파일·감마워닝·ICC 스냅샷 없음 |

---

## 3. 구조 문제 — 성능의 근본 원인

### 3.1 `run_develop` 이 호출마다 원본을 디코드합니다

`src/Native/pipeline/develop_export.cpp:101`

```
run_develop()
  → validate_request
  → observe_source_before   ← 파일 관찰·해시
  → decode_source           ← 5088×3401 16bit TIFF 디코드 (실측 2,695 ms)
  → apply_defect_stage → ... → publish_developed
```

`src/Native/pipeline/export/stages/decode.cpp` 에 프로세스 단일 슬롯 캐시가 있습니다(2026-08-18). 같은 경로·같은 `ImageFileObservation` 이면 `decode_source` 가 디스크 TIFF 를 다시 읽지 않고 `WorkingImage` 를 복사합니다. macOS 의 `preloadedPreviewRaw` 와 같은 뜻입니다. 아직 없는 것: 프레임별 2슬롯, `interactiveProxyDimension`(1024…3600), `waitForDevelopSettle` 0.14초, 정착 프록시에서 Lanczos 축소.

프리뷰(`abi/preview/develop_preview_*.cpp`)·검출·내보내기가 **같은 `run_develop`** 을 씁니다.
그래서 슬라이더를 한 칸 움직여도 내보내기와 같은 준비 비용을 전부 냅니다.

**macOS 는 정반대입니다** (`DevelopFrameRenderer+Input.swift:48-66`):

```swift
if let cached = snapshot.preloadedPreviewRaw { return ... }   // 디코드 0회
if let full = snapshot.preloadedFullPreviewRaw { ... }        // GPU Lanczos 축소만
```

주석 원문: *"수십 MP 원본을 디스크에서 재디코딩(수백 ms)하는 대신 한 번의 Lanczos 축소로 끝난다."*

### 3.2 macOS 의 2단 렌더 — 2026-08-18 이식됨(효과 미측정)

| macOS | 값 | Windows |
|---|---|---|
| `interactiveMaxDimension` | 2560 (폴백) | `DevelopPreviewProxy.cs` |
| `interactiveProxyDimension()` | 표시 픽셀 → 256 양자화, 1024~3600 | 〃 |
| `fullMaxDimension` (정착) | 3600 | 〃 |
| `fastPreviewMaxDimension` | 720 | 〃 |
| `waitForDevelopSettle` | **0.14초** 무편집 대기 | 〃 |
| `cachedInteractivePreviewRaw` / `cachedSettledPreviewRaw` | 두 슬롯 | `decode.cpp` 는 아직 **프로세스 단일 슬롯**. 프레임별 2슬롯 아님 |

**2026-08-18**: `DevelopPreviewProxy.cs` 가 macOS 상수를 갖고, `PreviewCoordinator` 가 표시 크기
적응 패스 뒤 무편집 0.14초면 3600 정착을 돌립니다. **고정 1600×1200 은 제거됐습니다.**

> ⚠️ **앱에서 정착 패스 ms 를 재지 않았습니다.** 이식했다는 것과 빨라졌다는 것은 다릅니다.
> 계측기가 없어서 못 쟀습니다 — [`13-performance-playbook.md`](13-performance-playbook.md) 2절.

---

## 4. 창작 — macOS 에 없는 것

| Windows | 줄 | 판정 |
|---|---:|---|
| `imaging/muted_scene_vibrance_table.cpp` | 9,003 | **정당함.** macOS 는 `CIFilter("CIVibrance")` 라는 Apple 비공개 커널을 씁니다. Windows 는 그것을 33³ LUT 로 **측정해** 옮겼고 golden 해시가 문서에 있습니다. 창작이 아니라 이식 수단입니다. 다만 God object 입니다 |
| `DefectOverlayImage` 의 `Opacity="0.75"` | 1줄 | **창작이었음 — 2026-08-18 제거.** macOS 는 불투명도를 색마다 넣습니다 |
| `NativeEngineStatusService` 의 `ABI 0.48 · X64` | — | **창작이었음 — `f5d9a5b` 에서 제거** |
| GrainMend 캡슐 `CornerRadius="999"` | — | **창작이었음 — `f5d9a5b` 에서 18/15 로 수정** |

---

## 5. 대조 결과 "맞음" (오해 방지)

| 항목 | 결과 |
|---|---|
| 점 커브 보간 | macOS `CurveLUT.monotoneTangents` (Fritsch–Carlson PCHIP)가 `point_curve.cpp:158-186` 에 **정확히** 있음 — `deltas`, `0.5` 평균, `> 9.0` 클램프, `3/sqrt` 까지 동일 |
| `gridLineDrops` ↔ `structure_grid_drops` | 두 메커니즘·보조 함수·상수 12개 전부 일치 |
| 먼지·핀홀·유제 검출 | 다섯 프레임 전부 macOS 와 개수 정확히 일치 |

**`MonotoneCubic` 이름이 없다고 "톤 곡선이 macOS 와 다르다"고 적은 기존 문서는 틀렸습니다** —
[`06-false-claims.md`](06-false-claims.md) 1절.

---

## 6. GPU 이식이 드러낸 결손 (2026-08-18)

커널을 옮기면서 macOS `[[stitchable]]` 커널 32개의 Windows 대응을 **하나씩 열어 확인**했습니다.
그 과정에서 나온 결손입니다 — 이름이 아니라 **개념어로** 훑어 확정한 것들입니다.

| macOS 커널 | Windows | 확인 방법 |
|---|---|---|
| `digitalSceneReconstruct` | **없음** | `scene_reconstruct` 로 `src/Native/` 전수 → 히트 0 |
| `digitalFilmDensity` | **없음** | `film_density` → 히트 0 |
| `digitalInterImage` | **없음** | `inter_image` → 히트 0 |
| `digitalPrintPaper` | **없음** | `print_paper` → 히트 0 |
| `digitalReversalTransmit` | **없음** | `reversal_transmit` → 히트 0 |
| `digitalToDisplayGamma` | **없음** | `digital_halation.cpp` 안에도 없음 |
| `digitalToLinearLight` | **없음** | 〃 |
| `ditherAdd` | **없음** | `OutputDither.swift` 미이식 — 1.3절과 같음 |
| `channelClippingOverlay` | **없음** | `ChannelClippingOverlay.swift` 미이식 |

**`digital_film_physics.cpp` 는 이것들의 구현이 아닙니다.** 그 파일은 필름별 산란·할레이션·
그레인 **프로파일 표**(125줄)일 뿐입니다. [`04-gpu-plan.md`](04-gpu-plan.md) 의 앞 판이 그것을
대응으로 적었던 것은 **파일명으로 짐작한 오류**이고 2026-08-18 에 정정했습니다.

이 결손은 2절이 적은 `Digital` (13파일) 66% 커버리지의 실체입니다 —
`DigitalFilmDevelop`·`SceneReconstruct` 가 통째로 없습니다.

**GPU 이전에 CPU 이식이 먼저입니다.** 없는 것을 GPU 로 옮길 수는 없습니다.
