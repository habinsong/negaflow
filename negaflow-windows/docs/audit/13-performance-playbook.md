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

# 13 — 성능·품질 플레이북

> **사용자 요구:** 자동 검출 **5초 미만**, 가이드·브러시·복제·IR **즉시**,
> 우측 슬라이더 **즉시**, 프리뷰 **즉시**. 그리고 **품질은 떨어뜨리지 않고.**

[`04-gpu-plan.md`](04-gpu-plan.md) 가 **무엇을 GPU 로 옮길지**를 다룹니다.
이 문서는 **어떻게 빠르게 만들지** — GPU 밖의 것까지 포함해서 — 를 다룹니다.

> ⚠️ **이 문서의 "기대" 는 전부 기대입니다.** 실제 수치는 재서 채워야 합니다.
> **재기 전에는 "빨라졌다" 고 적지 마십시오.**

---

## 0. 제1원칙 — 재고 나서 가장 큰 것부터

**지금 이 저장소에는 단계별 시간 계측기가 없습니다.**
`src/Native/pipeline/` 전체에서 `elapsed` · `duration_ms` · `stage_ms` **히트 0**.

가진 측정값은 이것뿐입니다(`plan/02-grainmend-performance.md`, 2026-08-17,
`OpticFilm8100_frame_4.tiff` 5088×3401, x64 Release, 10코어/16스레드):

| 이미 잰 것 | 값 |
|---|---:|
| TIFF 디코드 + ICC → linear | **2,695 ms** |
| GrainMend 자동 검출 | **8,932 ms** |
| └ 먼지 형태학 | 14,990 ms (CPU 합계, **47%**) |
| └ 미세 입자 | 11,135 ms (**35%**) |

**현상·보정·룩·인화 단계는 하나도 재지 않았습니다.** 사용자가 "우측탭 뭘 써도 수 초"
라고 한 그 구간의 내역을 우리는 **모릅니다.** 그러니 0단계는 GPU 가 아니라 계측입니다.

---

## 1. 이 저장소의 현재 상태 — 2026-08-18 실측

| 항목 | 측정 방법 | 결과 | 뜻 |
|---|---|---|---|
| GPU 코드 | 10개 키워드로 `src/` 전수 | **2026-08-18 착수함**(`aa0d59f`) — `src/Native/gpu/` 4파일 + `basic_tone.hlsl`. 착수 전에는 히트 0 이었음 | [`04`](04-gpu-plan.md) 0절 |
| **SIMD** | `__m128`·`__m256`·`_mm_`·`immintrin` | **히트 11, 전부 `flatbed_frame_*` 3파일** | **화소 파이프라인에 SIMD 가 없습니다** |
| **스레드 풀** | `src/Native/core/parallel_rows.cpp:113` | 호출마다 `std::thread(...)` **새로 생성** | **영속 풀이 없습니다** |
| 컴파일러 최적화 | `CMakeLists.txt` **와** `cmake/CompilerWarnings.cmake` 전수 | **`/fp:precise` 는 있음**(명시). `/arch:` · `/GL` · `/LTCG` 는 **없음** (Release 기본 `/O2` 만) | `/GL`+`/LTCG` 를 안 켰습니다 |
| 관리 쪽 버퍼 | `ArrayPool` | **히트 0** 전 트리 | 단 `PreviewCoordinator.cs:112` 는 버퍼를 **미리 한 번** 잡습니다 — 여긴 문제 없음 |
| 프리뷰 표시 | `DevelopPreviewCanvas.Present()` | `PixelBuffer.AsStream()` 으로 **프레임 전체 복사** | 3600×2400 이면 프레임당 **34.6 MB** 복사 |
| 단계별 ms | 위 0절 | **없음** | 기준선 없음 |

**이 표의 2·3·4행은 GPU 를 붙이기 전에도 오늘 당장 할 수 있는 것들입니다.**

---

## 2. 0단계 — 계측기부터

### 2.1 네이티브 단계별 시간

`develop_export_detail::RunTracker` 에 단계별 소요를 넣습니다.
`develop_export_stage_name()` 이 이미 있으니 이름은 그대로 씁니다.

