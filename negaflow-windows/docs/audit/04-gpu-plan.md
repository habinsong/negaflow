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
> ③ **스크린샷 50장**(`C:\Users\habin\맥negaflow 스크린샷\`)을 확인한 **뒤에만** 판정합니다. 폴더·파일 전체 목록은 [`11`](11-ui-verification-protocol.md) 1.3절.
> **모양·크기·위치·정렬·색상·내용·텍스트 안 잘림** 일곱 가지를 전부 맞춥니다.
> XAML 에 있다고 "있음" 이 아닙니다 — **화면에 보여야** 있는 것이고,
> **눌러서 값이 안 바뀌면 가짜**입니다.
>
> **화면 도구 — 자세히.** `windows-mcp` / `windows-gui` MCP 는 **절대 금지.** 켜지 말고 호출하지 말고 대용으로도 쓰지 마십시오. Windows 앱·Parsec 맥 화면은 **computer-use 만.** computer-use 도 **꼭 필요할 때만** 씁니다(토큰). **씁니다:** 이 작업에서 화면에 보이는지·눌러서 값이 바뀌는지·잘림/정렬/색을 새로 판정해야 하고 코드·단위시험·스크린샷 50장·기존 로그로는 부족할 때. **쓰지 않습니다:** 백엔드·네이티브·시험만 고칠 때, 스크린샷 폴더+Swift/XAML 으로 충분할 때, 방금 본 화면을 다시 찍을 때, "일단 띄워 보자" 탐색. 쓸 때도 전체를 반복 찍지 말고 **해당 구역만 크롭.** 전문은 [`00`](00-index.md) · [`11`](11-ui-verification-protocol.md).
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

## 0. 지금 어디까지 왔나 (2026-08-19)

> ### 2026-08-19 갱신 — 아래 0.0~0.4 는 **2026-08-18 판**입니다. 이 상자가 그 뒤를 적습니다.
>
> **① 옮기면 안 되는 것이 4개가 아니라 10개입니다.** 호출 사슬을 끝까지 따라가니
> `digitalSceneReconstruct`·`digitalFilmDensity`·`digitalInterImage`·`digitalPrintPaper`·
> `digitalReversalTransmit`·`digitalFilmColor` **여섯이 macOS 에서 죽어 있습니다**
> (호출부가 정의만 있고 아무도 안 부릅니다). 0.3절의 *"CPU 판부터 없음 (7)"* 중
> 다섯이 여기 해당하고, 남은 둘(`digitalToDisplayGamma`·`digitalToLinearLight`)은
> 이식했습니다. 근거는 [`06`](06-false-claims.md) 11절.
>
> **② `noritsuTexture` 는 Windows CPU 판이 이미 있습니다**
> (`scanner_target_grade.cpp:86` `apply_noritsu_texture`). camelCase 로 grep 해서
> 못 찾았던 것입니다 → [`06`](06-false-claims.md) 12절.
>
> **③ `film_scan_denoise` GPU 오케스트레이터는 제품 경로에 있습니다**
> (`gpu_film_scan_stage.cpp` → `gpu_accelerator.cpp` → `stages/finish.cpp`)
> → [`06`](06-false-claims.md) 13절.
>
> **④ 디지털 필름 룩 사슬 다섯을 이식하고 오케스트레이터로 묶었습니다.**
> 헐레이션(커널은 있었고 표에 `nullptr` 이라 **1 ms 도 안 줄고 있었습니다**) ·
> 33³ 색 큐브 · 아큐턴스 · 스톡 색 프리셋 · 밀도 그레인.
>
> **실측 (5088×3401 실제 스캔, RTX 4060 Ti, 프리뷰 3600, `--develop-timing … filmlook`)**
>
> | 단계 | CPU (`NEGA_GPU=0`) | 지금 | |
> |---|---:|---:|---:|
> | `film_look` | **35,126.25 ms** | **370.22 ms** | **−98.9%** |
> | `tone_adjust` | 1,239.65 ms | 440.28 ms | −64.5% |
> | 전체 | **37,016.98 ms** | **809.75 ms** | **−97.8% (45.7배)** |
>
> 사슬 오케스트레이터가 왜 필요했는지 — 재료 다섯을 **각자** GPU 로 돌렸을 때
> `film_look` 이 1,926 ms 였습니다. 24MP 에서 왕복이 다섯 번(277 MB × 10)이라
> **전송이 커널을 삼켰습니다.** 한 번 올려 한 번 내리니 370 ms 입니다 —
> 3절의 *"단계마다 올렸다 내리면 집니다"* 가 실측으로 재확인된 것입니다.
>
> **필름 스캔 경로**(사용자 실사용 경로)는 이 사슬을 지나지 않습니다. 그쪽 실측은
> 전체 **753 ms** 이고 내역은 `develop` 306.79 · `tone_adjust` 239.10 · `output` 106.97 입니다.
>
> ### ☠️ 2026-08-19 — **가장 비싼 단계를 못 보고 있었습니다: `target_grade` 58,995 ms**
>
> 계측 CLI 가 기본값(`develop_target = main`)으로만 재고 있었고, 그 값에서는 이 단계가
> **아예 안 돕니다.** 표에 찍힌 `0.00 ms` 는 "빠르다" 가 아니라 "안 돌았다" 였습니다.
>
> | 단계 | `main` | `noritsu` |
> |---|---:|---:|
> | `develop` | 201.00 ms | 349.08 ms |
> | `tone_adjust` | 176.10 ms | 452.84 ms |
> | **`target_grade`** | **0.00 ms** | **58,995.23 ms** |
> | 전체 | 584.71 ms | **60,536.19 ms** |
>
> 전체의 **97.5%**, 두 번째 단계의 **130배**입니다. `apply_profile_grade` 가 화소마다
> `transformed_srgb` 를 **두 번** 돌리고(정방향·역방향) `gamut_scale` 로 섞는데 그 안이
> 전부 `double` 이고 `log`·`exp`·`pow`·`fmod` 가 여러 번 돕니다. `noritsu` 는 그것을
> **두 번**(기본 + 상대 시그니처) 태우고 장치 질감(`noritsuTexture`)까지 얹습니다.
>
> **고쳤습니다 — 두 걸음입니다.**
>
> | | ms | |
> |---|---:|---:|
> | 처음(직렬 CPU) | **58,995.23** | |
> | 행 블록 병렬(비트 단위 동일) | **16,201** | −72.5% |
> | GPU | **859.18** | −94.7% |
> | | | **합계 −98.5%** |
>
> **2026-08-19 — TextureStage `filmGrain` GPU + 클리핑 오버레이.**
> 그레인 동치 NVIDIA 5.96e-08 / WARP 0. 프리뷰 `texture` 단계는 GPU 가 **더 느림**
> (26.84 → 69.52 ms)이라 기본 끔(`NEGA_GPU_TEXTURE_GRAIN=1`).
> `ditherAdd` 는 8bit CPU 경로에 이미 있음 — 별도 GPU 패스 없음.
> 클리핑 오버레이는 설정+프리뷰 합성+비트 일치 GPU. 상세 [`15`](15-gpu-handoff.md) 3.3·3.4.
>
> **2026-08-19 — `CIAreaAverage` 리덕션 GPU.** `groupshared` 트리, wave 없음.
> 동치 2.98e-08. 5088×3401 전체 CPU **25.109 ms** / GPU **33.397 ms** 라 기본 끔
> (`NEGA_GPU_AREA_AVERAGE=1`). 상세 [`15`](15-gpu-handoff.md) 3.5.
>
> **2026-08-19 — 장치 질감도 GPU.** `target_grade` **887.44 → 231.33 ms**,
> 노리츠 프리뷰 전체 **2,040 → 1,288 ms**. 질감 단독 동치 7.15e-07(NVIDIA) /
> 5.96e-07(WARP). 상세 [`15`](15-gpu-handoff.md) 3.1.
>
> 노리츠 프리뷰 전체(그레이드 GPU 직후) **60,536 → 2,038 ms**. 병렬화가 값을 안 바꿨다는 것은
> 프리뷰 지문으로 증명했습니다(직렬·병렬 둘 다 `cfe1f1b11f1cc9a3`).
>
> ☠️ **macOS 는 같은 수식을 64³ 큐브로 262,144번만 풉니다**
> (`ScannerTargetGrade+Apply.swift` 의 `CIColorCubeWithColorSpace`).
> Windows 는 화소마다 풉니다 — 24MP 에서 **66배**입니다. 이번 작업은 Windows 의 셈을
> 옮긴 것이고, **큐브로 바꾸는 것은 값이 달라지는 별건**입니다.
>
> 근거는 [`06`](06-false-claims.md) 14절, 이어서 할 일은 [`15`](15-gpu-handoff.md).
>
> **전송을 재고 고쳤습니다** — 왕복 145 → **63.5 ms**(3절 상자). 진입점 여덟이
> 작업 텍스처를 호출마다 만들던 것도 `GpuImagePool` 로 묶었습니다. 그 결과
> **필름 스캔 경로 753 → 585 ms**, 디지털 필름 룩 810 → 642 ms.
> 실측 `CIVibrance` 33³ 표(`muted_scene_vibrance`·`color_model`)도 이식했습니다.
>
> **2026-08-19 — `GpuMipHalve` 배선.** `downsample_for_statistics` 에 붙임.
> 제품 경로 비트 일치. 프리뷰 x2 마지막 전체 617.69 → 629.15 ms 라 **이득 없음**,
> 기본 끔(`NEGA_GPU_MIP_HALVE=1`). `GenerateMips` 미사용. 상세 [`15`](15-gpu-handoff.md) 3.6.
>
> **2026-08-19 — 흑백 디지털 룩 사슬.** 헐레이션→유제→아큐턴스→그레인 한 왕복.
> `film_look` **27,343 → 215 ms**, 전체 29,413 → 611 ms. 동치 3.28e-07.
> 상세 [`15`](15-gpu-handoff.md) 3.7.
>
> **2026-08-19 — 3.8 double 계측.** `box_mean` 을 잠깐 float 로 내려도
> frame_1 자동 검출 610/9331 이 같았습니다. 제품은 double 유지.
> 밴드 평균 double 은 D3D11 선택 기능이라 **이식 불가**.
>
> **2026-08-19 — 스크래치 각도 GPU.** 검출 17,276 → **4,527 ms**, 전체 **4,663 ms**.
> 610/9331 유지. 상세 [`15`](15-gpu-handoff.md) 3.2.

### 0.0 — 아래는 2026-08-18 판입니다


#### 진척률 — 세는 방법을 먼저 밝힙니다

☠️ **"몇 %" 는 세는 기준을 안 밝히면 거짓말입니다.** 세 가지로 나눠 셉니다.

macOS `ChromabaseMetalKernels.swift` 의 `[[stitchable]]` 커널은 **정확히 32개**입니다
(`grep -c stitchable`). 그중 4개는 **macOS 활성 파이프라인이 부르지 않으므로 이식 대상이 아닙니다** —
분모에서 뺍니다. **대상은 28개.**

| 기준 | 진척 | 근거 |
|---|---|---|
| **① 커널 이식** (28개 중) | **14 / 28 = 50%** | 0.1절 표. 전부 CPU/GPU 동치 시험으로 고정(`1e-5`) |
| **② 커널 중 *GPU 자체가 막혀 있지 않은* 것** | **14 / 14 = 100%** | ☠️ **2026-08-18 정정.** 남은 14개 중 **GPU 쪽 장애물이 있는 것은 `boundedRelativeGrade` 하나뿐**입니다(CPU 가 `double`). 나머지 13개는 **CPU 이식·기능 이식·이식 정확성** 문제이지 GPU 문제가 아닙니다. "3D LUT 필요"·"이웃 접근"·"씨앗 규칙 대조" 는 셋 다 **제 오판이었습니다** → [`14`](14-remaining-gpu-methodology.md) 0절 |
| **③ 제품 경로 반영** | **부분** | 톤 7단계 · 반전 · 유한성 확인은 **붙었습니다**. `film_scan_denoise` 오케스트레이터 **없음**, 형태학 **기본 꺼짐**, `GpuMipHalve` **미배선** — 0.4절 |

**커널 외에 만든 것**(분자에 안 셌습니다): 이웃 원시연산 5개(박스·가우시안·중앙값·형태학·밉축소) ·
유한성 리덕션 · 장치/텍스처/스테이징 뼈대 · 계측기(`--develop-timing`) · 영속 워커 풀.

**측정된 결과**(5100×3408 실제 스캔, RTX 4060 Ti, 프리뷰 경로):
CPU **911.35 ms** → 지금 **약 720 ms**. `develop` 348.56 → 261.49(−25%),
`tone_adjust` 356.43 → 276.1(−22%).

☠️ **①이 50% 라고 "절반 남았다" 로 읽지 마십시오.** 남은 14개 중 13개는
**GPU 작업이 아니라 CPU 이식·기능 이식·선행 조사**입니다. 0.3절이 하나하나 이유를 답니다.

### 0.1 이식 완료 — macOS 커널 **14개** + 이웃 원시연산 5개 + Windows 전용 3개

> 아래 표는 **줄 수와 커널 수가 다릅니다.** 가이드 필터 한 줄이 macOS 커널 4개
> (`gfProduct`·`gfCoeffA`·`gfCoeffB`·`gfApply`)입니다. macOS 커널로 세면 **14개**이고,
> 노출·포인트 커브·감마 리프트는 macOS 에 대응 커널이 없는 **Windows 전용 3개**입니다.

전부 **CPU/GPU 동치 시험으로 고정**돼 있습니다(허용 오차 `1e-5`). 수치는 이 기계 실측입니다 —
**RTX 4060 Ti · FL 11_1 · VRAM 7949MB**, 그리고 하드웨어 없는 경우를 위한 **WARP**.

| 커널 | macOS | Windows CPU | WARP 최대 오차 | NVIDIA 최대 오차 |
|---|---|---|---:|---:|
| 노출 | (전용 커널 없음) | `core/pointwise.cpp` `apply_exposure` | **0** | **0** |
| `basicTone` | `:185` | `imaging/tone_mapping.cpp` | 6.0e-07 | 7.7e-07 |
| `parametricToneCurve` | `:242` | `imaging/tone_mapping.cpp` | 1.2e-07 | 2.4e-07 |
| 포인트 커브 | `PointCurveStage` | `imaging/point_curve.cpp` | 3.6e-07 | 3.6e-07 |
| `colorMixerHSL` | `:74` | `imaging/color_mixer.cpp` | 6.0e-08 | 1.3e-06 |
| `colorGrade` | `:101` | `imaging/color_grading.cpp` | 1.8e-07 | 2.4e-07 |
| `calibrationPrimaries` | `:151` | `imaging/primary_calibration.cpp` | **0** | 1.4e-06 |
| `negativeInvert` | `:557` | `core/negative_inversion.cpp` | 1.5e-07 | 1.8e-07 |
| `bwToning` | `:123` | `imaging/bw_toning.cpp` | 1.2e-07 | 1.8e-07 |
| `digitalBWFilm` | `:826` | `imaging/digital_bw_emulsion_response.cpp` | 4.2e-07 | 4.8e-07 |
| `gfProduct`·`gfCoeffA`·`gfCoeffB`·`gfApply` | `:466`~`:486` | `film_scan_denoise_filters.cpp` `guided_base` | **0** | 4.1e-06 |
| `filmScanShrink` | `:362` | `film_scan_denoise_tile.cpp` `process_tile` | 1.2e-07 | 5.0e-06 |
| **박스 블러**(원시연산) | `CIBoxBlur` | `film_scan_denoise_filters.cpp` `box_blur` ×2 | **0** | **0** |
| **가우시안**(원시연산) | `CIGaussianBlur` | 〃 `gaussian_blur` · `texture_stage_gaussian.h` | **0** | **0** |
| **3×3 중앙값**(원시연산) | `CIMedianFilter` | 〃 `median3` | **0** | **0** |
| `digitalHalation` | `:712` | `imaging/digital_halation.cpp` | **0** | **0** |
| **감마 리프트** | (CI 체인 밖) | `film_scan_denoise_tile.cpp` `extract_lifted_tile` | 6.0e-08 | 1.2e-07 |
| **형태학**(원시연산) | (검출 경로, CI 아님) | `imaging/grain_mend_morphology.cpp` | **0** | **0** |

> `filmScanShrink` 줄은 **CPU 리프트를 올린 상태**의 사슬 전체 오차입니다. GPU `pow` 로
> 리프트하면 2.1e-05 ~ 6.2e-05 가 됩니다 — 이유는 **0.6절**입니다.
>
> `digitalHalation` 도 가우시안을 쓰지만 **delta 0** 입니다. 그 가우시안은 직접
> 컨볼루션이라 러닝 섬의 누적 이력이 없고, 앞에 `pow` 도 없기 때문입니다.

### 0.2 만든 뼈대

| 파일 | 무엇 |
|---|---|
| `gpu/gpu_device.*` | D3D11 장치·컨텍스트 하나(macOS `sharedRenderContext` 대응). FL 11_0 하한, WARP 폴백, **벤더 ID 로 거르지 않음** |
| `gpu/gpu_working_image.*` | `R32G32B32A32_FLOAT` 텍스처 + SRV/UAV, 업로드·다운로드·복사, `GpuStagingRing`(더블 버퍼) |
| `gpu/gpu_pointwise.*` | 화소별 커널이 공유하는 골격 — 커널마다 복사하면 32벌이 어긋납니다 |
| `gpu/gpu_neighborhood.*` | 박스 블러 · 3×3 중앙값 |
| `gpu/gpu_gaussian_blur.cpp` | 분리형 가우시안. 가중치는 **호스트가 CPU 와 같은 코드로** 만들어 `StructuredBuffer<float>` 로 넘깁니다 |
| `gpu/gpu_guided_filter.cpp` | 가이드 필터 4단 |
| `gpu/gpu_film_scan.*` | 감마 리프트 · `filmScanShrink` |
| `gpu/gpu_digital_halation.*` | 산란·헐레이션 재분배 |
| `gpu/gpu_morphology.*` | 열기·닫기·양극 톱햇. **검출 CPU 의 82%** |
| `gpu/gpu_tone_kernels.*` · `gpu_color_kernels.*` · `gpu_negative_invert.*` · `gpu_stage_kernels.*` | 커널 래퍼 |
| `gpu/shaders/*.hlsl` · `*.hlsli` | 셰이더 + 공용 조각(`tone_shared` · `hsl_shared` · `film_scan_shared`) |
| `cmake/CompileShaders.cmake` | `fxc` 로 빌드 시 컴파일해 헤더 임베드(`/T cs_5_0 /O3 /Gis /WX /Zpc`) |

### 0.3 남은 것 — 무엇이 왜 막혔는지

> **2026-08-19:** 아래 표는 **2026-08-18 판**입니다. [`15`](15-gpu-handoff.md) 3.1–3.8이
> 닫은 것: 노리츠 질감, 형태학+스크래치 각도(기본 켬), `ditherAdd`(CPU 유지)·클리핑 오버레이,
> `filmGrain`(기본 끔), `CIAreaAverage`(기본 끔), `GpuMipHalve`(기본 끔), 흑백 룩 사슬,
> `box_mean` double(제품 유지·GPU 안 옮김). 죽은 커널 10개는 옮기지 말 것.
> **지금 남은 확인은 [`15`](15-gpu-handoff.md) 4절.** 이 표를 보고 다시 이식하지 마십시오.

| 상태 | 커널 | 왜 |
|---|---|---|
| ☠️ **옮기지 말 것** (4) | `scannerLowSatChroma`·`scannerMidtoneChroma`·`gamutSoftClip`·`highlightDesaturate` | **macOS 활성 파이프라인이 부르지 않습니다.** 옮기면 없는 효과를 만듭니다 |
| **CPU 판부터 없음** (7) | `digitalSceneReconstruct`·`digitalFilmDensity`·`digitalInterImage`·`digitalPrintPaper`·`digitalReversalTransmit`·`digitalToDisplayGamma`·`digitalToLinearLight` | Windows 히트 **0**. GPU 이전에 **CPU 이식이 먼저** |
| **Windows 기능 자체가 없음** (2) | `ditherAdd`·`channelClippingOverlay` | `OutputDither.swift`·`ChannelClippingOverlay.swift` 미이식 |
| **정밀도 확인 필요** (1) | `boundedRelativeGrade` | `scanner_target_grade.cpp:62-64` 안에 박혀 있고 그 안이 **전부 `double`**. float32 로 옮기면 `1e-5` 를 못 지킬 수 있음 |
| ~~선행 조건 남음~~ **막혀 있지 않음** | `filmGrain`·`digitalFilmGrainDensity` | ☠️ **앞 판정 틀림.** 씨앗 규칙은 **이미 정해져 있습니다** — Windows CPU 가 좌표 해시 필드를 쓰고(`digital_film_grain.cpp:25-36`, 전부 uint32) 헤더가 *"statistical, not pixel-exact"* 계약을 명시합니다. 맞출 상대는 Apple 이 아니라 **Windows CPU 필드**입니다 → [`14`](14-remaining-gpu-methodology.md) 0.3·1절 |
| 〃 | `digitalFilmColor` | ☠️ **앞 판정 틀림. 3D LUT 가 필요 없습니다** — `:774` 에 텍스처 샘플링이 **한 줄도 없습니다**(행렬+틴트+hue 6앵커 보간, 완전 화소별). 3D LUT 는 `ScannerTargetGrade` 의 `CIColorCube` 이고 **다른 얘기**였습니다. 진짜 문제는 **Windows 가 다른 알고리즘**이라는 것 → [`14`](14-remaining-gpu-methodology.md) 0.1·2절 |
| 〃 | `noritsuTexture` | ☠️ **앞 판정 틀림.** 이웃 접근은 **이미 해결돼 있습니다** — 입력이 `src`+`blurred` 두 장인 **화소별** 커널이고 `GpuGaussianBlur` 는 delta 0 입니다. 이식한 `digitalHalation` 과 **같은 모양**입니다. CPU 판이 없는 것뿐 → [`14`](14-remaining-gpu-methodology.md) 0.2·3절 |
| **원시연산 남음** | `CIAreaAverage` 대응 | 병렬 리덕션. 히스토그램·자동 보정용 |
| **정밀도 확인 필요** (2) | `grain_mend_morphology.cpp` `box_mean` | 적분영상을 **`double` 로** 누적합니다(`:240`). float32 GPU 로는 그 값을 못 냅니다. D3D11 의 double 은 **선택 기능**(`D3D11_FEATURE_DOUBLES`)이라 내장 GPU 범용성도 보장되지 않습니다. **CPU 를 float 로 내려도 골든이 안 바뀌는지 먼저 재십시오** |

### 0.4 지금 GPU 가 **실제로 도는 곳**과 아직 아닌 것

> #### ✅ 파이프라인에 붙었습니다 (`cb3c9cf`, 형태학은 그 뒤)
>
> | 어디 | 무엇이 GPU 로 | 정책 |
> |---|---|---|
> | `stages/look.cpp` | 톤 7단계(노출·기본 톤·파라메트릭 커브·포인트 커브·믹서·그레이딩·원색 보정) | `GpuUsePolicy::allowed` — **프리뷰·검출만** |
> | `stages/finish.cpp` | `film_scan_denoise` 사슬 | 〃 |
> | GrainMend 검출 안쪽 | **형태학** | ☠️ **기본 꺼짐** — 실측이 더 느렸습니다(아래) |
>
> **형태학만 정책이 없는 이유**: 창 안에서 **하나를 고르는** 일이라 부동소수 산술이 없습니다.
> 창과 가장자리 처리가 같으면 고른 값도 같으므로 CPU 와 **비트 단위로 일치**하고,
> 시험이 전 반경에서 그것을 고정합니다. 그래서 내보내기·골든 경로에서도 켭니다.
>
> 이음매는 `imaging/kernel_accelerator.h` 의 **함수 표**입니다. 의존 방향이 `gpu → imaging`
> 이라 `imaging` 은 `gpu` 를 링크할 수 없어(순환) 표만 알고, 둘 다 링크하는 `pipeline` 이
> `install_gpu_kernel_accelerator()` 로 채웁니다.
>
> ☠️ **표에 곱셈·덧셈이 들어가는 커널을 넣지 마십시오.** 그런 것은 헤더의 "근사한 것" 칸과
> `ApproximateAcceleratorScope` 를 씁니다 — 프리뷰·검출만 그 스코프를 엽니다.

**2026-08-19 이후 — 아래 1·5번은 닫혔습니다.** 형태학+스크래치 각도 기본 켬(검출 4.66s).
`film_scan_denoise` 오케스트레이터는 제품 경로에 있습니다. 전송은 63.5 ms 로 쟀습니다.
**지금 남은 확인은 [`15`](15-gpu-handoff.md) 4절뿐입니다.** 이 목록을 보고 다시 이식하지 마십시오.

옛 판(2026-08-18)이 "아직 아님"으로 적었던 것 — 역사:

1. ~~GPU 형태학 기본 끔~~ → **기본 켬.** RGB 오케스트레이터. [`15`](15-gpu-handoff.md) 3.2
2. ✅ **프리뷰 경로를 쟀고, 최대 단계였던 반전을 붙였습니다.**
   `negaflow-cli --develop-timing` 신설. 5100×3408 실제 스캔:
   `develop`(반전) **353.61 → 261.49 ms(−26%)**, 전체 **856.45 → 782.59 ms(−9%)**.
   반전은 **근사**라 `ApproximateAcceleratorScope`(프리뷰·검출) 안에서만 돕니다 —
   내보내기·골든은 CPU 그대로이고 native 83/83 이 그것을 지킵니다.
   형태학과 반대 결과가 난 이유는 [`13`](13-performance-playbook.md) 16절.
3. ✅ **`tone_adjust` 를 갈라서 뺄 수 있는 것을 뺐습니다** — [`13`](13-performance-playbook.md) 17·18절.
   범인은 다운로드(4 ms)가 아니라 **밴드 측정**이었습니다. 그중 `validate_finite_pixels` 를
   `GpuFiniteCheck`(원자 플래그 + 4바이트 회수)로 옮겨 **tone_adjust 296.88 → 257.95 ms(−13%)**,
   전체 **782.59 → 735.20 ms**. CPU 기준으로는 911.35 → 735.20 = **−19%**.
   ☠️ 18절에 **제 앞 판정이 틀렸던 것**도 적었습니다 — 밴드 측정은 `downsample_for_statistics` 를
   부르지 않고 `double` 면적평균을 직접 돕니다. `GpuMipHalve` 는 자동 베이스·장면밀도·
   바이브런스 쪽 원시연산이고, 비트 단위 일치는 그대로 유효합니다.
   남은 `double` 면적평균은 **옮길 수 없습니다** — D3D11 의 double 은 선택 기능입니다.
4. 4방향 실측(CPU/GPU × 커브 켬/끔) 전체 표도 17절에 있습니다.
5. ☠️ **밴드 표본 루프 — 앞서 두 번 "병렬화해도 이득 없음" 이라고 적은 것이 틀렸습니다.**
   `work_units` 에 표본 격자 크기(38,232)를 넘겨 `minimum_parallel_row_work_units`(100만)
   문턱에 걸렸고, **병렬화가 아예 안 걸린 상태**를 "병렬" 이라고 부르며 쟀습니다.
   진짜 작업량(격자 × `ceil(inverse_scale)²` ≈ **1,686만**)을 넘기니 16블록으로 쪼개지고
   **32.0 → 5.0 ms (6.4배)**, `tone_adjust` 중앙값 **290.3 → 276.1 ms** 입니다.
   native 83/83 통과 — 값은 비트 단위로 같습니다.
   무엇을 어떻게 틀렸는지는 [`13`](13-performance-playbook.md) **21절**(19·20절 폐기).
2. **내장 GPU 실기 확인을 못 했습니다.** 이 기계에 Intel/AMD 내장이 없습니다.
   범용성은 **코드 구조로만** 보장돼 있습니다(벤더 ID 로 거르는 코드 0줄, FL 11_0 공통 하한,
   `DXGI_ADAPTER_FLAG_SOFTWARE` 만 제외, WARP 폴백).
3. **전송 대역폭을 재지 않았습니다.** 3절의 384 MB 는 산술입니다.
4. **형태학 가속이 평면마다 왕복합니다.** 검출은 평면을 여러 번 훑는데 지금은 호출마다
   업로드·다운로드를 합니다. 검출 전체를 GPU 에 머무르게 하려면 오케스트레이터가 필요합니다 —
   3절의 "단계마다 올렸다 내리면 집니다" 가 여기에도 그대로 적용됩니다.
5. ~~`film_scan_denoise` 오케스트레이터가 시험 안에만~~ → **제품 경로에 있음.**
   `gpu_film_scan_stage.cpp` → `gpu_accelerator.cpp` → `stages/finish.cpp`

### 0.5 ☠️ GPU 도 CPU 와 **같은 타일**로 나눠야 값이 같습니다 (2026-08-18 실측)

`film_scan_denoise` 를 이식하며 **재서** 확정한 것입니다. 이것은 성능 선택이 아니라
**값의 조건**입니다.

박스 블러는 러닝 섬이라 **수학적으로는 창 안만 보지만 수치적으로는 그 행의 0번 화소부터
누적한 반올림을 들고 옵니다.** CPU 는 512px 타일마다 그 행의 0에서 새로 시작하고, 전체를
한 번에 도는 GPU 는 이미지의 0에서 시작합니다 — 같은 화소에서 누적 이력이 달라집니다.

에이프런 18 은 **필터 지원**(가우시안 4 + 가이드 7 + 7)으로는 충분합니다.
모자란 것은 지원이 아니라 **누적 이력**입니다.

| 어떻게 돌렸나 | 최대 오차 | 최악 화소 |
|---|---:|---|
| 폭 400(타일 하나) 전체 한 번에 | 1.2e-07 | — |
| 폭 600(경계 512 지남) 전체 한 번에 | **4.3e-05** | x=531·534·580 — **전부 경계 너머** |
| 폭 600, CPU 와 같은 512/18 타일 | **1.2e-07** | — |

부수 효과로 메모리 문제도 풀립니다 — 전체를 한 번에 돌면 중간 텍스처 13장이 24MP 에서
**5 GB** 인데, 530×530 타일이면 **58 MB** 입니다. 8절의 "타일 분할 필수" 와 같은 결론에
**다른 이유로** 도착한 것입니다.

### 0.6 ☠️ `pow` 는 CPU 와 마지막 비트가 같을 수 없고, 이 사슬이 그것을 키웁니다

CPU 가 계산한 감마 리프트를 그대로 올리면 나머지 사슬 전체가 **1.2e-07** 로 맞습니다.
GPU `pow` 를 쓰면 **2.1e-05 ~ 6.2e-05** 가 됩니다. 리프트 자체의 차이는
**1 ulp(WARP 5.96e-08) · 2 ulp(NVIDIA 1.19e-07)** 뿐입니다.

키우는 것은 가이드 필터의 `1 / (variance + 0.001)` 입니다 — `variance` 가
`mean(guide²) − mean(guide)²` 라 평탄한 곳에서 **자리수가 거의 다 상쇄됩니다.**
macOS 도 같은 식이므로 이것은 **이식이 만든 문제가 아니라 알고리즘의 조건수**입니다.

HLSL `pow` 는 `exp2(y * log2(x))` 이고 D3D11 은 그 둘에 각각 상대오차 2^-21 을 허용합니다.
`std::pow` 와 같게 만들 방법이 표준 안에 없습니다. 고치려면 HLSL 에 double-float 로 `pow` 를
직접 써야 하고 그 자체로 검증이 필요합니다 — **하지 않았습니다.**
출처: [Floating-point rules](https://learn.microsoft.com/en-us/windows/win32/direct3d11/floating-point-rules)

### 0.7 이식하면서 시험이 잡은 실제 버그 5개

**동치 시험이 없었으면 전부 조용히 틀린 채로 갔을 것들입니다.**

| 무엇 | 증상 | 원인 |
|---|---|---|
| `colorMixerHSL` | delta **0.1** | CPU 는 "변화 없음" 이면 커널을 안 돌리고 **원본을 복사**합니다. GPU 가 커널을 돌려 HSL 왕복이 [0,1] 밖 값을 클램프했습니다 |
| 박스 블러 | delta **0.38** | HLSL `cbuffer` 에 `Extent` 뒤 `float2` 패딩을 안 적어 `Radius` 가 **8바이트 앞에서** 읽혔습니다. 컴파일·실행·경고 전부 통과하고 값만 틀립니다 |
| `basicTone` whites/blacks | 범위 밖 요청이 **통째로 거부** | Windows 가 macOS 의 ±2 대신 ±1 로 막고 있었고 clamp 도 없었습니다 — 엔진부터 슬라이더까지 7곳을 고쳤습니다 |
| 박스 블러 (2차) | 가이드 필터 delta **3.8e-05** | **CPU `box_blur` 가 두 벌이고 누적 괄호가 다릅니다** — `float` 판은 `sum + (a-b)`, `Rgb` 판은 `(sum + a) - b`. 시험 참조도 GPU 도 한 순서로 통일해 두어 **둘 다 실제 CPU 와 달랐습니다.** `blur_alpha=true` 경로에 시험이 아예 없어서 통과했습니다 |
| `CompileShaders.cmake` | 조용한 스테일 | `.hlsl` 만 의존으로 걸어 **`.hlsli` 조각을 고쳐도 다시 컴파일되지 않았습니다** |

규칙으로 박아 둔 것: [`13`](13-performance-playbook.md) 12절(조기 반환) · 13절(상수 버퍼 배치) ·
14절(러닝 섬 순서) · 15절(누적 이력과 타일) · 16절(초월함수).

### 0.8 착수 전 상태 (2026-08-18 이전) — **역사. 지금 GPU 0줄이 아님**


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

| macOS 내장 필터 | 쓰이는 곳 | Windows 에서 만들 것 | 상태 |
|---|---|---|---|
| `CIGaussianBlur` | `ColorModel.swift:128,166` · `FilmScanDenoise.swift:96` · `LocalDodgeBurnStage.swift:169` · `ScannerNoiseReduction+Color.swift:19` | **분리형 가우시안** — 수평 1D + 수직 1D | ✅ `gaussian_blur.hlsl`. **delta 0**. `groupshared` 타일 캐시는 아직 — 재고 나서 |
| `CIBoxBlur` | `FilmScanDenoise.swift:154` | **분리형 박스** — 슬라이딩 윈도우로 화소당 O(1) | ✅ `box_blur.hlsl`. **delta 0** |
| `CIMedianFilter` (3×3) | `FilmScanDenoise.swift:171` | **3×3 중앙값** — 9원소 정렬 네트워크 | ✅ `median3.hlsl`. **delta 0** — 부동소수 산술이 없어 고른 값이 같습니다 |
| `CIAreaAverage` | 히스토그램·자동 보정 | **병렬 리덕션** | ❌ 아직 |
| `CIRandomGenerator` | 그레인·디더 노이즈 | **결정적 해시 노이즈.** macOS 와 화소값까지 맞춰야 하면 **씨앗 규칙부터 대조** | ❌ 아직 |
| `CIVibrance` | `ColorModel` | **이미 CPU 로 이식돼 있음** — Apple 비공개 커널이라 33³ LUT 로 측정 이식(`muted_scene_vibrance_table.cpp` 9,003줄). GPU 에서는 `Texture3D` + `SampleLevel` **한 번**. **GPU 이득이 가장 큰 곳 중 하나** | ❌ 아직 |

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

> ### ✅ 2026-08-19 — **쟀습니다.** `negaflow-cli --gpu-transfer-bench` 신설
>
> 5088×3401(264 MB), RTX 4060 Ti, 6회 중앙값. 같은 이미지에 반전 커널을 한 번 얹어
> **전송 대 커널** 비율도 같이 봤습니다.
>
> | | 처음 | 스테이징 재사용 | + 병렬 회수 복사 | + 쓰기 스테이징 |
> |---|---:|---:|---:|---:|
> | 업로드 | 45.2 ms | 42.3 | 44.1 | **8.2 ms** |
> | 커널 디스패치 | 0.01 ms | 0.01 | 0.01 | **0.01 ms** |
> | 다운로드 | 98.9 ms | 78.0 | 61.9 | **55.3 ms** |
> | 왕복 | 145.0 ms | 122.0 | 105.9 | **63.5 ms** |
> | 실효 대역폭 | 3.5 GB/s | 4.2 | 4.9 | **8.1 GB/s** |
>
> ☠️ **커널 디스패치가 0.01 ms 입니다.** 24MP 반전은 화소마다 `log10`·`pow`·`exp` 를
> 도는 가장 비싼 화소별 커널인데도 그렇습니다(디스패치는 비동기라 이 숫자는 큐에 넣는
> 시간이고, 실제 계산은 다운로드의 동기화 대기에 섞여 있습니다). **이 문서가 "전송이
> 지배한다" 고 적은 것은 맞았고, 그 정도가 예상보다 큽니다.**
>
> 처음의 145 ms 는 셋이 겹친 것이었습니다 — 모두 **커널이 아니라 살림**입니다:
> ① 다운로드마다 264 MB 스테이징을 만들고 지웠고, ② 회수 복사가 한 스레드였고,
> ③ 업로드가 `UpdateSubresource`(드라이버 한 스레드 복사)였습니다.
>
> 그리고 진입점 여덟이 **작업 텍스처를 호출마다 만들고 있었습니다.** `GpuImagePool`
> 여섯 장을 가속기가 들고 전부 나눠 쓰게 했습니다.
>
> **내장 GPU 는 여전히 미확인입니다** — 시스템 메모리를 공유하므로 이 숫자가 그대로
> 적용되지 않습니다.

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

**2026-08-19:** 프리뷰는 더 이상 풀해상도로 현상한 뒤 `write_preview` 만 줄이지 않습니다.
`preview_proxy_materialize` 가 결함·베이스 이후 Lanczos3 로 상자에 맞추고, 인터랙티브/정착
두 슬롯에 raw 를 둡니다. 5088×3401 · 상자 1280 두 번째 `develop_preview` **43.1 ms**, decode 0.
CLI `--develop-timing` 3600 마지막 회차 GPU **291 ms**(develop 86.8 · tone 72.6). CPU 마지막 **490 ms**.
앱 슬라이더 벽시계는 설치본에서 확인 중.

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

> ### 2026-08-19 — 형태학은 제품 경로에 붙었고 기본 켭니다
>
> 커널 반경 0·1·3·4·8·12 WARP·NVIDIA **delta 0**. RGB 오케스트레이터 + 스크래치 각도 GPU.
> 검출 17.3s → **4.66s**, 610/9331. 끄려면 `NEGA_GPU_MORPHOLOGY=0` / `NEGA_GPU=0`.
> 상세 [`15`](15-gpu-handoff.md) 3.2.
>
> ⚠️ GPU 셰이더는 화소당 **O(r)** 로 창을 직접 훑습니다. 반경이 12 이하라 고른 선택이고,
> 반경 무관 O(1) 로 바꾸는 것은 성능 작업입니다 — **재고 나서** 하십시오.
>
> ☠️ `box_mean` 은 **옮기지 않았습니다.** 적분영상을 `double` 로 누적합니다(`:240`).
> D3D11 의 double 은 선택 기능이라 내장 GPU 범용성이 보장되지 않습니다.

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
| **타일은 성능이 아니라 값의 조건** | `film_scan_denoise` 는 GPU 도 **CPU 와 같은 512/18 타일**로 나눠야 값이 같습니다 — 러닝 섬의 누적 이력 때문입니다(0.5절 실측) | 이 단계의 GPU 오케스트레이터는 `make_tile` 을 그대로 씁니다. 다른 단계도 러닝 섬을 쓰면 같은 규칙입니다 |
| **초월함수** | HLSL `pow`·`exp`·`log` 는 `std::pow` 와 마지막 비트가 다릅니다(D3D11 이 상대오차 2^-21 을 허용) | 조건수가 큰 사슬 앞에 있으면 수백 배로 커집니다(0.6절). **재서 적을 것** — 못 맞추면 "다르다" 고 적습니다 |
| **내장 GPU 메모리** | 내장은 시스템 메모리를 나눠 씁니다. float32 RGBA 는 화소당 16바이트 | 타일 + 핑퐁 2장까지만. 상한 초과 시 CPU 폴백 |
| **드라이버별 부동소수** | 최적화 재배열로 벤더마다 값이 갈릴 수 있음 | `/Gis` + `precise`. 동치 시험이 벤더별로 다르게 깨지면 **여기부터** 봅니다 |
| **노이즈 재현성** | `CIRandomGenerator` 를 대체하면 그레인 무늬가 macOS 와 달라짐 | 씨앗 규칙을 먼저 대조. 못 맞추면 **"다르다" 고 적을 것** |
| **half vs float** | 1.2절 — macOS 는 half, 우리는 float32 | 이번 작업에서 건드리지 않음. **별건으로 남김** |
| ☠️ **상주 범위 수명** | `GpuResidentScope` 는 소멸자에서 `flush_resident()` 로 **호스트 버퍼에 내려씁니다.** 그 버퍼보다 **뒤에 선언**하면 C++ 소멸 역순 때문에 **이미 죽은 메모리**에 씁니다 — 2026-08-20 앱 강제 종료의 원인이 이것이었습니다(`develop_export.cpp`) | **상주 범위는 그것이 채우는 출력보다 먼저 선언합니다.** 새 단계를 붙일 때마다 이 순서를 확인하십시오. [`01`](01-backend-gaps.md) 9.1 |

---

## 9. 아직 모르는 것 (정직하게)

1. ~~단계별 ms~~ — `--develop-timing` 으로 잰다. [`16`](16-preview-handoff.md)
2. ~~업로드/다운로드 대역폭~~ — 264 MB 왕복 **63.5 ms · 8.1 GB/s**. **내장 GPU 는 미확인.**
3. **사용자 최대 스캔 크기** — 16384 한계에 걸리는지 미확인.
4. **앱 슬라이더 벽시계** — CLI 는 쟀고 앱은 못 잼.
5. **GPU 타일 크기** — `film_scan_denoise` 는 512/18 고정.
6. **`pow` 를 double-float 로 맞출 수 있는지** — 시도하지 않음.
7. `native.gpu_film_scan` 간헐 SEGFAULT 가 **정말** 상주 범위 수명 때문이었는지 —
   고친 뒤 55회 연속 통과지만 실패 스택을 못 잡아 **단정하지 않습니다**([`01`](01-backend-gaps.md) 9.4).
