# GPU 최적화 설계 — D3D11 범용 기준선

> 상태: 구현 전 성능 설계와 측정 gate  
> 기준일: 2026-08-04  
> 대상: Intel·AMD·NVIDIA x64, Qualcomm ARM64, Microsoft WARP  
> backend 정본: [backend 선택](backend-selection.md)  
> 벤더 정책: [GPU 범용성](gpu-vendor-portability.md)  
> 대형 이미지: [tile 설계](../06-large-images/image-source-tiling.md)  
> 실패·복구: [실패 모드 등록부](known-failure-modes.md)

## 0. 결론

Negaflow Windows의 GPU 최적화는 특정 GPU의 최대 점수를 얻는 작업이 아니다. 필수 기능과 수치
계약을 모든 지원 GPU에서 유지하면서 가장 느린 필수 장치의 대역폭·메모리·watchdog 위험을 낮추는
작업이다.

우선순위는 다음과 같다.

1. 잘못된 full-frame 처리와 CPU↔GPU 왕복 제거
2. ROI와 tile 단위 invalidation
3. point transform의 pass·intermediate 감소
4. spatial operation의 separable pass와 halo 재사용
5. deterministic histogram·measurement
6. 현재 DXGI budget 안의 resource pool·cache
7. 실제 벤더별 thread-group permutation
8. CPU/WARP를 포함한 복구
9. 그 뒤에만 NVIDIA CUDA 같은 선택 tier

GPU가 빠르다는 이유로 algorithm, bit depth, ICC, output quality, defect threshold를 바꾸지 않는다.

## 1. 고정 기준선

~~~text
API                 Direct3D 11
feature level       11_0
shader              SM 5.0 / FXC / DXBC
effect graph        Direct2D 1.1 custom effects
compute             같은 D3D11 device의 DirectCompute
presentation        DXGI flip-model + SwapChainPanel
software            WARP
CPU                 scalar/reference + 선택 SIMD
~~~

Direct3D 11 feature level 11_0의 compute shader는 그룹당 최대 1,024 thread, 차원별 제한,
32 KiB thread-group shared memory와 최대 8 UAV라는 공통 API 상한을 제공한다. 이 상한은 좋은
튜닝값이 아니다. 1,024 thread나 32 KiB를 모두 사용하면 register/shared-memory 압박으로 여러
GPU에서 occupancy가 떨어질 수 있다.

다음은 기준선이 아니다.

- D3D12
- Shader Model 6
- wave/subgroup intrinsic
- 특정 wave width
- vendor extension
- DirectML
- Work Graphs
- CUDA

이들은 공통 경로의 정확성과 기능을 대체하지 않는다.

## 2. macOS에서 가져오는 성능 근거

현재 macOS 코드·과거 계측에서 다음 교훈을 가져온다.

- 자동 결함 검출의 큰 병목은 scratch detector와 top-hat 계열 spatial processing이다.
- 해당 경로는 연산량만이 아니라 메모리 대역폭에 민감하다.
- 단순 CPU thread 증가나 cache 전치만으로 유의미한 개선이 나오지 않은 구간이 있다.
- 임계값·SNR·검출 의미를 바꾼 최적화는 제품 품질 회귀다.

이 근거는 Windows에서 GPU가 자동으로 빠르다는 증거가 아니다. Windows implementation은 실제
Intel·AMD·NVIDIA·Qualcomm과 CPU 결과를 다시 측정한다.

## 3. 성능 비용 모델

각 stage의 비용을 다음 합으로 본다.

~~~text
total latency
  = decode 또는 source tile 준비
  + CPU parameter·measurement
  + upload
  + GPU pass와 intermediate traffic
  + synchronization/readback
  + display 또는 encode
  + cache·journal commit
~~~

shader 하나의 microsecond만 줄이고 upload, intermediate, readback이 늘면 end-to-end 최적화가 아니다.

### 3.1 기록할 단위