- `QueryPerformanceCounter` 로 재고, 결과를 `DevelopExportOutcome` 에 실어 올립니다.
- CLI 로 덤프: `negaflow-cli --develop-timing <source>` (새 명령).
- **릴리스에서도 켤 수 있어야 합니다.** 개발자 모드에서만 보이면 사용자 기계의 느림을 못 잡습니다.

### 2.2 GPU 시간

`ID3D11Query` `D3D11_QUERY_TIMESTAMP` + `TIMESTAMP_DISJOINT` 로 커널별 GPU 시간을 잽니다.
**CPU 벽시계와 따로 잽니다** — 디스패치는 비동기라 벽시계로는 안 보입니다.

### 2.3 전송 대역폭

업로드/다운로드 실측을 한 번 재서 [`04`](04-gpu-plan.md) 3절의 빈칸을 채웁니다.
**내장 GPU 와 외장이 다릅니다.** 둘 다 재십시오.

### 2.4 무엇을 기록하나

커널·단계마다 **이전 ms / 이후 ms** 를 **커밋 메시지에** 적습니다.
적지 않은 최적화는 다음 사람이 되돌립니다.

---

## 3. GPU 없이 오늘 할 수 있는 것

### 3.1 스레드 풀 — `parallel_rows.cpp` 가 호출마다 스레드를 만듭니다

```cpp
// src/Native/core/parallel_rows.cpp:113
workers[started] = std::thread(
    [function, context, block]() noexcept { … });
```

화소 단계마다, 타일마다 이것이 돕니다. 슬라이더를 끄는 동안에는 **초당 수십 번**입니다.

**할 것**: 영속 워커 풀 하나(장치 수명과 같이). 작업은 큐에 넣고 스레드는 살려 둡니다.
**주의**: 지금 코드는 스레드 생성 실패 시 인라인 실행으로 복구합니다(`catch (...)`).
**그 복구 경로를 없애지 마십시오** — 풀이 포화일 때 같은 역할을 합니다.

> ⚠️ **얼마나 빨라지는지는 재야 압니다.** 스레드 생성 비용은 Windows 에서 수십 µs 급이라
> 큰 이미지 한 장에는 묻히고, **작은 프록시를 초당 수십 번 돌릴 때** 드러납니다.
> **프록시 크기에서 재십시오.**

### 3.2 컴파일러 스위치 — 켤 수 있는 것을 안 켰습니다

`cmake/CompilerWarnings.cmake` 는 `/W4 /WX /permissive- /Zc:__cplusplus /Zc:preprocessor /utf-8`
**`/fp:precise`** `/sdl /guard:cf` 를 겁니다. **`/fp:precise` 는 이미 명시돼 있습니다.**
없는 것은 **`/arch:` · `/GL` · `/LTCG`** 셋입니다.

| 스위치 | 효과 | ☠️ 위험 |
|---|---|---|
| `/GL` + `/LTCG` | 링크 시 최적화. 인라인이 파일 경계를 넘음 | 낮음. 빌드 시간만 늘어남 |
| `/fp:fast` | 부동소수 재배열 허용 | **높음. 절대 그냥 켜지 마십시오** — 골든값이 바뀝니다 |
| `/fp:precise` | **이미 켜져 있음**(`cmake/CompilerWarnings.cmake:12`). 유지할 것 | — |
| `/arch:AVX2` | 벡터 명령 + **FMA 축약** | **중간~높음.** FMA 로 반올림이 달라져 골든이 흔들릴 수 있음 |

**규칙: 스위치를 켤 때마다 골든 시험(`2026-08-16-macos-pixel-golden.md`)과 실측 17장 dmin 을 돌리십시오.**
바이트가 바뀌면 **그 스위치는 성능이 아니라 품질 변경**입니다. 값이 바뀌었는데 "빨라졌다" 고
보고하면 그게 구라입니다.

`/GL`+`/LTCG` 부터 하십시오 — **값을 안 바꾸면서 얻는 것**입니다.

### 3.3 SIMD — 화소 커널에 하나도 없습니다

