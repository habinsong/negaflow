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

---

## 1. 현재 상태 — GPU 코드가 한 줄도 없음

Windows 전 트리를 19개 키워드로 훑은 결과입니다.

| 키워드 | 히트 파일 수 |
|---|---:|
| `d3d11` · `D3D11` · `Direct3D` · `d3dcompiler` · `ID3D11Device` | **0** |
| `ComputeShader` · `compute_shader` · `.hlsl` | **0** |
| `DirectML` · `DirectCompute` · `CUDA` · `OpenCL` · `Vulkan` | **0** |
| `ID2D1` · `Direct2D` · `DXGI` · `Win2D` · `CanvasDevice` | **0** |

`.hlsl` / `.cso` / `.fx` 파일 **0개**.

macOS 는 반대입니다.

| 키워드 | 히트 파일 수 |
|---|---:|
| `CIImage` | **83** |
| `CIContext` | 27 |
| `CIFilter` | 13 |
| `MTLCommandQueue` | 1 (`DevelopFrameRenderer.swift:37`) |

`DevelopFrameRenderer.swift:33-51` 주석 원문:

> 공유 렌더 컨텍스트는 Metal command queue 로 만든다. 단일 큐로 GPU 작업이 정렬돼, 빠른 반복
> 렌더에서 "GPU 쓰기 완료 전에 결과를 읽어 빈/검은 프레임이 나오는" 동기화 버블을 없앤다.

**결론: macOS 이미지 파이프라인은 전부 GPU, Windows 는 전부 스칼라 CPU.**

---

## 2. 선택 — Direct3D 11 컴퓨트 셰이더

| 후보 | 판정 |
|---|---|
| **D3D11 Compute** | **채택.** Microsoft 제작, 모든 벤더 구현, Windows 기본 포함, 내장·외장 무관. WARP 소프트웨어 폴백이 정합성 검증에 쓸 수 있음 |
| D3D12 | 같은 커버리지지만 기술 부담이 큼. 이 작업에 필요한 것은 컴퓨트뿐 |
| DirectML | 추론용. 일반 이미지 커널에 과함 |
| Direct2D / Win2D | 편하지만 커널을 우리가 못 씀(고정 효과 집합) |
| CUDA | NVIDIA 전용 — **요구 위반** |
| OpenCL | 벤더 드라이버 의존, Intel 내장에서 불안정 |
| Vulkan compute | 되지만 Windows 기본 미포함 |

**하드웨어 하한**: `D3D_FEATURE_LEVEL_10_0` + `D3D11_FEATURE_D3D10_X_HARDWARE_OPTIONS` 의
`ComputeShaders_Plus_RawAndStructuredBuffers_Via_Shader_4_x` 확인.
안 되면 CPU 폴백. 요구되는 **Intel 내장(HD 4000 이후)·AMD 내장·외장 전부** 이 하한을 넘습니다.

**규칙: GPU 경로마다 CPU 폴백을 두고, 두 경로가 같은 값을 내는지 시험으로 고정합니다.**

---

## 3. 무엇을 GPU 로 옮기나 — 전 파이프라인

### 3.0 우선순위 0 — 프리뷰 프록시 캐시 (GPU 이전에 이것부터)

**GPU 를 붙여도 매번 원본을 디코드하면 소용없습니다.**
`run_develop` 은 여전히 `observe_source_before` + `decode_source` 를 지납니다. 2026-08-18 부터 `decode_source` 는 같은 파일·같은 관측이면 디스크 디코드를 건너뜁니다. 첫 호출의 2,695 ms 는 그대로이고, 같은 프레임의 다음 호출은 그 TIFF 디코드를 다시 하지 않습니다. 슬라이더 체감은 이후 단계(톤·룩 CPU)에 남습니다. 2026-08-18: `DevelopPreviewProxy` 가 macOS 상수(1024…3600, step 256, settle 0.14s)를 갖고, `PreviewCoordinator` 가 표시 크기 적응 패스 뒤 무편집 0.14초면 3600 정착을 돌립니다. 고정 1600×1200 은 제거했습니다. 앱에서 정착 패스 ms 는 아직 안 쟀습니다.

macOS 를 그대로 옮깁니다.