- source pixel과 byte 수
- active ROI와 halo pixel 수
- decoded tile count
- GPU pass·dispatch count
- SRV/UAV/RTV 전환
- transient texture bytes
- current DXGI local/non-local budget와 usage
- upload/readback bytes
- CPU submit·wait
- GPU duration
- UI pointer-to-present
- export first-file preparation과 steady-state throughput

### 3.2 preview와 export

preview는 viewport와 scale에 맞춰 덜 처리할 수 있지만 다른 수학이나 낮은 품질 preset을 쓰지 않는다.
export는 전체 extent를 처리하되 같은 stage 의미와 색 관리 경계를 사용한다.

성능 보고에는 다음을 분리한다.

- 첫 source open
- 첫 render graph build
- 첫 shader/effect registration
- warm parameter-only update
- viewport pan
- export 첫 파일 준비
- 배치 steady state
- 마지막 encode·commit

## 4. operation 분류와 기본 backend

| operation | v1 기본 후보 | 최적화 방향 | CPU 역할 |
|---|---|---|---|
| unary point transform | D2D custom pixel effect | linking·constant update | scalar oracle·fallback |
| multi-input same-coordinate combine | D2D custom effect | branch materialization 최소화 | oracle·fallback |
| color matrix·transfer | D2D built-in 또는 custom | domain·precision 먼저 | LittleCMS/CPU reference |
| Gaussian·box blur | D2D 또는 DirectCompute | separable·halo·tile | small ROI·fallback |
| median·morphology | DirectCompute | local window·line algorithm 비교 | 완전 경로 |
| histogram integer bins | DirectCompute 또는 CPU | local bins·bounded merge | deterministic 기준 |
| floating statistics | CPU 또는 deterministic hybrid | 고정 partial layout | 최종 결정 경로 |
| 3D LUT | D2D LookupTable3D 후보 | cache·interpolation | trilinear reference |
| deterministic noise | HLSL integer hash | absolute coordinate | 같은 hash |
| resampling | D2D/WIC/custom | phase·filter·ROI | conformance |
| canvas composite | D2D/DXGI | dirty rect·present | WARP |

이 표는 구현 전에 API 이름으로 성능을 확정하지 않는다. 같은 수학과 resource 계약의 비교
스파이크를 통과해야 한다.

## 5. point transform과 shader linking

현재 custom stitchable kernel은 31개다.

- 단일 image input 18개
- 다중 image input 13개
- kernel 내부 임의 이웃 sampling 0개
- 공간 producer 결과가 필요한 combine 9개

따라서 31개 current-coordinate kernel은 Direct2D simple-sampling authoring 후보지만 전체 graph를
한 pass로 합치는 대상 수가 아니다.

### 5.1 authoring 원칙

- 모든 effect에 독립 실행 가능한 full pixel shader를 제공한다.
- 연결 가치가 있는 pixel effect에는 export function artifact를 함께 제공한다.
- input sampling type을 simple/complex로 정확히 선언한다.
- full shader와 export function의 constant-buffer ABI를 일치시킨다.
- link 실패 여부와 무관하게 같은 결과를 낸다.
- runtime이 실제로 합친 pass 수를 trace한다.

### 5.2 연결이 끊기는 정상 경계

- blur·median·morphology
- compute transform
- complex sampling
- resampling·coordinate mapping
- histogram·readback
- display/output color transform
- cached branch
- multi-consumer branch

9개 spatial-dependent combine은 blur·median·box-mean producer 뒤에 있다. combine 자체를 linkable하게
만들 수 있어도 producer 결과의 materialization이 필요할 수 있다.

### 5.3 측정

- linked/unlinked output conformance
- actual pass count
- intermediate surface count와 bytes
- graph build·effect registration time
- parameter update가 graph rebuild를 일으키는지
- driver별 linking 차이
- small ROI와 full image
- WARP

linking은 성능 최적화다. 정밀도 문제를 자동 해결하거나 고정 pass 수를 보장하지 않는다.

## 6. spatial filter와 separable pass

Gaussian, box, top-hat의 일부는 2D kernel을 horizontal + vertical pass로 분해할 수 있다.

~~~text
2D direct        O(width × height × radius²)
separable        O(width × height × radius)
~~~

