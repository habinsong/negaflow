# 실행 백엔드 선택 — D3D11, Direct2D, CPU, WARP, CUDA

기준일: 2026-08-04  
상태: v1 기준선 결정, 세부 포맷·성능은 스파이크 필요  
대체 대상: 기존 문서의 `D3D12 + FL 12_0 + SM 6.0 필수` 결론
실패·복구 계약: [Windows 렌더·성능 실패 모드](known-failure-modes.md)

## 1. 결론

Windows v1은 한 개의 Direct3D 11 장치에서 Direct2D와 DirectCompute를 함께 사용한다.

```text
파일 decode / source tiles
          │
          ▼
CPU scalar·SIMD ────────┐
          │              │ upload/readback가 필요한 경우만
          ▼              ▼
D3D11 texture ──► Direct2D effect graph ──► color-managed display ──► swap chain
    │                        │
    └──── DirectCompute ◄────┘
          통계·리덕션·공간 연산 후보
```

기준:

| 항목 | v1 결정 |
|---|---|
| API | Direct3D 11 + DXGI + Direct2D 1.1+ |
| 최소 GPU 기능 | feature level 11_0 |
| shader | Shader Model 5.0, 오프라인 DXBC |
| 프레젠테이션 | composition flip-model swap chain + WinUI 3 SwapChainPanel |
| 소프트웨어 GPU | Microsoft WARP |
| CPU | scalar truth + x64/ARM64 runtime-dispatched hot kernels |
| D3D12 | 계측 후 선택적 tier 후보 |
| CUDA | NVIDIA 선택적 tier 후보, v1 우선순위 아님 |

이 기준은 Intel·AMD·NVIDIA·Qualcomm에서 하나의 기능 집합을 유지하면서 Direct2D와 D3D12
사이의 D3D11On12 wrapped-resource 수명·동기화 경계를 없앤다.

## 2. 왜 D3D11이 범용성 기준선인가

### 필요한 기능이 FL 11_0 안에 있다

Negaflow의 핵심은 이미지 필터, lookup, histogram, reduction, morphology, resize와 합성이다.
DirectCompute 5.0은 FL 11.x에서 다음을 제공한다.

- thread group당 최대 1,024 threads
- 최대 8 UAV bindings
- typed/read-write resources
- atomics
- thread-group shared memory
- 3차원 dispatch

프로젝트가 요구하지 않는 기능:

- ray tracing
- mesh shader
- work graph
- sampler feedback
- vendor matrix/tensor unit

FL 12_0을 최소로 올려도 사진 파이프라인의 정확도가 좋아지지 않는다. 반면 오래된 Intel iGPU,
가상 환경과 일부 ARM64 장치의 지원 범위를 줄이고 WARP·CI 조합을 복잡하게 만든다.

### Direct2D가 D3D11과 직접 interoperates한다

DirectX 11.1 이후 Direct2D는 DXGI surface를 통해 D3D11과 interop한다. 같은 D3D11 device에서
효과 그래프, custom pixel effect, DirectCompute resource와 UI 합성을 관리할 수 있다.

D3D12를 기준으로 두면 Direct2D용 D3D11On12 device, wrapped resource의 acquire/release,
flush, device-lost 복구를 추가해야 한다. 기능상 필요한 복잡도가 아니라 API 조합에서 생기는
복잡도이므로 v1 기준에서 제외한다.

### 낮은 API overhead가 주 병목이 아니다

고해상도 사진 파이프라인의 비용은 대개 다음에 있다.

- decode/encode와 압축
- 대용량 texture upload/readback
- 여러 full-frame intermediate의 메모리 대역폭
- filter halo와 tile overlap
- ICC transform
- defect detection의 spatial pass

command submission이 실제 상위 병목이라는 PIX/ETW 증거가 생기기 전에는 D3D12 전환 비용을
정당화하지 못한다.

## 3. 장치 생성 계약

### adapter 선택

기본 정책:

1. Windows의 사용자 graphics preference를 존중한다.
2. software adapter를 제외한 adapter를 열거한다.
3. 필수 D3D11·DXGI·format support를 capability query한다.
4. 지원되는 시스템 선호 adapter로 장치를 만든다.
5. 실패 시 다른 hardware adapter를 시도한다.
6. 마지막에 WARP를 시도한다.