| macOS | 값·위치 | Windows 에 만들 것 |
|---|---|---|
| `DevelopFramePreviewRaw` | 디코드 결과를 담는 값 | 네이티브 `PreloadedSourceProxy`(BGRA/float 버퍼 + 크기 + 색공간) |
| `cachedInteractivePreviewRaw` / `cachedSettledPreviewRaw` | `AppModel+DevelopRendering.swift:355-390` 두 슬롯, `cleanRawRevision` 으로 무효화 | `PreviewCoordinator` 옆에 프레임별 2슬롯 캐시 |
| `resolveRenderInput` | `DevelopFrameRenderer+Input.swift:48-66` — 캐시 있으면 디코드 0회, 없으면 **정착 프록시에서 GPU Lanczos 축소** | `decode_source` 앞에 프록시 입력 분기 |
| `interactiveProxyDimension()` | 표시 픽셀 → 256 양자화, `1024…3600` | 같은 식 |
| `fullMaxDimension = 3600` | 정착 패스 | 같은 값 |
| `fastPreviewMaxDimension = 720` | 최초 빠른 프리뷰 | 같은 값 |
| `waitForDevelopSettle` | **0.14초** 무편집 대기 후 정착 | 같은 값 |

**ABI 변경이 필요합니다**: `DevelopExportRequest` 에 "원본 경로 대신 이미 디코드된 프록시"를
넘길 입력을 추가하고, `decode_source` 가 그것을 쓰면 디코드를 건너뜁니다.

기대 효과: 슬라이더 한 칸당 **2,695 ms 제거**. GPU 를 붙이기 전에도 체감이 바뀝니다.

### 3.1 우선순위 1 — GrainMend 검출

검출 8,932 ms 의 CPU 작업 내역(12타일 합계, 워커 4):

| 단계 | CPU 합계 | 비중 | GPU 커널 |
|---|---:|---:|---|
| 먼지 형태학(`opening`/`closing`) | 14,990 ms | **47%** | `morphology_open.hlsl` / `morphology_close.hlsl` — 분리형 1D 최소/최대, van Herk/Gil-Werman |
| 미세 입자 | 11,135 ms | **35%** | 같은 형태학 원시연산 재사용 |
| 스크래치 각도 | 2,058 ms | 6% | `scratch_angle.hlsl` — 각도별 응답을 한 디스패치로 |
| 검출 이미지 생성 | 840 ms | 3% | `detection_image.hlsl` (다운스케일 + 채널 결합) |
| 증거 조립 | 602 ms | 2% | CPU 유지(분기 많음) |
| 봉합 + 성분 | 115 ms | <1% | CPU 유지(연결 성분) |

**형태학 하나가 82%.** 여기부터 옮깁니다.

대상 파일: `imaging/grain_mend_morphology.cpp` · `grain_mend_detector.cpp` ·
`grain_mend_speck_detector.cpp` · `grain_mend_scratch_angles.cpp` · `grain_mend_detection_image.cpp`

### 3.2 우선순위 1 — 현상·보정 (우측 슬라이더 체감)

슬라이더를 끄는 동안 매 프레임 도는 화소 단계입니다. 전부 화소별 독립이라 컴퓨트에 그대로 맞습니다.

| Windows 파일 | 줄 | 커널 |
|---|---:|---|
| `imaging/working_tone_adjuster.cpp` | — | `tone.hlsl` — 노출·대비·밝은영역·어두운영역·흰색·검정 |
| `imaging/point_curve.cpp` | — | `curve_lut.hlsl` — LUT 는 CPU 에서 만들고 적용만 GPU |
| `imaging/color_mixer.cpp` | — | `color_mixer.hlsl` |
| `imaging/color_grading.cpp` | — | `grading.hlsl` |
| `imaging/color_model.cpp` + `muted_scene_vibrance_table.cpp` | 9,003 | `vibrance.hlsl` — 33³ LUT 를 `Texture3D` 로 올려 `SampleLevel` |
| `imaging/tone_mapping.cpp` | — | `tone_map.hlsl` |
| `imaging/manual_negative_developer.cpp` | — | `negative_invert.hlsl` |
| `imaging/bw_toning.cpp` | — | `bw_toning.hlsl` |
| `imaging/rescue_grade.cpp` | — | `rescue.hlsl` |
| `imaging/scene_correction.cpp` | — | `scene_correction.hlsl` |
| `imaging/primary_calibration.cpp` | — | `primary_calibration.hlsl` |
| `imaging/scanner_target_grade.cpp` | 713 | 컬러큐브는 `Texture3D` |

### 3.3 우선순위 1 — 프리뷰 리샘플

| Windows 파일 | 커널 |
|---|---|
| `imaging/working_image_resample.cpp` | `lanczos_down.hlsl` — macOS `displayProxy` 의 GPU 축소에 해당 |
| `imaging/mipmap_downsampler.cpp` | 밉맵 생성 |
| `output/working_to_srgb16.cpp` | `to_srgb.hlsl` |

