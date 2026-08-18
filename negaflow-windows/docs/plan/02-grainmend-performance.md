# 02 — 속도와 GPU

목표: 자동 검출 **5초 미만**. 가이드·브러시·복제·IR 즉시. 그리고 **이미지에 관련된 것은
전부 GPU** — 현상·프리뷰·보정·우측 슬라이더·인화까지.

## 1. 측정 (2026-08-17, `OpticFilm8100_frame_4.tiff` 5088×3401, x64 Release, 10코어/16스레드)

### 1.1 전체

| 단계 | 시간 |
|---|---:|
| TIFF 디코드 + ICC → linear | 2,695 ms |
| 현상(manual negative develop) | 770 ms |
| 검출 | 8,932 ms |
| **합계** | **12,397 ms** |

참고: 같은 프레임의 전체 내보내기(디코드+현상+톤+필름룩+인코딩)는 5,196 ms 이고 그중
출력 인코딩만 1,696 ms 입니다(`negaflow-cli --export-developed-tiff16`).

### 1.2 검출 내역 (12타일 합계, 워커 4)

| 단계 | CPU 합계 | 비중 |
|---|---:|---:|
| 먼지 형태학 | 14,990 ms | 47% |
| 미세 입자 | 11,135 ms | 35% |
| 스크래치 각도 | 2,058 ms | 6% |
| 검출 이미지 생성 | 840 ms | 3% |
| 증거 조립 | 602 ms | 2% |
| 봉합 + 성분 | 115 ms | <1% |

**형태학 `opening`/`closing` 이 82%.** 먼지와 미세 입자가 같은 원시연산을 씁니다.

### 1.3 계측기

```bash
negaflow-cli --grain-mend-detect "<source.tiff>" <dmin-r> <dmin-g> <dmin-b> [sensitivity] [guided]
```

`stages` 에 위 표가 그대로 나옵니다. 앱을 띄우지 않고 잽니다.

## 2. 왜 macOS 가 빠른가

macOS Chromabase 는 검출을 **CoreImage + Accelerate(vImage)** 로 돕니다. 즉 GPU 와 SIMD 를
씁니다. Windows 는 같은 수식을 CPU 스칼라 4스레드로 돌립니다. 알고리즘은 이미 최적
(van Herk/Gil-Werman 분리형 단조 큐, 화소당 O(1))이라 **알고리즘이 아니라 실행 장치가
차이**입니다.

## 3. CPU 쪽에서 먼저 걷어낼 낭비

GPU 로 가기 전에 이것부터 합니다. 싸고, GPU 로 옮길 때도 그대로 도움이 됩니다.

1. **버퍼 재사용.** `bipolar_top_hat` 은 호출마다 `std::vector<float>` 를 새로 잡습니다.
   타일당 9회(3채널 × 반경 3개) × 내부 4개 ≈ 36개, 타일 12개면 432회 × 7MB 급 할당입니다.
   워크스페이스를 타일에 한 벌 두고 돌려씁니다.
2. **`find_candidates` 의 각도 워커 상한 2.** `worker_count = clamp(hw, 1, 2)` 로 박혀
   있습니다. 타일 4개가 이미 돌므로 중첩이 항상 이득은 아닙니다 — **측정해서** 정합니다.
3. **타일 동시 실행 수.** 지금 `clamp(hw/2, 1, 4)` = 4. 16스레드 기계에서 8까지 올려 보고
   메모리 피크와 함께 잽니다(타일당 약 100MB).
4. **`std::async` 대신 고정 스레드 풀.** 타일마다 스레드를 만들고 버립니다.

## 4. GPU — 무엇으로 할 것인가

### 4.1 선택: Direct3D 11 컴퓨트 셰이더 (DirectCompute)

요구는 "Intel 내장·AMD 내장·외장(Intel/NVIDIA/AMD) 공통". 그 조건을 만족하는 것은
D3D11 컴퓨트 셰이더입니다.