사용자 설정에는 `자동`, 실제 adapter 목록, `소프트웨어 호환 모드(WARP)`를 제공할 수 있다.
벤더 이름만 보고 “빠른 GPU”를 고르지 않는다. 하이브리드 GPU에서는 배터리·외장 모니터·OS
graphics preference와 compositor adapter가 영향을 준다.

필수 로그:

- adapter LUID와 DXGI description
- vendor/device/subsystem/revision ID
- hardware/WARP
- granted feature level
- dedicated/shared memory와 budget
- driver version
- required format/support bit 결과

### device flags

- `D3D11_CREATE_DEVICE_BGRA_SUPPORT`: Direct2D interop 필수
- Debug build에서만 `D3D11_CREATE_DEVICE_DEBUG`, debug layer가 있을 때
- single-threaded flag는 사용하지 않는다. resource creation과 engine thread 모델을 검증한다.
- feature-level 요청은 11_1을 먼저 허용하되 11_0을 제품 최소로 기록한다.

11_1 장치에서 추가 기능을 쓰더라도 11_0 결과와 기능이 같아야 한다. capability는 최적화에만
사용한다.

### Direct2D 체인

```text
ID3D11Device
→ IDXGIDevice
→ ID2D1Factory1+
→ ID2D1Device
→ ID2D1DeviceContext
```

factory와 device는 장기 재사용한다. 프레임마다 factory, D3D device, `CIContext` 등가 객체를
만들지 않는다. device context 사용은 engine render queue가 직렬화한다.

## 4. 포맷과 정밀도

### 원칙

- negative inversion, exposure, curves와 색 변환 사이의 intermediate를 UNORM으로 만들지 않는다.
- 0 미만과 1 초과의 extended-linear 값을 pipeline이 허용하는 구간에서는 보존한다.
- 최종 display/output transform에서만 명시적으로 gamut map·clamp·quantize한다.
- alpha는 수학적 의미가 없으면 상수 1로 유지하고 premultiplication 경계를 문서화한다.
- sRGB texture flag로 색 관리를 대신하지 않는다.

### 초기 포맷 후보

| 용도 | 기본 후보 | 결정 방법 |
|---|---|---|
| 품질 기준 intermediate | 32-bpc float RGBA | WARP·필수 GPU 지원과 메모리 예산 실측 |
| interactive preview 일부 | 16-bpc float RGBA | 골든 오차와 banding·highlight 보존 통과 시만 |
| histogram input | pipeline float texture | 별도 8-bit 양자화 금지 |
| display swap chain | BGRA8 또는 HDR별 명시 포맷 | 출력 색공간·Advanced Color 계약에 따라 |
| masks | R8/R16/float 중 의미별 | feather·recipe 정밀도 테스트 |
| IDs/labels | integer texture/buffer | 색 texture와 혼용 금지 |

`32-bpc float`는 channel당 32-bit를 뜻하며 100MP RGBA 한 장만 약 1.6GB다. 따라서 품질 기준을
그대로 유지하되 전체 이미지를 여러 장 resident로 두지 않는 tile/graph scheduling이 필수다.
FP16은 메모리 절감 버튼이 아니라 stage별 오차가 입증된 최적화다.

필수 capability query:

- shader sample
- render target
- typed UAV load/store가 필요한 경우
- linear filtering
- shared/composition surface
- Direct2D buffer precision support

포맷이 없으면 조용히 8-bit로 내리지 않는다. CPU 경로 또는 지원되는 float 포맷으로 전환하고
진단한다.

## 5. 작업별 백엔드 배치

| 작업 | 기본 | 폴백 | 이유 |
|---|---|---|---|
| 파일 probe/metadata | CPU | 없음 | IO·parsing |
| decode | WIC/libtiff CPU | codec별 | GPU upload 전 원본 계약 검증 |
| negative/digital pointwise develop | D2D pixel effects | CPU | effect graph·ROI·shader linking |
| tone curve/LUT | D2D pixel effects | CPU | pointwise, cacheable constants |
| geometric transform/resize | D2D 또는 D3D11 shader | CPU | sampler·ROI, 품질 kernel 비교 |
| histogram/statistics | D3D11 compute 후보 | 결정적 CPU | 리덕션 순서가 자동 결과에 영향 |
| auto-tone parameter 산출 | CPU 결정적 | 없음 | 적은 데이터, 재현성 우선 |
| defect contrast field | D3D11 compute 후보 | CPU tile | 대역폭·spatial filtering |
| connected components/recipe logic | CPU | GPU 후보 | 분기·결정성·작은 metadata |
| defect clean render | operation별 GPU | CPU | spatial tile/ROI |
| thumbnail | GPU/CPU scheduler | CPU | cache와 foreground 우선순위 |
| export final render | GPU | CPU | 같은 수치 graph, headless 가능 |
| print page pixels | GPU 또는 CPU | CPU | output profile과 page renderer 분리 |
| UI text/vector overlay | Direct2D/WinUI | WARP | XAML·DWrite integration |