실제 이득은 arithmetic뿐 아니라 intermediate write/read, cache와 halo 중복에 달려 있다.

### 6.1 tile과 halo

~~~text
requested output tile
  └─ input tile = output tile를 역매핑한 영역 + effect halo
~~~

각 effect는 다음을 제공한다.

- output rect에서 필요한 input rect 계산
- input rect에서 보장할 output rect
- border mode
- scale/transform에 따른 radius
- alpha와 premultiplication
- 최대 halo

tile scheduler는 chain의 halo를 합성하되 source extent를 벗어난 sample의 clamp/mirror/zero 정책을
명시한다. Core Image의 clamp-to-extent 의미를 Direct2D 기본값으로 추측하지 않는다.

### 6.2 groupshared 사용

groupshared memory는 여러 thread가 겹쳐 읽는 source와 kernel weight를 한 번 가져오는 데 유용하다.
그러나 모든 spatial operation이 groupshared로 빨라지는 것은 아니다.

비교한다.

- texture cache에 맡긴 direct sampling
- horizontal/vertical separable sampling
- groupshared tile + halo
- bilinear tap packing
- CPU line/tile algorithm

groupshared byte 계산:

~~~text
(tileWidth + 2 × radiusX)
× (tileHeight + 2 × radiusY)
× channelCount
× bytesPerChannel
× bufferedPlaneCount
~~~

32 KiB API 상한을 목표값으로 채우지 않는다. compiler의 register 사용과 실제 active group을 함께 본다.

### 6.3 시작 permutation

제품 기본값을 하나로 고정하기 전에 다음처럼 작은 후보 집합을 offline compile한다.

| 분류 | 후보 |
|---|---|
| point 2D | 8×8, 16×8, 16×16 |
| horizontal filter | 64×1, 128×1, 256×1 |
| vertical filter | 1×64, 1×128 또는 8×16 |
| reduction | 64, 128, 256 |

512·1,024 thread는 실제 전체 graph 이득이 있을 때만 후보로 추가한다. 특정 GPU의 warp/wave 또는
CU/SM occupancy 숫자를 공통 상수로 사용하지 않는다.

### 6.4 weight precision

pixel과 intermediate는 FP32 계약을 유지한다. filter coefficient를 FP16으로 저장하는 최적화는
다음을 모두 통과할 때만 허용한다.

- coefficient normalization
- impulse response
- flat-field neutrality
- edge/halo
- repeated-pass drift
- 모든 vendor와 WARP
- 실제 memory 또는 speed 이득

지원 hardware에서 FP16이 빠르다는 일반론만으로 승인하지 않는다.

## 7. median·morphology·top-hat

결함 검출은 큰 spatial window와 memory traffic 때문에 별도 설계가 필요하다.

### 7.1 후보

- small fixed window: local compare/sort network
- separable morphology: van Herk/Gil-Werman 또는 deque형 line algorithm
- 큰 radius: multi-pass 또는 hierarchy
- CPU: cache-friendly line tiles와 thread pool
- GPU: halo tile, row/column pass, bounded dispatch

algorithm 변경은 결과 의미를 바꿀 수 있다. 후보가 같은 이름의 filter를 만든다고 동등한 것은 아니다.

### 7.2 동등성

- impulse와 salt-and-pepper
- one-pixel scratch
- diagonal scratch
- border scratch
- flat noise
- real dust/scratch mask
- threshold 근처 candidate

binary mask만 비교하지 않는다. intermediate contrast field, score, connected component와 최종 recipe를
단계별로 비교한다.

### 7.3 성능

- source read bytes
- intermediate count
- halo overhead
- dispatch duration
- CPU/GPU overlap
- mask readback
- candidate compaction

GPU에서 mask를 만들고 즉시 full mask를 CPU로 읽으면 이득을 잃을 수 있다. candidate count·bounding
box·compact record만 읽는 경로와 비교한다.

## 8. histogram과 reduction

histogram·measurement는 속도보다 결정성이 우선이다.

### 8.1 integer histogram