지금 SIMD 는 `flatbed_frame_grid_fit.cpp` · `flatbed_frame_grid_types.h` ·
`flatbed_frame_profiles.cpp` **3파일뿐**입니다. 톤·커브·믹서·그레이딩·반전은 전부 스칼라입니다.

**그런데 이것들은 [`04`](04-gpu-plan.md) 의 GPU 이식 대상과 정확히 같습니다.**

**판단: GPU 가 먼저입니다.** 같은 커널을 SIMD 로 한 번, HLSL 로 또 한 번 쓰는 것은 낭비이고,
**두 벌이 되면 서로 어긋납니다.** SIMD 는 **GPU 폴백 경로가 확정된 뒤**, GPU 없는 기계를 위해
넣으십시오. 그때는 이미 커널 수식이 HLSL 로 정리돼 있어 옮기기 쉽습니다.

### 3.4 메모리

- `ArrayPool` 히트 0이지만 **프리뷰 경로는 이미 선할당**(`PreviewCoordinator.cs:112`)이라 급하지 않습니다.
- 진짜 문제는 **네이티브 쪽 `WorkingImage` 복사**입니다. 단계 시그니처를 보면
  `apply_finish_stages(… WorkingImage grain_image …)` 처럼 **값으로 받는** 곳이 있습니다.
  24MP 면 한 번에 **384 MB 복사**입니다. **전부 열어서 값/참조를 확인하십시오.**
- 메모리 압력은 `CreateMemoryResourceNotification` 으로 감지합니다([`10`](10-cache-and-optimization.md) FIFO 캐시).

---

## 4. GPU 커널 작성 규칙 — [`04`](04-gpu-plan.md) 보완

04 는 **무엇을** 옮길지, 여기는 **어떻게** 씁니다.

### 4.1 스레드 그룹

| 규칙 | 값 | 근거 |
|---|---|---|
| 그룹 크기는 **64의 배수** | `[numthreads(8,8,1)]` = 64 부터 | 모든 벤더에서 무난. AMD wave64 · NVIDIA warp32 둘 다 나눠떨어짐 |
| D3D11 그룹당 최대 | **1024 스레드** | |
| `groupshared` 상한 | **32 KB / 그룹** (D3D 제한) | float4 로 2,048개 = 45×45 타일 정도 |

**주의**: 큰 그룹은 점유율(occupancy)을 떨어뜨릴 수 있습니다 — 레지스터·LDS 를 많이 먹으면
동시에 도는 그룹 수가 줄어듭니다. **8×8 로 시작해서 재고 올리십시오.**

### 4.2 분리형 컨볼루션 — 가우시안·박스

1. 수평 1D 패스 → 중간 텍스처 → 수직 1D 패스.
2. 각 패스에서 **커널 반경만큼 넓은 타일을 `groupshared` 에 미리 읽고**, 거기서 곱합니다.
   같은 화소를 반경 배로 다시 읽지 않게 됩니다.
3. 박스 필터는 **슬라이딩 윈도우로 화소당 O(1)** — 반경과 무관합니다.

### 4.3 형태학 — 반경과 무관한 O(1)

**먼지 형태학이 검출 CPU 의 47%, 미세 입자까지 82%** 입니다. 여기가 가장 큰 덩어리입니다.

**van Herk / Gil-Werman (vHGW)**: 구조 요소 크기와 **무관하게** 화소당 상수 시간
(비교 3n)으로 최소/최대를 구합니다. 침식·팽창은 **분리 가능**하므로 수평·수직 두 패스로 갑니다.
CUDA 구현 논문이 있고 원리는 API 무관이라 HLSL 로 옮길 수 있습니다.

**주의**: 45° 같은 사선 구조 요소는 별도 취급이 필요합니다.
**지금 `grain_mend_morphology.cpp` 가 어떤 구조 요소를 쓰는지 먼저 읽으십시오.**

### 4.4 가이드 필터 — 이미 O(1) 형태