“GPU 우선”은 무조건 모든 단계를 GPU에 올린다는 뜻이 아니다. 입력·출력, 데이터 크기, transfer,
결정성, 이미 resident인지까지 포함한 end-to-end 시간이 더 빠른 경로를 고른다.

## 6. Direct2D 효과 그래프

현재 macOS Metal kernel 개수는 고정 상수가 아니다. 커밋 `9be909c` 기준 31개이고 현재
미커밋 워킹트리에는 새 `digitalGamutSoftClip`을 포함해 32개가 관찰된다. Windows 구현은 숫자를
문서에 박지 않고 baseline manifest의 kernel ID와 stage를 입력으로 삼는다.

### pointwise chain

- 각 조정은 stable effect ID와 property schema를 가진다.
- `MapInputRectsToOutputRect`와 역방향 ROI가 pointwise identity인지 명시한다.
- 인접한 pixel transforms는 Direct2D shader linking 가능 여부를 검사한다.
- linking이 실패해도 결과가 바뀌지 않고 intermediate allocation만 늘어난다.
- compile manifest에 shader profile, entry point, source hash, constant layout을 기록한다.

### linking을 깨는 항목

- compute transform
- vertex transform
- sampling footprint를 확장하는 spatial transform
- precision/format 경계
- CPU readback
- output color transform 또는 합성 경계

그래프를 “무조건 한 shader”로 수동 생성하지 않는다. 먼저 D2D가 실제로 link한 pass 수와
intermediate allocation을 PIX에서 확인한다. 필요하면 macOS stage 계약을 유지한 별도 fused
HLSL permutation을 제한적으로 만들되 조합 폭발을 막는다.

## 7. DirectCompute 사용

같은 D3D11 device의 compute shader로 다음을 우선 스파이크한다.

- histogram private bins + merge
- min/max/percentile용 partial reduction
- separable blur/top-hat/contrast field
- mask dilation/erosion 후보
- tile statistics

### resource binding 규칙

D3D11은 D3D12식 명시적 barrier API가 없지만 hazard가 사라지는 것은 아니다.

- 같은 resource를 SRV와 UAV/RTV로 동시에 bind하지 않는다.
- pass가 끝나면 사용한 slot을 명시적으로 unbind한다.
- D2D `BeginDraw`/`EndDraw`와 compute dispatch 사이의 소유 순서를 render queue가 관리한다.
- CPU readback은 staging resource와 fence/query 성격의 완료 확인을 사용한다.
- `Flush`는 correctness를 위해 실제로 필요한 interop 경계만 사용하고 프레임마다 습관적으로 호출하지 않는다.
- immediate context 접근은 한 engine queue가 직렬화한다.

### thread-group 튜닝

1024가 상한이라는 사실은 권장값이 아니다. 시작점:

- point/2D: 8×8 또는 16×16
- 1D reduction: 128 또는 256 threads
- groupshared 사용량은 32KB 상한보다 occupancy와 vendor 차이를 먼저 본다.
- wave size를 32 또는 64로 가정하지 않는다.
- NVIDIA 한 장치에서 빠른 shape를 전 벤더 상수로 확정하지 않는다.

각 kernel은 최소 Intel iGPU, AMD, NVIDIA, Qualcomm/WARP에서 후보 shape를 측정하고 지나친
permutation은 버린다.

## 8. CPU 백엔드

CPU는 “GPU 실패 때만 작동하는 느린 코드”가 아니다.

- 수치 truth implementation
- headless CLI와 CI
- 작은 ROI·작은 이미지에서 transfer보다 빠른 경로
- image IO와 metadata
- 결정적 histogram/auto parameter
- GPU device-lost 동안 기능 유지
- ARM64와 x64의 독립 성능 경로

dispatch 순서:

```text
항상 존재하는 scalar
→ compiler auto-vectorization 확인
→ x64 AVX2/FMA 또는 ARM64 NEON hot path
→ 측정된 경우에만 Highway 같은 dispatch helper
```

SIMD를 넣기 전에 multi-thread tile/scanline scheduling, cache locality, false sharing, allocator와
format conversion을 프로파일한다. morphology deque처럼 branch/data dependency가 강한 작업은
라인 병렬이 SIMD보다 먼저다.

## 9. WARP의 역할

WARP는 다음 세 역할을 가진다.

1. hardware device 생성이 불가능한 사용자 환경의 기능 폴백
2. vendor-independent CI 그래픽 conformance
3. device-lost 복구와 shader capability 검증

WARP에서도 모든 기능과 정밀도 계약이 유지되어야 한다. 다만 100MP export의 실시간 성능을
요구하지 않는다. UI는 software compatibility mode를 명확히 표시하고 GPU-heavy background
작업의 예상 지연을 안내할 수 있다.

자동 WARP 전환 정책:

- startup hardware device 생성 실패: WARP 시도, 성공하면 진단 surface에 표시
- runtime device removed: 같은 hardware adapter 재생성 1회
- 반복 실패: 사용자 recipe를 보존하고 WARP/CPU 전환 제안 또는 자동 전환
- invalid call/hung 반복: 무한 재시작하지 않고 crash diagnostics와 safe mode

WARP 결과가 hardware와 다르면 hardware 차이로 덮지 않고 shader/precision bug로 취급한다.

## 10. 비디오 메모리 예산

고정 VRAM 크기의 일정 비율만 보는 방식은 UMA와 다른 앱의 사용량을 반영하지 못한다.

`IDXGIAdapter3::QueryVideoMemoryInfo`의 local/non-local segment에서 다음을 추적한다.

- `Budget`
- `CurrentUsage`
- `AvailableForReservation`
- `CurrentReservation`

budget change notification을 받아 cache를 trim한다. 정책 예:

| 상태 | 조치 |
|---|---|
| usage < 60% budget | interactive working set 유지 |
| 60~80% | background thumbnail·prefetch 억제 |
| 80~90% | LRU intermediate·offscreen preview 적극 eviction |
| >90% 또는 allocation failure | foreground에 필요한 tile만, export concurrency 감소 |

이 퍼센트는 초기값이지 확정 성능 수치가 아니다. 실제 UMA/dGPU에서 조정한다. 예약은 OS에 대한
힌트이며 다른 앱을 밀어내기 위한 권리가 아니다.

### resource budget 항목

- source decode tiles
- full/preview working textures
- effect intermediates
- histogram/reduction buffers
- defect masks와 cleaned tiles
- swap-chain buffers
- export in-flight tiles
- thumbnails

각 resource는 owner, byte size, reconstruct cost, last-used fence/epoch를 가진다. 원본과 recipe는
GPU resource보다 상위의 영속 truth이므로 언제든 파생 resource를 버리고 재생성할 수 있어야 한다.

## 11. 타일과 작업 스케줄링

전체 이미지에 단일 dispatch를 보내지 않는다.

- source tile size와 GPU compute tile을 구분한다.
- spatial kernel은 halo를 요청하고 output valid rect를 기록한다.
- preview는 viewport와 zoom에 필요한 tile을 우선한다.
- export는 scanline/codec 요구와 memory budget에 맞는 순서로 처리한다.
- interactive 작업이 background thumbnail/export보다 높은 priority다.
- 오래된 slider render는 아직 시작하지 않은 tile을 즉시 취소한다.
- 이미 실행 중인 GPU command를 억지로 회수하지 않고 결과 commit에서 revision을 확인한다.

TDR 회피:

- 대형 image와 큰 morphology radius를 bounded tile dispatch로 나눈다.
- 한 dispatch의 GPU 시간 분포를 PIX timestamp로 기록한다.
- OS TDR registry를 바꾸는 설치 안내를 제품 해법으로 제공하지 않는다.
- worst-case synthetic와 실제 35mm/120 high-DPI scan을 모두 시험한다.

## 12. preview와 export의 관계

속도를 위해 preview와 export의 수학을 다른 제품으로 만들지 않는다.

공유:

- adjustment order
- parameter semantics
- color working space
- crop/transform geometry
- defect recipe
- output transform 전 scene result