기본 후보:

1. thread-group별 local bins
2. group 내부 merge
3. global integer bins에 bounded merge
4. CPU가 percentile·policy를 계산

fixed 32-lane warp private-bin 알고리즘을 공통 경로로 사용하지 않는다. SM5 기준선에는 portable wave
intrinsic 계약이 없고 실제 hardware subgroup width가 다를 수 있다.

### 8.2 contention

다음을 dataset별로 측정한다.

- 균일 ramp
- 한 bin에 몰린 flat image
- 어두운 negative
- saturated channel
- real scan

분포가 균일한 synthetic benchmark만으로 atomic strategy를 고르지 않는다.

### 8.3 floating reduction

mean·variance·covariance는 덧셈 순서가 결과에 영향을 준다.

후보:

- CPU double reference
- GPU fixed tile partial + CPU deterministic final
- GPU pairwise tree with fixed topology
- compensated summation의 비용 비교

auto parameter가 임계값을 넘나들면 GPU 측정 결과를 채택하지 않는다. 픽셀 전체를 CPU로 내릴 필요
없이 작은 measurement stage만 CPU로 고정할 수 있다.

### 8.4 readback

- 작은 staging ring 사용
- request/session/revision identity
- non-blocking completion query 또는 event
- UI thread wait 금지
- stale result 폐기
- timeout과 device-lost 처리

## 9. deterministic noise

grain과 dither는 tile·thread·backend에 따라 패턴이 달라지면 안 된다.

입력:

- absolute pixel x/y
- document/frame identity
- explicit seed
- stream/domain ID
- algorithm version

generic grain, density grain, dither는 서로 다른 stream ID를 쓴다. HLSL과 CPU는 같은 fixed-width integer
hash와 overflow 의미를 사용한다.

금지:

- dispatch order
- thread-group ID만 사용
- frame마다 implicit random state
- wall clock
- GPU vendor
- tile origin을 absolute coordinate로 착각

검증:

- tile 크기 변경
- pan·zoom
- x64·ARM64
- CPU·WARP·hardware GPU
- export 재시도
- batch order 변경

## 10. resource lifetime과 pool

### 10.1 transient texture key

pool key에는 최소한 다음이 포함된다.

- width/height
- DXGI format
- bind flags
- mip count
- sample count
- color/alpha semantic
- device generation
- usage/access

크기만 같다고 mask, linear color, display surface를 재사용하지 않는다.

### 10.2 graph lifetime

compile-time graph가 아니라 request lifetime을 기준으로 마지막 consumer를 계산한다.

~~~text
source tile
→ branch A
→ branch B
→ combine
→ display/export
~~~

branch가 남아 있는 동안 source/intermediate를 pool에 돌려보내지 않는다. async GPU completion 전에
resource를 재사용하지 않는다.

### 10.3 budget

IDXGIAdapter3::QueryVideoMemoryInfo로 local/non-local segment의 Budget, CurrentUsage,
AvailableForReservation을 확인한다.

정책:

- dedicated VRAM 숫자를 고정 cache 크기로 쓰지 않는다.
- UMA의 shared memory를 무료 VRAM으로 취급하지 않는다.
- budget notification 또는 주기적 query로 pressure를 감지한다.
- soft limit에서 prefetch와 derived cache를 줄인다.
- hard limit 전에 transient reserve를 남긴다.
- allocation 실패 뒤 같은 요청을 무한 재시도하지 않는다.
- cache eviction은 원본·recipe를 지우지 않는다.

### 10.4 release order

device lost 시:

1. 새 render 요청 중지
2. old generation completion/callback 무효화
3. GPU-derived cache와 effect instance 해제
4. device/context/swap chain 재생성
5. capability·format 재검사
6. 현재 document와 immutable recipe로 재렌더

사용자 편집 state는 GPU resource에만 존재하면 안 된다.

## 11. upload·readback·동기화

### 11.1 upload