### 3.4 우선순위 2 — 필름 룩·질감·그레인

| Windows 파일 | 줄 | 커널 |
|---|---:|---|
| `imaging/working_film_look.cpp` | — | `film_look.hlsl` |
| `imaging/film_emulation_color.cpp` | — | `emulation_color.hlsl`(3D LUT) |
| `imaging/film_emulation_acutance.cpp` | — | `acutance.hlsl`(분리형 컨볼루션) |
| `imaging/texture_stage.cpp` | 646 | `texture.hlsl` |
| `imaging/digital_film_grain.cpp` | — | `grain.hlsl` |
| `imaging/digital_halation.cpp` | — | `halation.hlsl`(가우시안 + 합성) |
| `imaging/film_scan_denoise.cpp` | 802 | `denoise.hlsl`(가이드 필터) |
| `imaging/local_dodge_burn.cpp` | 656 | `dodge_burn.hlsl` |

### 3.5 우선순위 2 — 인화

| Windows 파일 | 무엇 |
|---|---|
| `Views/Print/Preview/PrintPreviewRenderer.cs` | **지금 360px 썸네일을 확대해 그림** → 현상본 프록시를 쓰도록 먼저 고치고, 합성·배치를 GPU 로 |
| `Shell.Core/Print/PrintPackageLayout.cs` | 배치 계산은 CPU, 합성은 GPU |
| `PrintTextRasterizer.cs` | 캡션 래스터화 — D2D 로 |

### 3.6 우선순위 3 — 결함 수리·IR

| Windows 파일 | 줄 |
|---|---:|
| `imaging/defect_heal_brush.cpp` | 945 |
| `imaging/defect_clone_stamp.cpp` | 522 |
| `imaging/defect_component_repair.cpp` | — |
| `imaging/defect_component_texture.cpp` | — |
| `imaging/infrared_defect_detector.cpp` | 1,197 |

---

## 4. 구조 — 어디에 넣나

```
src/Native/gpu/
  gpu_device.h/.cpp          D3D11 장치·큐 1개 (macOS 의 sharedRenderContext 대응)
  gpu_capability.h/.cpp      CheckFeatureSupport → 되는지/폴백인지
  gpu_buffer.h/.cpp          구조화 버퍼·Texture2D/3D 래퍼
  gpu_dispatch.h/.cpp        디스패치 + 펜스
  shaders/*.hlsl             커널
  shaders/compiled/*.h       빌드 시 fxc 로 컴파일해 헤더로 임베드
```

- **장치는 하나.** macOS 가 command queue 하나로 정렬하는 것과 같은 이유입니다.
- **셰이더는 빌드 시 컴파일**해 헤더로 넣습니다(런타임 `d3dcompiler` 의존 제거).
- 각 커널은 `xxx_gpu()` 와 기존 `xxx()`(CPU) 를 나란히 두고, 상위에서 장치 가용성으로 고릅니다.

---

## 5. 검증 — "된다"고 말하기 전에

1. **동치 시험**: 커널마다 CPU 결과와 GPU 결과를 같은 입력으로 비교. 허용 오차는 float 반올림
   범위(`1e-5`)로 고정. 시험 이름에 커널 이름을 넣습니다.
2. **WARP 시험**: 하드웨어 없이도 CI 에서 돌도록 `D3D_DRIVER_TYPE_WARP` 로 한 번 더.
3. **측정**: 커널마다 이전/이후 ms 를 커밋 메시지에 적습니다.
4. **실기 확인**: Intel 내장 · AMD 내장 · 외장 각각에서 한 번씩.

---

## 6. 순서

| 단계 | 내용 | 기대 |
|---|---|---|
| 0 | **프리뷰 프록시 캐시 + 2단 렌더 + 0.14초 정착** (GPU 아님) | 슬라이더당 −2,695 ms |
| 1 | `gpu/` 뼈대 + 가용성 판정 + WARP 시험 | — |
| 2 | 형태학 커널 (검출 82%) | 검출 8.9초 → 목표 2.5초 |
| 3 | 톤·곡선·믹서·그레이딩·바이브런스 | 슬라이더 즉시 |
| 4 | 리샘플 · sRGB 변환 | 프리뷰 즉시 |
| 5 | 필름 룩·질감·그레인·할레이션·디노이즈 | — |
| 6 | 인화 합성 | — |
| 7 | 결함 수리·IR | — |