다를 수 있음:

- preview resolution과 tile residency
- interactive cancellation/supersession
- display profile 대 export profile
- preview cache와 export streaming
- sampling kernel의 명시적 preview tier — 최종 commit 전 full-quality rerender 필요

Quick Export, ordinary Export, Develop toolbar, Output tab 등 어떤 UI entry에서도 같은 final render
contract를 호출해야 한다.

## 13. device-lost와 adapter 변경

device-derived object는 모두 한 generation에 속한다.

```text
Present/EndDraw/dispatch 완료에서 device error 감지
→ 새 GPU 요청 중지
→ GetDeviceRemovedReason + adapter/build/request 진단
→ 기존 generation의 canvas/effect/texture/query 전부 폐기
→ adapter 재열거·device 재생성
→ shader/effect registration 재구성
→ source + recipe + current revision에서 필요한 화면 재렌더
```

보존해야 하는 것:

- catalog
- selection
- undo/redo와 Develop parameters
- defect recipe
- export plan과 완료된 파일 기록

보존하지 않아도 되는 것:

- GPU textures
- effect instances
- swap chain
- transient histogram buffer
- preview cache의 GPU side

`DXGI_ERROR_INVALID_CALL`은 정상 장치 교체로 취급하지 않는다. 앱 bug 가능성이 높으므로 반복
재생성 대신 진단 gate를 세운다.

## 14. CUDA 평가 규칙

CUDA는 NVIDIA 사용자에게만 추가 속도를 줄 수 있으므로 기본 설계를 지배하지 않는다.

### 허용 조건

- 동일 operation의 D3D11과 CPU 구현이 이미 완성됨
- NVIDIA가 아니어도 기능 100% 제공
- 실제 Negaflow workload에서 병목이 해당 kernel로 확인됨
- texture/resource interop과 synchronization을 포함한 end-to-end 비교
- installer 크기·초기화·driver/EULA·테스트 유지비 포함
- decoded final pixel과 metadata가 품질 허용 오차 통과
- 대표 NVIDIA 2세대 이상에서 실측

### 초기 채택 threshold

- 긴 batch의 end-to-end time 20% 이상 단축, 또는
- 한 장의 사용자 대기에서 체감 가능한 명확한 절대 시간 단축

kernel microbenchmark 2배만으로 채택하지 않는다. upload, shared-resource handoff, fence,
fallback, package를 포함한다.

### 격리 방식

- 별도 optional module
- backend capability registry에 속도 tier로만 등록
- canonical parameter와 resource contract 공유
- CUDA-specific preset/품질 option 금지
- module load 실패 시 D3D11로 정상 계속
- main installer에 무조건 포함하지 않음

CUDA를 먼저 최적화하지 않는다. 가장 느린 필수 target인 Intel/AMD/Qualcomm과 CPU 경로를 먼저
제품 수준으로 만든다.

## 15. D3D12 전환 게이트

D3D12는 “새 API라 더 빠르다”로 채택하지 않는다. 다음이 모두 필요하다.

1. D3D11 최적화 후에도 목표 latency/throughput을 지속적으로 초과한다.
2. PIX/ETW가 원인을 command submission, resource state control 등 D3D11 고유 제약으로 특정한다.
3. 같은 shader math와 quality fixture를 유지한다.
4. Direct2D interop의 D3D11On12 acquire/release/flush 비용을 포함한다.
5. device-lost·memory-budget·multi-adapter 복구 복잡도를 구현한다.
6. Intel·AMD·NVIDIA·Qualcomm에서 순이득이 있거나 특정 tier로 격리한다.
7. WARP/CPU fallback은 그대로 유지한다.

D3D12를 추가해도 v1 D3D11 path를 바로 제거하지 않는다. 지원 hardware 분포와 유지 비용을
릴리스 telemetry·실험실 matrix로 확인한 뒤 별도 결정한다.

## 16. 자동 backend 선택

startup capability만으로 영구 선택하지 않는다. operation별 데이터 크기와 residency가 중요하다.

초기 휴리스틱:

```text
필수 GPU 기능 없음                         → CPU
hardware device 없음                       → WARP 또는 CPU
작은 ROI + source가 CPU resident            → CPU 후보
interactive/full image + GPU resident       → D2D/D3D11
결정적 auto measurement                     → GPU partial + CPU final 또는 CPU
export tile + GPU budget 충분               → GPU
export queue가 GPU UI를 방해                 → CPU/낮은 GPU priority 후보
NVIDIA optional module + 채택 게이트 통과    → 일부 operation만 CUDA 후보
```