macOS 커널 `gfProduct`·`gfCoeffA`·`gfCoeffB`·`gfApply` 4단은 **박스 필터 기반 가이드 필터**입니다.
가이드 필터는 **창 크기에 무관한 O(1)** 이 원 논문 성질이고, 박스 평균만 O(1)로 만들면 됩니다
(적분 영상 또는 4.2의 슬라이딩 윈도우).

**즉 4개 커널 자체는 화소별이고, 그 사이의 박스 평균만 우리가 만들면 됩니다.**

### 4.5 다운로드 — 여기서 멈춥니다

**D3D11 의 `Map` 은 동기화합니다.** 스테이징 텍스처를 `Map` 하면 GPU 가 밀린 작업을 끝낼 때까지
CPU 가 **멈춥니다.** (D3D12 와 다른 점입니다.)

**할 것: 스테이징 텍스처를 2장 이상 두고 돌려 씁니다.** N 프레임을 GPU 가 쓰는 동안
N−1 프레임을 CPU 가 읽습니다. 이렇게 안 하면 프리뷰가 매 프레임 GPU 를 기다립니다.

### 4.6 캐시 지역성

넓게 흩어져 읽는 패스(디노이저 같은 큰 커널)는 **스레드그룹 타일링**으로 L2 지역성을 올립니다.
그룹 ID 를 재배열해 인접 그룹이 인접 메모리를 보게 합니다.
**이건 마지막 손질입니다** — 4.1~4.5 부터 하십시오.

---

## 5. 품질을 지키면서 — 이게 진짜 어려운 부분

**빨라졌는데 값이 바뀌었으면 실패입니다.**

| 지킬 것 | 어떻게 |
|---|---|
| CPU/GPU 동치 | 커널마다 같은 입력으로 비교, 허용 오차 **1e-5**. 시험 이름에 커널 이름 |
| 골든 이미지 | `verification/2026-08-16-macos-pixel-golden.md` 의 기준값 |
| 실측 17장 dmin | 필름 베이스 경로 — **바이트까지 동일**해야 함 |
| WARP | `D3D_DRIVER_TYPE_WARP` 로 하드웨어 없이 CI 에서 |
| 드라이버 편차 | `/Gis` + `precise`. **벤더마다 다르게 깨지면 여기부터** |
| 노이즈 재현성 | `CIRandomGenerator` 대체는 씨앗 규칙부터 대조. 못 맞추면 **"다르다" 고 적을 것** |

**측정 절차 고정** — 안 그러면 숫자를 못 믿습니다:

1. x64 **Release**, 같은 원본 파일, 같은 해상도.
2. **워밍업 1회 버리고** 3회 이상, 중앙값.
3. 다른 빌드·다른 앱이 동시에 돌지 않게. (앞서 catalog 시험 2개가 이것 때문에 흔들렸습니다.)
4. 내장/외장 GPU 를 **따로** 기록.

---

## 6. 프론트엔드 성능

| 항목 | 지금 | 할 것 |
|---|---|---|
| `DevelopPreviewCanvas.Present()` | `PixelBuffer.AsStream()` 으로 **프레임 전체 복사**. 3600×2400 = **34.6 MB/프레임** | 크기 안 바뀌면 `WriteableBitmap` 재사용은 **이미 하고 있음**(잘 돼 있음). 남은 것은 복사 자체 — 바뀐 사각형만 쓰거나, GPU 경로가 서면 `IDirect3DSurface`/`SurfaceImageSource` 로 **복사 없이** |
| 프리뷰 프록시 | `DevelopPreviewProxy.cs` 로 macOS 상수 이식됨(1024…3600, 256 양자화, 0.14초 정착) | **앱에서 ms 를 안 쟀습니다** |
| 슬라이더 드래그 | 매 틱 전체 파이프라인 | 인터랙티브 프록시 + 정착으로 흡수 — [`04`](04-gpu-plan.md) 6.1 |

> ⚠️ **34.6 MB 는 산술입니다.** 이 복사가 실제로 몇 ms 인지, UI 스레드를 얼마나 잡는지
> **재지 않았습니다.** 재고 나서 손대십시오.

---

## 7. 순서