- decoded tile을 contiguous working layout으로 준비
- row pitch를 명시적으로 처리
- immutable source와 frequently updated mask를 분리
- 같은 tile의 반복 upload 방지
- dGPU와 UMA를 같은 비용 모델로 가정하지 않음
- upload staging pool에 backpressure 적용

### 11.2 readback

가능하면 GPU 결과를 다음 GPU stage 또는 display/export에 유지한다. CPU가 필요한 결과만 작게 읽는다.

- histogram bins
- measurement scalars
- compact defect candidate
- diagnostic probe

full-frame readback은 CPU encoder가 실제로 필요할 때 tile stream으로 수행한다.

### 11.3 context와 flush

ID3D11DeviceContext Flush를 진행률 표시나 “확실한 완료” 용도로 남발하지 않는다. 실제 dependency,
query completion, present 또는 encode handoff가 요구할 때만 사용한다.

UI thread가 GetData polling loop에서 대기하지 않는다.

## 12. D2D와 DirectCompute 경계

같은 D3D11 device를 공유해도 hazard와 ownership이 자동으로 사라지지 않는다.

operation transition마다 기록:

- previous writer
- next reader/writer
- bound SRV/UAV/RTV
- unbind 필요
- D2D BeginDraw/EndDraw 경계
- resource lifetime
- async completion

D3D11은 D3D12식 explicit barrier API가 없지만 잘못된 동시 binding과 stale completion을 허용하지 않는다.

비교 스파이크:

- D2D compute transform
- raw D3D11 compute
- D2D pixel effect
- CPU

같은 texture를 쓰는 것만으로 zero-cost interop라고 표현하지 않는다.

## 13. large image와 watchdog

단일 거대 texture나 단일 긴 dispatch를 전제로 하지 않는다.

### 13.1 texture dimension

D3D11 Texture2D 한 변의 일반 상한은 16,384 pixel이다. 이 크기의 RGBA32F surface 하나는 약
4 GiB이므로 dimension 안에 들어온다는 사실이 메모리 안전을 뜻하지 않는다. intermediate가 여러 개면
즉시 budget을 넘을 수 있다.

### 13.2 tile scheduling

- source의 논리 extent와 physical tile 분리
- operation별 halo
- bounded in-flight tile
- viewport priority
- export sequential 또는 bounded parallel
- cache key에 scale·recipe revision·color transform 포함
- cancel point를 tile/dispatch 경계에 둠

### 13.3 TDR

TdrDelay registry 변경을 사용자 요구사항으로 만들지 않는다.

- slowest supported Intel iGPU·Qualcomm UMA에서 측정
- p95뿐 아니라 p99 dispatch duration
- UI composition과 export 동시 부하
- thermal sustained run
- 큰 radius와 pathological image
- device removal injection

safe tile 상한은 API 문서에서 추정하지 않고 operation×device class 측정으로 정한다.

## 14. UMA와 dGPU

### UMA

집중 항목:

- CPU와 GPU가 같은 physical memory를 쓴다고 upload가 항상 무료인 것은 아님
- page residency와 bandwidth 경쟁
- CPU decode·GPU render 동시 부하
- system RAM pressure
- integrated display와 power state

### dGPU

집중 항목:

- PCIe upload/readback
- dedicated/local budget
- hybrid display의 cross-adapter copy
- Optimus/graphics preference
- external monitor

backend 기능은 같게 유지하고 queue depth·prefetch·tile size 같은 실행 policy만 capability와 measurement로
바꾼다.

## 15. CPU와 GPU의 작업 분배

CPU가 충분히 빠르고 전환 비용이 큰 작업은 CPU에 남긴다.

CPU 우선 후보:

- 작은 ROI
- 작은 histogram/measurement final
- metadata·ICC parsing
- short line morphology
- tiny thumbnail
- GPU device lost 중 recovery export

GPU 우선 후보:

- 대형 pointwise graph
- 큰 blur·spatial filter
- full-resolution defect field
- canvas present
- large batch의 반복 graph

crossover는 pixel 수 하나로만 정하지 않는다.

- source가 이미 CPU/GPU 어디에 있는가
- 다음 consumer
- current queue
- device budget
- operation radius
- encode path
- preview deadline