휴리스틱은 hidden benchmark로 사용자 첫 실행을 오래 막지 않는다. shipped default와 짧은
calibration, 실제 telemetry가 아닌 로컬 timing cache를 조합할 수 있다. 사용자가 backend를
고정하면 진단 가능성을 위해 존중하되 unsupported 조합은 설명하고 거부한다.

## 17. 품질 비교

backend 비교는 단순 file hash로 하지 않는다. 압축·metadata ordering은 달라질 수 있다.

### 픽셀

- stage별 float dump 또는 sampled probes
- max absolute/relative error
- RMSE/PSNR만이 아니라 shadow, highlight, neutral, saturated patch
- NaN/Inf count와 위치
- clipped-below-zero/above-one count
- spatial edge/halo와 mask boundary
- deterministic histogram/percentile/auto parameters

### 색과 파일

- embedded ICC bytes 또는 semantic identity
- decoded final pixels after profile handling
- EXIF/XMP allowlist policy
- bit depth, alpha, orientation, DPI
- TIFF tag·BigTIFF·compression semantics

허용 오차는 operation별로 설정한다. 모든 단계를 하나의 넓은 최종 오차로 덮지 않는다.

## 18. 성능 측정 matrix

데이터셋:

- 작은 JPEG 12MP
- 일반 카메라 24/45MP
- 35mm high-DPI scan
- 120 6×17 high-DPI scan
- 100MP synthetic noise/gradient/edge
- panorama 또는 수억 픽셀 tiled TIFF
- 실제 39장 batch와 대규모 virtual batch

경로:

- first open/cold decode
- warm Develop slider drag
- zoom/pan/fit와 monitor move
- automatic measurement
- defect detection/clean
- ordinary Export와 Quick Export
- single print와 contact sheet
- foreground UI 중 background thumbnail/export

환경:

- Intel x64 iGPU
- AMD x64 iGPU/dGPU
- NVIDIA x64 dGPU·hybrid laptop
- Qualcomm ARM64
- WARP
- 8/16/32GB RAM 등급

측정값:

- user-perceived latency p50/p95/p99
- CPU time, GPU time, disk IO
- upload/readback bytes
- peak committed RAM, working set
- GPU local/non-local usage와 budget peak
- pass/intermediate count
- decode/render/encode 분해
- cancellation latency와 wasted work
- device-lost recovery time

## 19. 아직 실기로 확인하지 않은 위험

- Direct2D 32-bpc float intermediate의 모든 필수 Intel/AMD/NVIDIA/Qualcomm/WARP 조합
- D2D shader linking이 실제 파이프라인에서 만드는 pass 수
- D2D와 external D3D11 compute 사이 전환 비용
- WinUI compositor와 선택 adapter가 다른 hybrid-GPU 환경
- 100MP에서 FP32 tile working set과 budget threshold
- WARP의 대형 spatial effect 실행 시간
- ARM64의 native dependency와 HLSL asset 로딩
- D3D11 driver별 floating-point variation
- Advanced Color/HDR와 display ICC의 실제 Windows 동작

이 항목을 확인하기 전에는 “모든 GPU에서 빠르다” 또는 “색이 완전히 같다”고 선언하지 않는다.

## 공식 근거

- [Direct2D and Direct3D interoperability](https://learn.microsoft.com/en-us/windows/win32/direct2d/direct2d-and-direct3d-interoperation-overview)
- [Direct2D custom effects](https://learn.microsoft.com/en-us/windows/win32/direct2d/custom-effects)
- [Direct2D effect shader linking](https://learn.microsoft.com/en-us/windows/win32/direct2d/effect-shader-linking)
- [Direct3D 11 compute shader overview](https://learn.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-compute-shader)
- [Direct3D hardware feature levels](https://learn.microsoft.com/en-us/windows/win32/direct3d12/hardware-feature-levels)
- [Create a WARP device](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-devices-create-warp)
- [DXGI 1.4 video-memory budget](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-1-4-improvements)
- [Handle Direct3D device removed scenarios](https://learn.microsoft.com/en-us/windows/uwp/gaming/handling-device-lost-scenarios)