| 후보 | 판정 | 이유 |
|---|---|---|
| **D3D11 컴퓨트 셰이더** | **채택** | Microsoft 가 만들고 모든 벤더가 구현. Windows 에 기본 포함이라 재배포할 런타임 없음. DX11 되는 GPU면 내장·외장 무관 |
| D3D12 컴퓨트 | 보류 | 되지만 API 표면이 훨씬 크고, 구형 내장 GPU 드라이버 커버리지가 D3D11 보다 좁음 |
| OpenCL | 탈락 | 깨끗한 Windows 에 ICD 가 보장되지 않음 |
| CUDA | 탈락 | NVIDIA 전용 |
| Vulkan 컴퓨트 | 탈락 | 되지만 SDK·셰이더 파이프라인이 무겁고 구형 내장에서 드라이버 편차 |
| DirectML | 탈락 | ML 연산자용. 형태학·톤 곡선에 맞는 연산자가 없음 |

근거:
- 컴퓨트 셰이더는 D3D11 을 그래픽 밖으로 넓힌 프로그래머블 스테이지이며 DirectCompute 로
  불립니다. 벤더 중립으로 설계됐고 Microsoft 와 DX 워킹그룹이 만듭니다
  ([Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-compute-shader),
  [Real-Time Rendering](https://www.realtimerendering.com/blog/direct-3d-11-details-part-iii-compute-shaders-unordered-memory/)).
- 다운레벨 하드웨어(D3D_FEATURE_LEVEL_10_0/10_1)도 CS 4.0/4.1 을 **선택적으로** 지원합니다.
  `ID3D11Device::CheckFeatureSupport` 에 `D3D11_FEATURE_D3D10_X_HARDWARE_OPTIONS` 를 넘겨
  `ComputeShaders_Plus_RawAndStructuredBuffers_Via_Shader_4_x` 로 확인합니다
  ([Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-devices-downlevel-compute-shaders)).
- 하드웨어가 없거나 컴퓨트를 못 하면 **WARP**(소프트웨어 래스터라이저)로 장치를 만들 수
  있습니다. Windows 8 이후로는 모든 기능 수준에서 WARP 장치를 만들 수 있습니다
  ([Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-devices-create-warp)).
  다만 WARP 는 CPU 라 속도 이득이 없으므로 **정합성 확인용**으로만 씁니다.

### 4.2 형태학의 GPU 구현

van Herk/Gil-Werman 을 GPU 로 옮긴 선례가 있습니다. CUDA 구현에서 소박한 GPU 구현과 CPU
vHGW 대비 크게 앞섰고, 65×65 구조요소까지 CPU 대비 13~33배가 보고돼 있습니다
([NVIDIA GTC 포스터](https://www.nvidia.com/content/gtc/posters/14_domanski_parallel_vanherk.pdf),
[논문 PDF](https://www.diva-portal.org/smash/get/diva2:981180/FULLTEXT01.pdf)).
우리 반경은 4·8·12 로 작아 배수는 더 낮겠지만, 82% 를 차지하는 단계라 절대 이득이 큽니다.

구현 방향:
- 가로 패스와 세로 패스를 **각각 하나의 컴퓨트 셰이더**로. 그룹 공유 메모리에 타일 한 줄을
  올리고 vHGW 의 전방/후방 누적을 그룹 안에서 계산합니다.
- 입력은 `Buffer<float>`/`RWBuffer<float>` (structured buffer). 텍스처보다 인덱싱이 단순하고
  다운레벨에서도 raw/structured buffer 가 CS 4.x 조건에 포함됩니다.
- opening = erode→dilate, closing = dilate→erode. 커널 두 개(min/max)를 `#define` 으로 찍어
  네 조합을 만듭니다.

### 4.3 이미지 파이프라인 전체를 GPU 로

사용자 요구: 현상·프리뷰·보정·우측 슬라이더·인화까지 이미지 관련은 전부.

macOS 는 이 전부가 CoreImage 그래프입니다. Windows 도 같은 구조로 갑니다 — **한 번 올리고,
여러 커널을 이어 돌리고, 마지막에 한 번 내린다.** 단계마다 올렸다 내리면 PCIe 전송이 계산보다
비쌉니다.

| 파이프라인 단계 | 현재 | GPU 커널 | 우선순위 |
|---|---|---|---|
| 네거티브 반전 + dmin/dmax | CPU | 화소별 — 아주 쉬움 | 2 |
| 기본 톤(노출·대비·밝은/어두운·화이트/블랙·농도) | CPU | 화소별 + LUT | 1 (슬라이더 체감) |
| 톤 곡선(파라메트릭·포인트) | CPU | 1D LUT 텍스처 | 1 |
| 컬러 믹서 / 컬러 그레이딩 / 캘리브레이션 | CPU | 화소별 행렬 | 1 |
| 필름 룩(3D LUT + acutance) | CPU | 3D LUT 샘플 + 언샤프 | 2 |
| GrainMend 형태학 | CPU | vHGW 컴퓨트 | **0 (가장 큼)** |
| GrainMend 스크래치 8각도 적분 | CPU | 방향 적분 커널 | 3 |
| 미세 입자 | CPU | 형태학 재사용 | 0 (형태학과 같이) |
| 복원(median / onion-peel) | CPU | 이웃 커널 | 3 |
| 크롭·회전·수평보정 | CPU | 샘플링 커널 | 3 |
| 프리뷰 리샘플 | CPU | 밉/Lanczos 커널 | 1 (프리뷰 체감) |
| 인화 합성 | CPU | 화소별 | 4 |
| 출력 인코딩(TIFF/JPEG) | CPU(WIC) | GPU 대상 아님 | — |

**우선순위 0~1 이 체감의 전부입니다.** 슬라이더를 끌 때 프리뷰가 즉시 따라오려면
"기본 톤 → 곡선 → 믹서 → 그레이딩" 이 GPU 에서 한 번에 돌아야 합니다.

### 4.4 아키텍처

```
src/Native/gpu/
  gpu_device.{h,cpp}        D3D11 장치 생성·기능 확인·WARP 폴백. 실패하면 CPU 경로로.
  gpu_buffer.{h,cpp}        structured buffer 올리기/내리기, 스테이징 링
  gpu_kernel.{h,cpp}        컴파일된 셰이더 바이트코드 캐시, 디스패치
  shaders/morphology.hlsl   vHGW 가로/세로 × min/max
  shaders/tone.hlsl         기본 톤 + 곡선 LUT + 믹서 + 그레이딩
  shaders/develop.hlsl      네거티브 반전 + dmin/dmax
  shaders/resample.hlsl     프리뷰 축소
```

규칙:

1. **GPU 는 선택 경로입니다.** 장치를 못 만들거나 컴퓨트를 못 하면 지금 CPU 코드가 그대로
   돕니다. 두 경로가 **같은 값**을 내야 하며, 이것을 시험으로 고정합니다(05 문서).
2. **셰이더는 빌드 때 `fxc` 로 컴파일해 바이트코드를 리소스로 심습니다.** 런타임 컴파일은
   `d3dcompiler_47.dll` 재배포가 필요하고 첫 실행이 느립니다.
3. **한 파일 500줄.** 셰이더도 마찬가지입니다.
4. **정밀도.** 현재 파이프라인은 `float`(32bit)입니다. HLSL 도 `float` 이라 같습니다.
   단, 컴파일러의 `precise` 여부와 fast-math 로 미세 차이가 납니다 — 05 문서의 허용 오차로
   고정합니다.

### 4.5 위험

| 위험 | 대응 |
|---|---|
| 내장 GPU 메모리 부족(공유 메모리) | 타일 단위로 올림. 타일 크기를 가용 VRAM 으로 정함 |
| 드라이버가 컴퓨트 미지원(구형 10.x) | `CheckFeatureSupport` 로 확인 후 CPU 폴백 |
| CPU↔GPU 전송이 계산보다 비쌈 | 파이프라인을 GPU 에서 이어 돌리고 마지막에 한 번만 내림 |
| MSIX 패키지에서 D3D 초기화 | WinUI 3 앱이 이미 D3D 를 쓰므로 같은 프로세스에서 가능. 장치를 공유할지 별도로 만들지 결정 필요 |
| 값이 CPU 와 미세하게 다름 | 허용 오차 시험 + 골든 이미지 비교 |
| ARM64 | D3D11 컴퓨트는 ARM64 Windows 에서도 됩니다. 같은 코드로 갑니다 |

## 5. 순서

1. CPU 낭비 제거(3절) → 재측정
2. `gpu_device` + 기능 확인 + WARP 폴백 + **CPU/GPU 동치 시험 틀**
3. `morphology.hlsl` (검출 82%) → 재측정
4. `tone.hlsl` + `develop.hlsl` (슬라이더 체감) → 프리뷰 지연 측정
5. `resample.hlsl` (프리뷰)
6. 나머지(필름 룩, 복원, 기하, 인화)

각 단계마다 `--grain-mend-detect` 와 `--export-developed-tiff16` 숫자를 이 문서에 적습니다.

## 6. 목표 배분 (자동 5초)

| 단계 | 지금 | 목표 |
|---|---:|---:|
| 디코드 | 2,695 ms | 1,500 ms (행 스트리밍 병렬화) |
| 현상 | 770 ms | 200 ms (GPU) |
| 검출 | 8,932 ms | 2,500 ms (GPU 형태학) |
| **합계** | **12,397 ms** | **4,200 ms** |

디코드가 남는 가장 큰 CPU 항목이 됩니다. macOS 는 첫 검출 뒤 **세션 캐시**
(`defectSessionRaw`)를 두어 재검출에서 디코드를 건너뜁니다 — Windows 도 같은 캐시가 필요합니다
(03 문서의 재검출 경로와 함께).

---

## 최신화 (2026-08-18)

이 문서의 **측정값은 그대로 유효합니다**(2026-08-17, `OpticFilm8100_frame_4.tiff` 5088×3401).
그 뒤에 확인·결정된 것:

| 항목 | 결과 |
|---|---|
| GPU 구현 | **여전히 0줄.** 10개 키워드 히트 0, `.hlsl` 0개 |
| GPU 이식 대상 | macOS `ChromabaseMetalKernels.swift` 의 `[[stitchable]]` 커널 **32개**(전부 화소별). 목록은 [`../audit/04-gpu-plan.md`](../audit/04-gpu-plan.md) 1.3 |
| ☠️ 주의 | 그중 **3개는 macOS 가 부르지 않습니다** — `scannerLowSatChroma`/`scannerMidtoneChroma`·`gamutSoftClip`·`highlightDesaturate`. 옮기면 없는 효과를 만듭니다 |
| 이웃 연산 | macOS 는 Apple 내장 필터(`CIGaussianBlur`·`CIBoxBlur`·`CIMedianFilter`·`CIAreaAverage`)로 처리. **Windows 는 직접 만들어야 합니다** |
| 형태학 47%(미세 입자까지 82%) | **van Herk / Gil-Werman** 으로 구조 요소 크기와 **무관한 O(1)**. 침식·팽창은 분리 가능 → 수평·수직 2패스. 방법은 [`../audit/13-performance-playbook.md`](../audit/13-performance-playbook.md) 4.3 |
| API | D3D11 컴퓨트, 하한 **FL 11_0**, 포맷 `R32G32B32A32_FLOAT` |
| 디코드 2,695 ms | `decode.cpp` 에 프로세스 단일 슬롯 캐시가 들어감(2026-08-18). 첫 호출은 그대로, 같은 프레임 재호출은 디스크 디코드 안 함 |
| 프리뷰 2단 렌더 | `DevelopPreviewProxy.cs` 로 macOS 상수 이식됨. **효과 ms 는 미측정** |

**그리고 이 문서가 못 다룬 것: 현상·보정·룩·인화 단계별 ms 를 아무도 안 쟀습니다.**
사용자가 "우측탭 뭘 써도 수 초" 라고 한 그 구간입니다.
계측기가 없어서 못 쟀습니다 — [`../audit/13-performance-playbook.md`](../audit/13-performance-playbook.md) 2절이 0단계입니다.