runtime microbenchmark로 매번 결정하는 복잡한 scheduler를 v1에 넣지 않는다. 대표 corpus에서 승인한
작은 policy table로 시작한다.

## 16. thread-group permutation 정책

하나의 HLSL source에서 offline permutation을 만들 수 있다.

manifest:

~~~text
logical kernel
entry point
numthreads
TGSM bytes
resource bindings
compiler version/options
DXBC hash
minimum feature level
validated adapter classes
numeric contract version
~~~

선택은 vendor 이름이 아니라 capability와 승인된 profile class를 사용한다. 알려진 driver bug
workaround만 device/driver range를 좁게 분기한다.

permutation 수를 무한히 늘리지 않는다. 기본 하나와 실제로 이득이 큰 소수 후보만 유지한다. 각
permutation은 전체 conformance matrix를 통과한다.

## 17. 선택적 FP16

FP16을 쓰지 않는 기본 이유:

- intermediate extended range와 누적 오차
- hardware마다 처리량 차이
- conversion traffic
- Direct2D built-in의 실제 precision
- WARP/CPU 동등성

허용 후보:

- 정확히 bounded된 mask
- 충분한 error budget이 있는 coefficient
- transient weight table
- 결과가 FP32 reference를 통과한 isolated operation

working RGB, negative density, tone, measurement accumulator는 FP32 기준을 유지한다.

## 18. CUDA의 위치

CUDA는 NVIDIA 전용 선택 backend 후보이며 v1 critical path가 아니다.

재검토에 필요한 조건:

1. D3D11·CPU 구현과 골든이 완성됨
2. PIX/ETW/자체 trace가 NVIDIA에서 실제 병목을 특정
3. interop, sync, copy, runtime load와 package까지 포함한 end-to-end 비교
4. 20% 이상 또는 사용자에게 의미 있는 절대 시간 단축
5. CUDA 미설치·load 실패·driver mismatch에서 D3D11로 안전 전환
6. 결과·metadata·progress·cancel이 기준 경로와 동등
7. 라이선스·재배포·SBOM·보안 승인

CUDA 전용 기능, preset, 품질 option을 만들지 않는다. 한 operation이 CUDA를 쓰더라도 전체 graph와
다른 vendor의 기능은 동일하다.

## 19. benchmark corpus

### 19.1 합성

- neutral/primary gradient
- impulse·edge·checkerboard
- flat one-bin histogram
- random noise
- long scratch·diagonal scratch
- alpha edge
- extreme aspect panorama

### 19.2 실제

- 일반 24MP digital
- 50MP camera
- 100MP 이상 film scan
- dense grain
- dust/scratch가 많은 scan
- wide-gamut/highlight
- RAW 조건부
- TIFF 16-bit/float

실제 corpus는 license·provenance와 개인정보를 기록하고 CI 공개 가능/내부 전용을 분리한다.

## 20. benchmark 시나리오

| 시나리오 | 측정 |
|---|---|
| first open | decode, graph build, first present |
| Develop drag | pointer-to-present p50/p95/p99 |
| pan at 100% | tile miss, frame pacing |
| fit preview | downsample, graph passes |
| histogram update | GPU/CPU sync, determinism |
| defect auto | field·candidate·recipe |
| single export | first-file preparation, encode, commit |
| batch export | throughput, memory, backpressure |
| device lost | recovery latency, state preservation |
| low budget | eviction, fallback, user-visible error |

warm-only benchmark를 제품 속도로 보고하지 않는다.

## 21. 결과 검증

### 21.1 수치

- max/percentile absolute error
- relative error
- neutral channel delta
- luminance percentile
- clipped pixel count
- histogram exactness
- recipe identity
- mask IoU와 component difference
- ICC·metadata

### 21.2 성능

- p50/p95/p99
- CPU wall·active time
- GPU duration
- peak CPU/GPU memory
- upload/readback
- energy·thermal 조건
- sustained throughput

### 21.3 사용자 경험

- UI thread stall
- pointer-to-present
- progress first movement
- cancellation latency
- app responsiveness
- failure message와 recovery