| # | 할 일 | 왜 이 자리 | 값이 바뀌나 |
|---|---|---|---|
| 0 | **계측기**(2절) | 기준선이 없음 | 아니오 |
| 1 | `/GL` + `/LTCG`(3.2) | 값 안 바꾸고 얻는 것 | **아니오 — 확인할 것** |
| 2 | 프리뷰 프록시 ms 측정 | 이미 이식됨, 효과 미확인 | 아니오 |
| 3 | 스레드 풀(3.1) | GPU 폴백 경로에도 계속 쓰임 | 아니오 |
| 4 | GPU 뼈대 + 가용성 + WARP | — | 아니오 |
| 5 | **화소 커널**(04 1.3) | 우측 슬라이더 체감의 전부 | **1e-5 안에서만** |
| 6 | **형태학 vHGW**(4.3) | 검출 82% | **1e-5 안에서만** |
| 7 | 이웃 원시연산(4.2·4.4) | 디노이즈·닷지번·할레이션 | **1e-5 안에서만** |
| 8 | 더블 버퍼 다운로드(4.5) | 커널이 서야 의미 있음 | 아니오 |
| 9 | 표시 경로 복사 제거(6절) | GPU 경로가 선 뒤 | 아니오 |
| 10 | SIMD 폴백(3.3) | GPU 확정 후 | **1e-5 안에서만** |
| 11 | 스레드그룹 타일링(4.6) | 마지막 손질 | 아니오 |

---

## 8. 아직 모르는 것

1. **현상·보정·룩·인화 단계별 ms** — 안 쟀습니다. 사용자가 느리다고 한 그 구간입니다.
2. **업로드/다운로드 실제 대역폭** — 내장/외장 둘 다.
3. **이 기계의 GPU 와 기능 수준** — 안 찍었습니다.
4. **`Present()` 복사의 실제 ms** — 34.6 MB 는 산술.
5. **스레드 생성 비용의 실제 비중** — 프록시 크기에서 재야 함.
6. **`grain_mend_morphology.cpp` 의 구조 요소 모양** — vHGW 적용 가능 여부가 여기 달림.
7. **`WorkingImage` 를 값으로 받는 단계가 몇 개인지** — 전수 확인 안 함.

---

## 9. 출처