한 평균 숫자로 승인하지 않는다.

## 22. 벤더별 최소 확인

| 군 | 집중 항목 |
|---|---|
| Intel iGPU | 낮은 bandwidth, shared budget, OEM driver |
| Intel Arc | discrete budget, driver version, hybrid display |
| AMD APU | UMA와 power state |
| AMD Radeon | LDS/register permutation, multi-monitor |
| NVIDIA laptop/dGPU | PCIe, Optimus, Studio/Game driver |
| Qualcomm ARM64 | native DLL, Adreno format, UMA, thermal |
| WARP | shader/effect conformance와 복구 |

각 군의 최신 고성능 장치 한 대만으로 지원을 선언하지 않는다. 하한·일반·최신 범위를 release
hardware manifest에 고정한다.

## 23. CI와 hardware lab

### 모든 변경

- scalar x64
- scalar ARM64 compile·가능하면 실행
- WARP shader/effect registration
- WARP numeric golden
- shader manifest·DXBC reproducibility
- CPU↔GPU conformance

### scheduled hardware

- Intel
- AMD
- NVIDIA
- Qualcomm ARM64
- hybrid GPU
- memory pressure
- device lost
- long batch

hardware lab의 이전 green 결과는 새 driver/toolchain/shader hash에 자동 승계되지 않는다.

## 24. 최적화 승인 gate

모든 최적화는 다음을 통과한다.

- [ ] 실제 top bottleneck을 profile로 확인
- [ ] before/after가 같은 source·build·dataset
- [ ] scalar/reference 수치 동등성
- [ ] Intel·AMD·NVIDIA·Qualcomm·WARP 영향
- [ ] x64·ARM64 CPU fallback
- [ ] preview·ordinary export·Quick Export·print 영향
- [ ] 24MP·50MP·100MP·panorama
- [ ] memory budget과 OOM
- [ ] cancel·device lost
- [ ] code size·shader permutation·maintenance 비용
- [ ] license/SBOM 영향

성능이 빨라져도 품질·결정성·복구·범용성이 나빠지면 승인하지 않는다.

## 25. 금지 패턴

- vendor ID로 core algorithm 선택
- NVIDIA warp=32 또는 AMD wave=64 가정
- one giant 1,024-thread group 고정
- TGSM 32 KiB를 항상 가득 사용
- hidden FP16/UNORM intermediate
- fast-math global flag
- full-frame upload/readback per slider tick
- UI thread GPU wait
- TdrDelay 변경 요구
- WARP 성공을 physical vendor 지원으로 주장
- 한 vendor benchmark만으로 공통 default 변경
- CUDA가 없으면 기능 숨김
- 해상도·quality·DPI·ICC를 낮춰 속도 달성
- GPU 실패 시 original 또는 stale render를 export

## 26. 공식 참고

- [Direct3D 11 compute shader overview](https://learn.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-compute-shader)
- [Direct3D 11 features](https://learn.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-features)
- [Direct3D resource limits](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-resources-limits)
- [DXGI video-memory budget](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_4/nf-dxgi1_4-idxgiadapter3-queryvideomemoryinfo)
- [Direct2D performance guidance](https://learn.microsoft.com/en-us/windows/win32/direct2d/improving-direct2d-performance)
- [Direct2D effect shader linking](https://learn.microsoft.com/en-us/windows/win32/direct2d/effect-shader-linking)
- [Direct2D precision and clipping](https://learn.microsoft.com/en-us/windows/win32/direct2d/precision-and-clipping-in-effect-graphs)
- [D3D11 tiled resources](https://learn.microsoft.com/en-us/windows/win32/direct3d11/tiled-resources)
- [Handle device removed](https://learn.microsoft.com/en-us/windows/uwp/gaming/handling-device-lost-scenarios)

GPUOpen·NVIDIA 자료는 vendor hardware의 최적화 아이디어를 이해하는 보조 자료로 사용할 수 있지만,
공통 D3D11 계약과 전체 vendor matrix를 대체하지 않는다.