- [Optimizing GPU occupancy and resource usage with large thread groups — AMD GPUOpen](https://gpuopen.com/learn/optimizing-gpu-occupancy-resource-usage-large-thread-groups/)
- [Compute Shader Overview — Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-compute-shader)
- [Compute Shaders on Downlevel Hardware — Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-devices-downlevel-compute-shaders)
- [D3D11_FEATURE_DATA_D3D10_X_HARDWARE_OPTIONS — Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/ns-d3d11-d3d11_feature_data_d3d10_x_hardware_options)
- [Optimizing Compute Shaders for L2 Locality using Thread-Group ID Swizzling — NVIDIA](https://developer.nvidia.com/blog/optimizing-compute-shaders-for-l2-locality-using-thread-group-id-swizzling)
- [High Performance Post-Processing — NVIDIA GDC 2011](https://www.nvidia.com/content/pdf/gdc2011/nathan_hoobler.pdf)
- [Parallel van Herk/Gil-Werman image morphology on GPUs using CUDA — NVIDIA GTC](https://www.nvidia.com/content/gtc/posters/14_domanski_parallel_vanherk.pdf)
- [Efficient dilation, erosion, opening, and closing algorithms — IEEE](https://ieeexplore.ieee.org/document/1114852/)
- [Removing CPU-GPU sync stalls — Intel](https://www.intel.com/content/www/us/en/developer/articles/case-study/removing-cpu-gpu-sync-stalls-in-galactic-civilizations-3.html)
- [D3D11 Texture Update Costs — eatplayhate](https://eatplayhate.me/2013/09/29/d3d11-texture-update-costs/)
- [Guided Image Filtering (OpenCL 구현) — GitHub](https://github.com/nlamprian/GuidedFilter)

---

## 10. 착수 기록 (2026-08-18, `aa0d59f`)

| 한 것 | 실측 |
|---|---|
| `src/Native/gpu/` 기반 4파일 + `cmake/CompileShaders.cmake` | 이 기계 **RTX 4060 Ti, FL 11_1, VRAM 7949MB** |
| 텍스처 왕복(업로드/다운로드, 행 피치 다름) | WARP·NVIDIA 양쪽 **비트 단위 일치** |
| `basicTone` 커널 CPU/GPU 동치 | WARP **1.8e-07~6.0e-07** · NVIDIA **3.6e-07~7.7e-07** (허용 1e-5) |
| 4.1 스레드 그룹 | `[numthreads(8,8,1)]` = 64. 셰이더와 `gpu_basic_tone.cpp` 의 상수를 **같이** 바꿔야 함 |
| 4.5 더블 버퍼 다운로드 | `GpuStagingRing` 으로 구현. 깊이 1을 요청해도 2로 올림 |
| `/Gis` | fxc 플래그에 넣음 |

**아직 안 한 것 (정직하게):**

1. **파이프라인 연결 안 됨.** 커널은 시험에서만 돕니다. `stages/look.cpp` 는 여전히 CPU 만 부릅니다.
2. **속도를 안 쟀습니다.** 동치만 증명했지 **빨라졌는지는 모릅니다.** 계측기(2절)가 먼저입니다.
3. **내장 GPU 실기 확인 못 함.** 이 기계에 Intel/AMD 내장이 없습니다. 범용성은 **코드 구조로만** 보장돼 있습니다.
4. 커널 1개 / 대상 32개 중.

## 11. 이식하다 발견한 CPU 차이 — `basicTone` whites/blacks

macOS `basicTone` 은 **커널 안에서** 두 값을 clamp 합니다:

```metal
target += clamp(whitesAmount, -2.0, 2.0) * 0.12 * whiteMask;
target += clamp(blacksAmount, -2.0, 2.0) * 0.06 * blackMask;
```

**Windows 에는 그 clamp 가 없습니다.** `imaging/tone_mapping.cpp` `apply_basic_tone` 에도,
관리 쪽(`Shell.Core/Develop/`·`Interop/`)에도 히트가 없습니다.
macOS `DevelopToneRange.whites/blacks` 는 `-2...2` 입니다.

**GPU 커널은 CPU 를 따르게 뒀습니다** — GPU 만 고치면 CPU/GPU 동치 시험이 무의미해집니다.
**어느 쪽을 맞출지는 별건이고, 고칠 때 CPU·GPU 를 같이 고쳐야 합니다.**
UI 슬라이더가 ±2 를 넘길 수 있는지 확인한 뒤 판단하십시오.

---

## 12. 이식이 잡아낸 CPU/GPU 의미 차이 — "변화 없음" 은 복사입니다

`colorMixerHSL` 을 옮기다 동치 시험이 잡은 것입니다. **셰이더 수식은 맞았는데 결과가 갈렸습니다.**

CPU 커널들은 매개변수가 하나도 안 움직였으면 **커널을 돌리지 않고 원본을 그대로 내보냅니다**:

```cpp
// imaging/color_mixer.cpp:227
if (!has_color_mixer_change(parameters)) {
    negaflow::core::copy_validated_rows(input, output);
    return negaflow::core::KernelStatus::ok;
}
```

GPU 가 그 경우에도 커널을 돌리면 HSL 왕복이 `clamp(rgb, 0, 1)` 을 지나며 **[0,1] 밖 값을 잘라 냅니다.**
작업 이미지는 그 범위 밖 값을 **일부러** 남기므로(하이라이트 여유·포화색) 실제로 갈립니다 —
**실측 최대 delta 0.1.**

**규칙: 커널을 옮길 때 수식만 보지 말고 그 앞의 조기 반환도 같이 옮기십시오.**
지금까지 확인한 조기 반환 — `apply_color_mixer:227` · `apply_primary_calibration` ·
`apply_color_grading`. `GpuWorkingImage::copy_from`(`CopyResource`)가 그 자리를 맡습니다.

**아직 안 본 것: 나머지 커널의 조기 반환.** 옮길 때마다 확인하십시오.
